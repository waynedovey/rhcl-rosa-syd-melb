# RHCL on ROSA (Sydney + Melbourne) with Kustomize

This repo deploys:

- Red Hat Connectivity Link / Kuadrant Gateway policies
- OpenShift Service Mesh 3 runtime (`Istio` + `IstioCNI`)
- a demo app in each cluster
- shared external DNS via Route 53
- TLS via either self-signed certs or Let's Encrypt DNS-01
- traffic shifting between Sydney and Melbourne using `DNSPolicy` weights

Validated hostname pattern used in this repo:

- `greenblue.${DOMAIN}`

At apply time, `DOMAIN` is passed as the **base domain** from your shell environment, for example:

- `DOMAIN=$DOMAIN`
- rendered hostname: `greenblue.$DOMAIN`

Route 53 hosted zone ID is resolved dynamically from `DOMAIN` by the helper scripts in this repo.

Validated Let's Encrypt email:

- `wdovey@gmail.com`

## What this repo does and does not do

This repo **does** include:

- complete manifests for app + Gateway + RHCL + TLS
- Kustomize overlays for Sydney and Melbourne
- helper scripts for IAM, secrets, annotation, restart, cleanup, verification, and rendered apply

This repo **does not** install Operators automatically from OperatorHub. Those are prerequisites and are documented below.

---

## Prerequisites

### 1. Tools

You need:

- `oc`
- `aws`
- `jq`
- `envsubst`
- `kustomize` support via `oc kustomize`
- access to both ROSA clusters

On macOS, `envsubst` is commonly provided by `gettext`.

### 2. ROSA contexts

```bash
oc config get-contexts -o name
```

```bash
oc config rename-context default/api-rosa-syd-wyt2-p3-openshiftapps-com:443/cluster-admin rosa-syd
oc config rename-context default/api-rosa-melb-zwxe-p3-openshiftapps-com:443/cluster-admin rosa-melb
```

Expected contexts:

- `rosa-syd`
- `rosa-melb`

Verify:

```bash
oc --context=rosa-syd whoami
oc --context=rosa-melb whoami
```

### 3. Route 53 hosted zone and delegation

This repo assumes the public hosted zone already exists and is delegated correctly:

```bash
export DOMAIN='sandbox931.opentlc.com'
```

Resolve the zone dynamically from the base domain:

```bash
./scripts/resolve-hosted-zone-id.sh "$DOMAIN"
```

You can also export it explicitly if you want to inspect or override it:

```bash
export HOSTED_ZONE_ID="$(./scripts/resolve-hosted-zone-id.sh "$DOMAIN")"

echo "$HOSTED_ZONE_ID"
```

The helper scripts in this repo will auto-resolve `HOSTED_ZONE_ID` from `DOMAIN` if you do not set it yourself.

### 4. Operators — install via Kustomize

This repo now installs all three required operators via Kustomize instead of the
OperatorHub UI. A single helper script handles everything:

1. Creates (or reuses) the cert-manager operator IAM role for each cluster.
2. Renders the Kustomize operator overlays with the correct role ARNs injected.
3. Applies the rendered manifests to both clusters.

```bash
DOMAIN=$DOMAIN ./scripts/install-operators.sh
```

Operators installed on **both** Sydney and Melbourne:

| Operator | Namespace | Channel |
|---|---|---|
| Red Hat Connectivity Link | `openshift-operators` | `stable` |
| Red Hat OpenShift Service Mesh 3 | `openshift-operators` | `stable` |
| cert-manager Operator for Red Hat OpenShift | `cert-manager-operator` | `stable-v1` |

Wait for all CSVs to reach `Succeeded` before continuing:

```bash
oc --context=rosa-syd  get csv -n openshift-operators
oc --context=rosa-syd  get csv -n cert-manager-operator
oc --context=rosa-melb get csv -n openshift-operators
oc --context=rosa-melb get csv -n cert-manager-operator
```

#### cert-manager operator role ARNs (reference)

If you need to retrieve or inspect the role ARNs without re-running the full
install, run the underlying script directly:

```bash
# Sydney
DOMAIN=$DOMAIN ./scripts/create-cert-manager-operator-role.sh \
  --cluster-name rosa-syd \
  --oc-context rosa-syd

# Melbourne
DOMAIN=$DOMAIN ./scripts/create-cert-manager-operator-role.sh \
  --cluster-name rosa-melb \
  --oc-context rosa-melb
```

Both commands are idempotent. If the role already exists they print the
existing ARN and exit without making changes.

#### Operator Kustomize layout

```text
manifests/operators/
  base/
    kustomization.yaml
    operatorgroup.yaml                  # global OperatorGroup for openshift-operators
    subscription-rhcl.yaml             # Red Hat Connectivity Link
    subscription-servicemesh.yaml      # OpenShift Service Mesh 3
    cert-manager-operator-namespace.yaml
    operatorgroup-cert-manager.yaml    # scoped OperatorGroup for cert-manager-operator ns
    subscription-cert-manager.yaml     # cert-manager (ROLEARN placeholder)
  overlays/
    sydney/
      kustomization.yaml               # patches ROLEARN with rosa-syd ARN
    melbourne/
      kustomization.yaml               # patches ROLEARN with rosa-melb ARN
```

