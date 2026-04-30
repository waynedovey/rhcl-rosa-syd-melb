#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./cleanup-test.sh [context1 context2 ...]

Examples:
  ./cleanup-test.sh
  ./cleanup-test.sh rosa-syd
  ./cleanup-test.sh rosa-syd rosa-melb

Defaults:
  If no contexts are supplied, the script cleans:
    - rosa-syd
    - rosa-melb

What it does:
  - Deletes TLSPolicy, DNSPolicy, HTTPRoute, and Gateway
  - Removes finalizers from stuck ACME Challenges and Orders
  - Deletes Challenges, Orders, CertificateRequests, Certificates, and TLS Secrets
  - Deletes ClusterIssuer letsencrypt-production
  - Restarts cert-manager

Notes:
  - This is safe to run on macOS because it is a bash script, not pasted zsh loop text.
  - This gives you a clean retry path, but it will not fix AWS Route53 IAM permissions.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v oc >/dev/null 2>&1; then
  echo "Error: oc is not installed or not in PATH." >&2
  exit 1
fi

if [[ "$#" -gt 0 ]]; then
  CONTEXTS=("$@")
else
  CONTEXTS=("rosa-syd" "rosa-melb")
fi

remove_finalizers() {
  local ctx="$1"

  while IFS= read -r resource; do
    [[ -z "$resource" ]] && continue
    oc --context="$ctx" -n api-gateway patch "$resource" \
      --type=json \
      -p='[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
  done < <(oc --context="$ctx" -n api-gateway get challenges.acme.cert-manager.io -o name 2>/dev/null || true)

  while IFS= read -r resource; do
    [[ -z "$resource" ]] && continue
    oc --context="$ctx" -n api-gateway patch "$resource" \
      --type=json \
      -p='[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
  done < <(oc --context="$ctx" -n api-gateway get orders.acme.cert-manager.io -o name 2>/dev/null || true)
}

cleanup_context() {
  local ctx="$1"

  echo "=== CLEANING $ctx ==="

  oc --context="$ctx" -n api-gateway delete tlspolicy shared-app-gw-tls --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete dnspolicy shared-app-dns --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete httproute shared-app-route --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete gateway shared-app-gw --ignore-not-found=true --wait=false || true

  remove_finalizers "$ctx"

  oc --context="$ctx" -n api-gateway delete challenges.acme.cert-manager.io --all --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete orders.acme.cert-manager.io --all --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete certificaterequests.cert-manager.io --all --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete certificates.cert-manager.io --all --ignore-not-found=true --wait=false || true
  oc --context="$ctx" -n api-gateway delete secret api-shared-app-gw-tls --ignore-not-found=true || true
  oc --context="$ctx" -n api-gateway delete secret -l cert-manager.io/certificate-name=shared-app-gw-https --ignore-not-found=true || true

  oc --context="$ctx" delete clusterissuer letsencrypt-production --ignore-not-found=true || true

  oc --context="$ctx" -n cert-manager rollout restart deployment/cert-manager
  oc --context="$ctx" -n cert-manager rollout status deployment/cert-manager
}

verify_context() {
  local ctx="$1"

  echo
  echo "=== VERIFY $ctx ==="
  oc --context="$ctx" -n api-gateway get tlspolicy,dnspolicy,gateway,httproute 2>/dev/null || true
  oc --context="$ctx" -n api-gateway get challenges.acme.cert-manager.io 2>/dev/null || true
  oc --context="$ctx" -n api-gateway get orders.acme.cert-manager.io 2>/dev/null || true
  oc --context="$ctx" -n api-gateway get certificaterequests.cert-manager.io 2>/dev/null || true
  oc --context="$ctx" -n api-gateway get certificates.cert-manager.io 2>/dev/null || true
  oc --context="$ctx" -n api-gateway get secret api-shared-app-gw-tls 2>/dev/null || true
  oc --context="$ctx" get clusterissuer letsencrypt-production 2>/dev/null || true
}

for ctx in "${CONTEXTS[@]}"; do
  cleanup_context "$ctx"
done

for ctx in "${CONTEXTS[@]}"; do
  verify_context "$ctx"
done

echo
echo "Cleanup complete."
echo "You can now reapply one cluster at a time, for example:"
echo '  DOMAIN=sandbox3733.opentlc.com ./scripts/apply-overlay.sh rosa-syd manifests/overlays/sydney/letsencrypt-production'
echo '  DOMAIN=sandbox3733.opentlc.com ./scripts/apply-overlay.sh rosa-melb manifests/overlays/melbourne/letsencrypt-production'
