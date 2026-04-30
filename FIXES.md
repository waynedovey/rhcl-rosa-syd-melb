# Route 53 hosted zone ID fix

This repo no longer hardcodes the Route 53 hosted zone ID.

What changed:
- `scripts/resolve-hosted-zone-id.sh` resolves the public hosted zone ID from `DOMAIN`
- `scripts/apply-overlay.sh` auto-resolves `HOSTED_ZONE_ID` if not supplied
- `scripts/render-overlay.sh` auto-resolves `HOSTED_ZONE_ID` if not supplied
- `scripts/create-cert-manager-operator-role.sh` now accepts `--hosted-zone-id`, `--domain`, or `DOMAIN`, and uses the resolved zone when generating the Route 53 policy
- Let's Encrypt overlay ClusterIssuers now use `${HOSTED_ZONE_ID}` instead of a hardcoded zone
- empty `secretAccessKeySecretRef.name: ""` blocks were removed from the Route 53 solver config

Typical usage:

```bash
export DOMAIN="sandbox3733.opentlc.com"

./scripts/create-cert-manager-operator-role.sh --cluster-name rosa-syd --oc-context rosa-syd
./scripts/create-cert-manager-operator-role.sh --cluster-name rosa-melb --oc-context rosa-melb

./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```