### 5. cert-manager Operator role ARN prerequisite (manual reference)

On ROSA STS the cert-manager Subscription `spec.config.env[ROLEARN]` must
contain the cluster-specific role ARN. The `install-operators.sh` script handles
this automatically. The underlying role creation script is idempotent and safe
to re-run at any time.

### 6. cert-manager controller Route 53 role prerequisite

The cert-manager **controller** needs a Route 53-capable role for DNS-01.

Use the same role generated by `create-cert-manager-operator-role.sh` **only if** its trust policy is for:

- `system:serviceaccount:cert-manager:cert-manager`

and it has Route 53 policy attached.

This repo’s role creation script does that.

---

## Important note about DOMAIN rendering

Do **not** run `oc apply -k` directly for overlays that contain `${DOMAIN}` and `${HOSTED_ZONE_ID}`.

`oc apply -k` and `oc kustomize` do **not** substitute shell variables by themselves. This repo uses helper scripts to render the manifests through `envsubst` before applying. Those scripts also auto-resolve `HOSTED_ZONE_ID` from `DOMAIN` unless you explicitly export `HOSTED_ZONE_ID` yourself.

Use:

```bash
DOMAIN=$DOMAIN ./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
DOMAIN=$DOMAIN ./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

To inspect the rendered YAML before applying:

```bash
DOMAIN=$DOMAIN ./scripts/render-overlay.sh manifests/overlays/sydney/letsencrypt-production | grep -E 'hostname:|hostnames:|hostedZoneID:'
```

Expected:

```yaml
hostname: greenblue.$DOMAIN
hostnames:
  - greenblue.$DOMAIN
```

---

## Deployment order

Follow this exact order.

### Step 1. Create Service Mesh namespaces and runtime

#### Sydney

```bash
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/selfsigned
```

#### Melbourne

```bash
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/selfsigned
```

This creates:

- `istio-system`
- `istio-cni`
- `api-gateway`
- `demo-app`
- `Istio`
- `IstioCNI`
- demo backend app and route
- Gateway

### Step 2. Create Route 53 provider secret in `api-gateway`

#### Sydney

```bash
export AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
export AWS_REGION=ap-southeast-2
./scripts/create-route53-secret.sh rosa-syd
```

#### Melbourne

```bash
./scripts/create-route53-secret.sh rosa-melb
```

The script prefers environment variables for AWS credentials and region. Positional arguments are still supported as a fallback, but environment variables are the recommended and safer default.

### Step 3. Ensure cert-manager operand exists

On both clusters, verify:

```bash
oc --context=rosa-syd get ns cert-manager
oc --context=rosa-syd get pods -n cert-manager

oc --context=rosa-melb get ns cert-manager
oc --context=rosa-melb get pods -n cert-manager
```

Do **not** continue until the cert-manager namespace and pods exist.

### Step 4. Annotate cert-manager service account with Route 53 role

This step is required for Let's Encrypt DNS-01.

This environment uses a **single AWS account** for both clusters. To make the workflow reusable across accounts, derive `ACCOUNT_ID` dynamically from the active AWS CLI identity, with the option to override it if needed.

Run this with `bash`:

```bash
bash <<'EOF'
set -euo pipefail

# Uses the active AWS CLI identity by default.
# Override only if you need to force a specific account:
# export ACCOUNT_ID="<target-account-id>"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  echo "ERROR: Failed to determine ACCOUNT_ID from AWS CLI." >&2
  echo "Run 'aws sts get-caller-identity' and make sure your AWS credentials are set." >&2
  exit 1
fi

declare -A CERT_MANAGER_ROLE_ARNS=(
  [rosa-syd]="arn:aws:iam::${ACCOUNT_ID}:role/rosa-syd-cert-manager-operator"
  [rosa-melb]="arn:aws:iam::${ACCOUNT_ID}:role/rosa-melb-cert-manager-operator"
)

for CTX in rosa-syd rosa-melb; do
  ROLE_ARN="${CERT_MANAGER_ROLE_ARNS[$CTX]}"
  echo "Annotating ${CTX} with ${ROLE_ARN}"

  ./scripts/annotate-cert-manager-sa.sh \
    "$CTX" \
    "$ROLE_ARN"

  echo -n "Live SA annotation for ${CTX}: "
  oc --context="$CTX" -n cert-manager get sa cert-manager \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
