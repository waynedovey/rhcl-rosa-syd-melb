# RHCL on ROSA Sydney + Melbourne with Kustomize and Let's Encrypt

This repo deploys a two-cluster Red Hat Connectivity Link setup across:

- `rosa-syd`
- `rosa-melb`

It publishes a shared external hostname:

- `greenblue.sandbox3573.opentlc.com`

and supports:

- OpenShift Service Mesh 3 as the Gateway API provider
- RHCL `DNSPolicy` for weighted DNS across both clusters
- RHCL `TLSPolicy` for TLS on the shared Gateway
- self-signed bootstrap or Let's Encrypt Route53 DNS-01
- Kustomize overlays per cluster and certificate mode

## Repository layout

```text
manifests/
  base/
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
  create-cert-manager-operator-role.sh
  create-route53-secret.sh
```

## Prerequisites

You need the following before applying manifests:

- `oc` logged into both clusters with contexts named `rosa-syd` and `rosa-melb`
- AWS CLI configured for the account that owns Route53 zone `sandbox3573.opentlc.com`
- Route53 hosted zone ID: `Z07828883BTBHTW06APRZ`
- Let's Encrypt email: `wdovey@gmail.com`
- Red Hat Connectivity Link operator installed on both clusters
- Red Hat OpenShift Service Mesh 3 installed on both clusters
- cert-manager Operator for Red Hat OpenShift installed on both clusters

## Required operator and runtime order

Use this order from scratch:

1. Log into both ROSA clusters and create friendly contexts.
2. Generate the **cert-manager Operator** role ARN for each cluster.
3. Install the **cert-manager Operator for Red Hat OpenShift** in OperatorHub using that role ARN.
4. Install the **Red Hat Connectivity Link** operator.
5. Install the **Red Hat OpenShift Service Mesh 3** operator.
6. Create `istio-system` and `istio-cni` namespaces.
7. Create the `Istio` and `IstioCNI` runtime resources.
8. Create the RHCL Route53 secret in `api-gateway`.
9. Apply the Kustomize overlays.

## 1. Prepare ROSA contexts

Rename contexts if needed:

```bash
oc config get-contexts -o name
oc config rename-context '<melb-context-name>' rosa-melb
oc config rename-context '<syd-context-name>' rosa-syd
```

## 2. Create the cert-manager Operator role ARN before OperatorHub install

On ROSA STS, the OperatorHub install page for the **cert-manager Operator for Red Hat OpenShift** requires a **role ARN**.
This must exist **before** you install the operator.

The helper script below creates the AWS IAM role if it does not already exist.
If it already exists, it prints the existing ARN and exits successfully so you can paste it into OperatorHub.

Default assumptions used by the script:

- namespace: `cert-manager-operator`
- service account: `cert-manager-operator-controller-manager`
- role name: `<cluster-name>-cert-manager-operator`

### Sydney

```bash
./scripts/create-cert-manager-operator-role.sh \
  --cluster-name rosa-syd \
  --oc-context rosa-syd
```

### Melbourne

```bash
./scripts/create-cert-manager-operator-role.sh \
  --cluster-name rosa-melb \
  --oc-context rosa-melb
```

Paste the printed ARN into the OperatorHub **role ARN** field for the cert-manager Operator install.

## 3. Install required operators in OperatorHub

Install these on **both** clusters:

- **cert-manager Operator for Red Hat OpenShift**
  - Update channel: `stable-v1`
  - Installation mode: `All namespaces on the cluster`
  - Installed namespace: `cert-manager-operator`
  - Use the role ARN printed by `create-cert-manager-operator-role.sh`
- **Red Hat Connectivity Link**
- **Red Hat OpenShift Service Mesh 3**

## 4. Create Service Mesh runtime namespaces and resources

Create namespaces:

