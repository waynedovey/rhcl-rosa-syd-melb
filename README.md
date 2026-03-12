# RHCL on ROSA Sydney + Melbourne with Kustomize and Let's Encrypt

This repo deploys a two-cluster Red Hat Connectivity Link setup across:

- `rosa-syd`
- `rosa-melb`

It publishes a shared external hostname:

- `greenblue.sandbox3573.opentlc.com`

and includes:

- OpenShift Service Mesh 3 as the Gateway API provider
- RHCL `DNSPolicy` for weighted DNS across both clusters
- RHCL `TLSPolicy` for TLS on the shared Gateway
- self-signed bootstrap or Let's Encrypt Route53 DNS-01
- demo application backends and `HTTPRoute`
- Kustomize overlays per cluster and certificate mode
- helper scripts for secrets, STS role annotation, apply, verify, direct testing, and traffic switching

## What this repo does

This repo configures the application and RHCL layers. It does **not** install operators automatically and it does **not** create AWS IAM roles or the Route53 hosted zone for you.

The repo does deploy:

- `istio-system` and `istio-cni` namespaces
- `Istio` and `IstioCNI`
- `api-gateway` and `demo-app` namespaces
- shared `Gateway`
- `DNSPolicy`
- `TLSPolicy`
- `ClusterIssuer`
- Sydney backend returning `hello from sydney green`
- Melbourne backend returning `hello from melbourne blue`
- `HTTPRoute` for the shared hostname

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

### Cluster prerequisites

You need two working ROSA STS clusters:

- Sydney cluster context: `rosa-syd`
- Melbourne cluster context: `rosa-melb`

### Operators required on both clusters

Install these from **OperatorHub** on **both** clusters before applying the manifests in this repo:

1. **Red Hat Connectivity Link**
2. **Red Hat OpenShift Service Mesh 3**
3. **cert-manager Operator for Red Hat OpenShift**

Recommended settings:

- use **Manual** approval where ROSA STS warns that operator upgrades may require IAM permission updates
- wait until each operator shows **Succeeded** before moving on

### AWS and DNS prerequisites

You need:

- AWS CLI configured against the AWS account that owns the Route53 hosted zone
- Route53 hosted zone already created and delegated for `sandbox3573.opentlc.com`
- Hosted zone ID: `Z07828883BTBHTW06APRZ`
- shared external hostname: `greenblue.sandbox3573.opentlc.com`
- Let's Encrypt email: `wdovey@gmail.com`

### cert-manager Route53 prerequisites for ROSA STS

For Let's Encrypt DNS-01 on ROSA STS you also need:

- an IAM role for the Sydney cert-manager service account
- an IAM role for the Melbourne cert-manager service account
- those roles must allow Route53 changes for hosted zone `Z07828883BTBHTW06APRZ`
- the `cert-manager` service account on each cluster annotated with the correct role ARN

This repo includes the script to annotate the service account, but it does not create the IAM role for you.

### Local tools required

- `oc`
- `kubectl` optional but useful
- `kustomize` optional if you prefer `kustomize build`; `oc apply -k` is enough
- `aws`
- `dig`
- `openssl`
- `curl`

## 1. Prepare ROSA contexts

Log into both clusters, then rename the contexts if needed:

```bash
oc config get-contexts -o name
oc config rename-context '<melb-context-name>' rosa-melb
oc config rename-context '<syd-context-name>' rosa-syd
oc config get-contexts
```

Quick validation:

```bash
oc --context=rosa-syd whoami
oc --context=rosa-melb whoami
```

## 2. Verify operators are installed on both clusters

Check Service Mesh, RHCL, and cert-manager:

```bash
oc --context=rosa-syd get csv -A | egrep 'connectivity|kuadrant|service-mesh|cert-manager'
oc --context=rosa-melb get csv -A | egrep 'connectivity|kuadrant|service-mesh|cert-manager'
```

You should see all three operators in a healthy state before continuing.

## 3. Create the RHCL Route53 secret on both clusters

Export AWS credentials with write access to the hosted zone:

```bash
export AWS_ACCESS_KEY_ID='<route53-access-key-id>'
export AWS_SECRET_ACCESS_KEY='<route53-secret-access-key>'
export AWS_REGION='ap-southeast-2'
```

Create the secret in `api-gateway` on both clusters:

```bash
./scripts/create-route53-secret.sh rosa-syd
./scripts/create-route53-secret.sh rosa-melb
```

Verify:

```bash
oc --context=rosa-syd -n api-gateway get secret aws-credentials
oc --context=rosa-melb -n api-gateway get secret aws-credentials
```

## 4. Configure cert-manager for ROSA STS

Annotate the `cert-manager` service account with the IAM role ARN created for Route53 DNS-01.

