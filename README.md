# RHCL ROSA Sydney/Melbourne Demo

This repo now passes the base domain as a runtime variable.

Use `DOMAIN` as the base domain only, and the manifests will render `greenblue.${DOMAIN}`.

Examples:

```bash
DOMAIN=sandbox3271.opentlc.com ./scripts/render-overlay.sh manifests/overlays/sydney/letsencrypt-production | grep -E 'hostname:|hostnames:'

DOMAIN=sandbox3271.opentlc.com ./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
DOMAIN=sandbox3271.opentlc.com ./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

Important:

- Do not run `oc apply -k` directly for overlays that contain `${DOMAIN}`.
- `oc apply -k` and `oc kustomize` do not substitute shell variables by themselves.
- The helper scripts render the manifests through `envsubst` before applying.
- `DOMAIN` must be a real lowercase base domain, for example `sandbox3271.opentlc.com`.

Verification:

```bash
DOMAIN=sandbox3271.opentlc.com ./scripts/render-overlay.sh manifests/overlays/sydney/letsencrypt-production | grep -E 'hostname:|hostnames:'
```

Expected output:

```yaml
hostname: greenblue.sandbox3271.opentlc.com
hostnames:
  - greenblue.sandbox3271.opentlc.com
```


## Applying overlays with DOMAIN

Use the helper script so the base domain is rendered into `greenblue.${DOMAIN}`:

```bash
DOMAIN=sandbox5278.opentlc.com ./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production
DOMAIN=sandbox5278.opentlc.com ./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production
```

If a cluster still has an older Deployment created from a previous selector layout, the script will automatically delete and recreate the rendered Deployment, then re-apply the manifest.