```bash
oc --context=rosa-syd create namespace istio-system --dry-run=client -o yaml | oc --context=rosa-syd apply -f -
oc --context=rosa-syd create namespace istio-cni --dry-run=client -o yaml | oc --context=rosa-syd apply -f -
oc --context=rosa-melb create namespace istio-system --dry-run=client -o yaml | oc --context=rosa-melb apply -f -
oc --context=rosa-melb create namespace istio-cni --dry-run=client -o yaml | oc --context=rosa-melb apply -f -
```

Create `Istio` and `IstioCNI` resources using the manifests in the repo, then verify a `gatewayclass` exists.

## 5. Create the RHCL Route53 secret on both clusters

Export AWS credentials with write access to the hosted zone:

```bash
export AWS_ACCESS_KEY_ID='<route53-access-key-id>'
export AWS_SECRET_ACCESS_KEY='<route53-secret-access-key>'
export AWS_REGION='ap-southeast-2'
```

Then create the secret:

```bash
./scripts/create-route53-secret.sh rosa-syd
./scripts/create-route53-secret.sh rosa-melb
```

This script now uses the supplied context for **both** namespace creation and secret creation.

## 6. Configure cert-manager for ROSA STS Route53 DNS-01

Annotate the `cert-manager` service account with the separate Route53 DNS-01 IAM role used by the cert-manager controller.
This is **not** the same as the operator install role created earlier.

```bash
./scripts/annotate-cert-manager-sa.sh rosa-syd arn:aws:iam::<ACCOUNT_ID>:role/rosa-syd-cert-manager-operator
./scripts/annotate-cert-manager-sa.sh rosa-melb arn:aws:iam::<ACCOUNT_ID>:role/rosa-melb-cert-manager-operator
```

## 7. Bootstrap with self-signed certs (optional but recommended)

This gets the gateway, DNS, backend apps, and TLS online quickly.

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/selfsigned
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/selfsigned
```

## 8. Move to Let's Encrypt staging

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-staging
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-staging
```

Watch certificate issuance:

```bash
oc --context=rosa-syd -n api-gateway get certificates,certificaterequests,secrets
oc --context=rosa-melb -n api-gateway get certificates,certificaterequests,secrets
```

## 9. Promote to Let's Encrypt production

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

Re-check the certificate:

```bash
openssl s_client -connect greenblue.sandbox3573.opentlc.com:443 -servername greenblue.sandbox3573.opentlc.com </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
```

## 10. Validate public DNS and app access

```bash
dig greenblue.sandbox3573.opentlc.com +noall +answer
curl -v https://greenblue.sandbox3573.opentlc.com
```

If your Mac still resolves stale data, flush DNS cache:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## 11. Switch traffic between Sydney and Melbourne

All traffic to Melbourne:

```bash
./scripts/switch-to-melbourne.sh
```

All traffic to Sydney:

```bash
./scripts/switch-to-sydney.sh
```

50/50 split:

```bash
oc --context=rosa-syd -n api-gateway patch dnspolicy shared-app-dns --type=merge -p '
spec:
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 50
'

oc --context=rosa-melb -n api-gateway patch dnspolicy shared-app-dns --type=merge -p '
spec:
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 50
'
```

## 12. Troubleshooting

### Operator role script says the role already exists

That is fine. The script prints the existing ARN and exits successfully. Use that ARN in OperatorHub.

### Route53 secret script says namespace not found

Use the updated script in this repo. It now applies the namespace using the same `oc` context passed on the command line.

### DNS works in `dig` but not `curl`

That is usually a local macOS DNS cache issue. Flush the cache and retry.

### Direct HTTPS ELB tests

Use SNI-preserving direct tests:

```bash
curl -vk --connect-to greenblue.sandbox3573.opentlc.com:443:a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com:443 https://greenblue.sandbox3573.opentlc.com
curl -vk --connect-to greenblue.sandbox3573.opentlc.com:443:ae2663d3b278c46cda6cc207c6b64f0c-743541281.ap-southeast-4.elb.amazonaws.com:443 https://greenblue.sandbox3573.opentlc.com
```
