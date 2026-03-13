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
```

## Prerequisites

- `oc` logged into both clusters with contexts named `rosa-syd` and `rosa-melb`
- Red Hat Connectivity Link operator installed on both clusters
- Red Hat OpenShift Service Mesh 3 installed on both clusters
- cert-manager Operator for Red Hat OpenShift installed on both clusters
- AWS CLI configured for the account that owns Route53 zone `sandbox3573.opentlc.com`
- Route53 hosted zone ID: `Z07828883BTBHTW06APRZ`
- Let's Encrypt email: `wdovey@gmail.com`

## 1. Prepare ROSA contexts

Rename contexts if needed:

```bash
oc config get-contexts -o name
oc config rename-context '<melb-context-name>' rosa-melb
oc config rename-context '<syd-context-name>' rosa-syd
```

## 2. Create the RHCL Route53 secret on both clusters

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

## 3. Configure cert-manager for ROSA STS

Annotate the cert-manager service account with the IAM role ARN created for Route53 DNS-01.

```bash
./scripts/annotate-cert-manager-sa.sh rosa-syd arn:aws:iam::<ACCOUNT_ID>:role/rosa-syd-cert-manager-operator
./scripts/annotate-cert-manager-sa.sh rosa-melb arn:aws:iam::<ACCOUNT_ID>:role/rosa-melb-cert-manager-operator
```

## 4. Bootstrap with self-signed certs (optional but recommended)

This gets the gateway, DNS, backend apps, and TLS online quickly.

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/selfsigned
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/selfsigned
```

Verify:

```bash
./scripts/verify.sh rosa-syd rosa-melb
```

Direct tests with SNI preserved:

```bash
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com ae2663d3b278c46cda6cc207c6b64f0c-743541281.ap-southeast-4.elb.amazonaws.com
```

## 5. Move to Let's Encrypt staging

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-staging
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-staging
```

Watch certificate issuance:

```bash
oc --context=rosa-syd -n api-gateway get certificates,certificaterequests,secrets
oc --context=rosa-melb -n api-gateway get certificates,certificaterequests,secrets
```

Inspect the served certificate:

```bash
openssl s_client -connect greenblue.sandbox3573.opentlc.com:443   -servername greenblue.sandbox3573.opentlc.com </dev/null 2>/dev/null |   openssl x509 -noout -issuer -subject -dates
```

## 6. Promote to Let's Encrypt production

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

Re-check the certificate:

```bash
openssl s_client -connect greenblue.sandbox3573.opentlc.com:443   -servername greenblue.sandbox3573.opentlc.com </dev/null 2>/dev/null |   openssl x509 -noout -issuer -subject -dates
```

## 7. Validate public DNS

```bash
dig greenblue.sandbox3573.opentlc.com +noall +answer
curl -v https://greenblue.sandbox3573.opentlc.com
```

If your Mac still resolves stale data, flush DNS cache:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## 8. Switch traffic between Sydney and Melbourne

All traffic to Melbourne:

```bash
./scripts/switch-to-melbourne.sh
```

All traffic to Sydney:

```bash
./scripts/switch-to-sydney.sh
```

## 9. Kustomize overlays

Use these overlays directly:

- `manifests/overlays/sydney/selfsigned`
- `manifests/overlays/sydney/letsencrypt-staging`
- `manifests/overlays/sydney/letsencrypt-production`
- `manifests/overlays/melbourne/selfsigned`
- `manifests/overlays/melbourne/letsencrypt-staging`
- `manifests/overlays/melbourne/letsencrypt-production`

Examples:

```bash
oc --context=rosa-syd apply -k manifests/overlays/sydney/letsencrypt-production
oc --context=rosa-melb apply -k manifests/overlays/melbourne/letsencrypt-production
```

## 10. Notes

- The self-signed overlay keeps `allowInsecureCertificate: true` in `DNSPolicy`, which is fine for bootstrap and lab use.
- The Let's Encrypt overlays also keep that field; it is harmless but can be removed once you are fully on publicly trusted certs.
- Sydney overlay starts with DNS weight `100`, Melbourne with `0`.
- The gateway hostname is fixed in this repo to `greenblue.sandbox3573.opentlc.com`.

## 11. Troubleshooting

### Gateway not programmed

```bash
oc get gatewayclass
oc -n api-gateway describe gateway shared-app-gw
```

### TLS secret missing

```bash
oc --context=rosa-syd -n api-gateway get tlspolicy,certificates,certificaterequests,secrets
oc --context=rosa-melb -n api-gateway get tlspolicy,certificates,certificaterequests,secrets
```

### DNS not publishing

```bash
oc --context=rosa-syd -n api-gateway get dnspolicy shared-app-dns -o yaml
oc --context=rosa-melb -n api-gateway get dnspolicy shared-app-dns -o yaml
```

### Test each cluster directly

```bash
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com ae2663d3b278c46cda6cc207c6b64f0c-743541281.ap-southeast-4.elb.amazonaws.com
```

## Create the cert-manager Operator role ARN before OperatorHub install

On ROSA STS, the OperatorHub install page for the **cert-manager Operator for Red Hat OpenShift** asks for a **role ARN**.
Red Hat documents that, on STS clusters, this field should be the AWS IAM role ARN for the operator service account. For the
Route53 DNS-01 flow, Red Hat separately documents a second IAM role for the `cert-manager` controller itself. The repo now
includes a helper script to generate the **operator install role ARN** before you install the operator. citeturn101071search11turn858714search3turn101071search2

### Assumptions used by the script

The script defaults to the operator-recommended namespace and the common controller service account naming pattern:

- namespace: `cert-manager-operator`
- service account: `cert-manager-operator-controller-manager`
- role name: `<cluster-name>-cert-manager-operator`

If your install uses a different namespace or service account, pass them explicitly.

### Script location

```bash
scripts/create-cert-manager-operator-role.sh
```

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

The script prints the created **role ARN**. Paste that value into the OperatorHub **role ARN** field when installing the
cert-manager Operator for Red Hat OpenShift on each cluster.

### Optional extra policy attachment

If you need to attach an additional AWS policy to the operator role, create a policy JSON file and pass it with
`--policy-document`:

```bash
./scripts/create-cert-manager-operator-role.sh \
  --cluster-name rosa-syd \
  --oc-context rosa-syd \
  --policy-document ./iam/optional-extra-policy.json
```

### Important distinction

This operator install role is **not the same** as the Route53 DNS-01 role used by the cert-manager controller for
Let's Encrypt. Keep using the separate controller role and service account annotation for DNS-01 challenge solving.