```bash
./scripts/annotate-cert-manager-sa.sh rosa-syd arn:aws:iam::<ACCOUNT_ID>:role/rosa-syd-cert-manager-operator
./scripts/annotate-cert-manager-sa.sh rosa-melb arn:aws:iam::<ACCOUNT_ID>:role/rosa-melb-cert-manager-operator
```

Verify:

```bash
oc --context=rosa-syd -n cert-manager get sa cert-manager -o yaml | grep eks.amazonaws.com/role-arn
oc --context=rosa-melb -n cert-manager get sa cert-manager -o yaml | grep eks.amazonaws.com/role-arn
```

## 5. Deploy the Service Mesh runtime

Even if the Service Mesh operator is installed, you still need to create the runtime resources.

Create namespaces:

```bash
oc --context=rosa-syd create namespace istio-system --dry-run=client -o yaml | oc apply -f -
oc --context=rosa-syd create namespace istio-cni --dry-run=client -o yaml | oc apply -f -

oc --context=rosa-melb create namespace istio-system --dry-run=client -o yaml | oc apply -f -
oc --context=rosa-melb create namespace istio-cni --dry-run=client -o yaml | oc apply -f -
```

Then apply the base:

```bash
oc --context=rosa-syd apply -k manifests/base
oc --context=rosa-melb apply -k manifests/base
```

Verify:

```bash
oc --context=rosa-syd get gatewayclass
oc --context=rosa-melb get gatewayclass
oc --context=rosa-syd get pods -n istio-system
oc --context=rosa-syd get pods -n istio-cni
oc --context=rosa-melb get pods -n istio-system
oc --context=rosa-melb get pods -n istio-cni
```

## 6. Bootstrap with self-signed certs

This is the easiest first successful path. It proves:

- Gateway API provider
- RHCL DNS
- backend apps
- TLS
- traffic steering

Apply overlays:

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

If local DNS caching causes trouble on macOS:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## 7. Move to Let's Encrypt staging

Apply staging overlays:

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
openssl s_client -connect greenblue.sandbox3573.opentlc.com:443 \
  -servername greenblue.sandbox3573.opentlc.com </dev/null 2>/dev/null | \
  openssl x509 -noout -issuer -subject -dates
```

## 8. Promote to Let's Encrypt production

Apply production overlays:

```bash
./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

Re-check the certificate:

```bash
openssl s_client -connect greenblue.sandbox3573.opentlc.com:443 \
  -servername greenblue.sandbox3573.opentlc.com </dev/null 2>/dev/null | \
  openssl x509 -noout -issuer -subject -dates
```

Test:

```bash
curl -v https://greenblue.sandbox3573.opentlc.com
```

## 9. Validate public DNS

```bash
dig sandbox3573.opentlc.com NS +noall +answer
dig greenblue.sandbox3573.opentlc.com +noall +answer
curl -v https://greenblue.sandbox3573.opentlc.com
```

If you want to test each cluster directly while keeping the correct SNI/hostname:

```bash
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com ae2663d3b278c46cda6cc207c6b64f0c-743541281.ap-southeast-4.elb.amazonaws.com
```

## 10. Switch traffic between Sydney and Melbourne

All traffic to Melbourne:

```bash
./scripts/switch-to-melbourne.sh
```

All traffic to Sydney:

```bash
./scripts/switch-to-sydney.sh
```

Check DNS after the switch:

```bash
dig greenblue.sandbox3573.opentlc.com +noall +answer
```

## 11. Kustomize overlays

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

## 12. Full deployment order

Use this order if you are building the environment from scratch:

1. log into both ROSA clusters and set contexts to `rosa-syd` and `rosa-melb`
2. install operators on both clusters:
   - RHCL
   - Service Mesh 3
   - cert-manager
3. create or verify Route53 hosted zone and delegation for `sandbox3573.opentlc.com`
4. create the cert-manager IAM roles for ROSA STS Route53 DNS-01
5. annotate the cert-manager service account on both clusters
6. create the Route53 secret in `api-gateway`
7. apply `manifests/base` to both clusters
8. apply self-signed overlays to both clusters
9. verify Gateway, DNSPolicy, TLSPolicy, certs, and app reachability
10. apply Let’s Encrypt staging overlays
11. validate ACME issuance
12. apply Let’s Encrypt production overlays
13. test public HTTPS access
14. use the switch scripts to move traffic between Sydney and Melbourne

## 13. Troubleshooting

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
aws route53 list-resource-record-sets --hosted-zone-id Z07828883BTBHTW06APRZ \
  --query "ResourceRecordSets[?contains(Name, 'greenblue') || contains(Name, 'klb.greenblue')]"
```

### macOS curl cannot resolve but dig works

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Test each cluster directly

```bash
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com a5718f247bd254aa98a39e824691648b-1501888680.ap-southeast-2.elb.amazonaws.com
./scripts/test-direct.sh greenblue.sandbox3573.opentlc.com ae2663d3b278c46cda6cc207c6b64f0c-743541281.ap-southeast-4.elb.amazonaws.com
```