done
EOF
```

You can verify which account will be used with:

```bash
aws sts get-caller-identity
```

If your actual role names differ, keep the same dynamic `ACCOUNT_ID` logic and update only the role names in the `CERT_MANAGER_ROLE_ARNS` map.

This script now:

- derives `ACCOUNT_ID` dynamically from the active AWS CLI identity
- annotates `serviceaccount/cert-manager`
- deletes the cert-manager pod
- waits for the new pod
- verifies `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`

### Step 5. Restart Kuadrant after cert-manager install

If cert-manager was installed after Kuadrant, restart the Kuadrant operator on both clusters.

#### Sydney

```bash
./scripts/restart-kuadrant.sh rosa-syd
```

#### Melbourne

```bash
./scripts/restart-kuadrant.sh rosa-melb
```

This uses the correct deployment:

- `openshift-operators/deployment/kuadrant-operator-controller-manager`

It does **not** delete all pods in `openshift-operators`.

### Step 6. Apply Let's Encrypt production overlays

#### Sydney

```bash
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
```

#### Melbourne

```bash
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

### Step 7. If ACME issuance gets stuck, clean it up and re-apply

#### Sydney

```bash
./scripts/cleanup-acme.sh rosa-syd
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
```

#### Melbourne

```bash
./scripts/cleanup-acme.sh rosa-melb
export DOMAIN="$DOMAIN"
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

This deletes stale:

- `CertificateRequest`
- `Certificate`
- `Order`
- `Challenge`

---

## Verify

### TLS policy

```bash
oc --context=rosa-syd -n api-gateway get tlspolicy shared-app-gw-tls -o yaml
oc --context=rosa-melb -n api-gateway get tlspolicy shared-app-gw-tls -o yaml
```

Expected:

- `Accepted=True`
- `Enforced=True`

### DNS policy

```bash
oc --context=rosa-syd -n api-gateway get dnspolicy shared-app-dns -o yaml
oc --context=rosa-melb -n api-gateway get dnspolicy shared-app-dns -o yaml
```

Expected eventually:

- `SubResourcesHealthy=True`
- `Enforced=True`

It is normal to see `AwaitingValidation` briefly.

### Certificates

```bash
oc --context=rosa-syd -n api-gateway get certificate,certificaterequest
oc --context=rosa-melb -n api-gateway get certificate,certificaterequest
```

Expected:

- `Certificate READY=True`
- `CertificateRequest READY=True`

### Test direct ELBs with SNI

#### Sydney

```bash
curl -vk \
  --connect-to greenblue.${DOMAIN}:443:a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com:443 \
  https://greenblue.${DOMAIN}
```

#### Melbourne

```bash
curl -vk \
  --connect-to greenblue.${DOMAIN}:443:af4950c338c0947a4bde6182f37a3d52-408642302.ap-southeast-4.elb.amazonaws.com:443 \
  https://greenblue.${DOMAIN}
```

### Test public name

```bash
curl -vk https://greenblue.${DOMAIN}
```

---

## Traffic shifting

### 100% Sydney

```bash
./scripts/set-weights.sh rosa-syd 100
./scripts/set-weights.sh rosa-melb 0
```

### 100% Melbourne

```bash
./scripts/set-weights.sh rosa-syd 0
./scripts/set-weights.sh rosa-melb 100
```

### 50 / 50

```bash
./scripts/set-weights.sh rosa-syd 50
./scripts/set-weights.sh rosa-melb 50
```

---

## Repo layout

```text
manifests/
  base/
  operators/
    base/
      kustomization.yaml
      operatorgroup.yaml
      subscription-rhcl.yaml
      subscription-servicemesh.yaml
      cert-manager-operator-namespace.yaml
      operatorgroup-cert-manager.yaml
      subscription-cert-manager.yaml
    overlays/
      sydney/
        kustomization.yaml
      melbourne/
        kustomization.yaml
  overlays/
    sydney/
      selfsigned/
      letsencrypt-staging/
      letsencrypt-production/
    melbourne/
      selfsigned/
      letsencrypt-staging/
      letsencrypt-production/
scripts/
  annotate-cert-manager-sa.sh
  apply-overlay.sh
  cleanup-acme.sh
  create-cert-manager-operator-role.sh
  create-route53-secret.sh
  install-operators.sh
  render-overlay.sh
  resolve-hosted-zone-id.sh
  restart-kuadrant.sh
  set-weights.sh
```

---

## Lessons learned / important fixes

These are baked into this repo because they were required in the lab:

- After annotating `serviceaccount/cert-manager`, you must **delete the cert-manager pod** so the new pod gets AWS web identity env vars.
- On ROSA STS, cert-manager DNS-01 must show:
  - `AWS_ROLE_ARN`
  - `AWS_WEB_IDENTITY_TOKEN_FILE`
- If cert-manager is installed after Kuadrant, restart:
  - `openshift-operators/deployment/kuadrant-operator-controller-manager`
- Do **not** delete all pods in `openshift-operators`.
- `oc get ... -w` only supports one resource type at a time.
- If ACME gets stuck, delete stale `CertificateRequest`, `Certificate`, `Order`, and `Challenge` resources and re-apply.
- Hosted zone IDs must match the actual Route 53 zone for `${DOMAIN}`. This repo now resolves `HOSTED_ZONE_ID` dynamically from `DOMAIN`.
- If a cluster still has an older Deployment from a previous selector layout, `scripts/apply-overlay.sh` will detect the immutable selector error, delete the rendered Deployment, and re-apply.

