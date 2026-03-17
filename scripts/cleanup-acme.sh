#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: DOMAIN=<base-domain> $0 <oc-context>"
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 rosa-syd"
  exit 1
fi

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: DOMAIN environment variable is required."
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 <oc-context>"
  exit 1
fi

CONTEXT="$1"
CITY="${CONTEXT#rosa-}"
OVERLAY="manifests/overlays/${CITY}/letsencrypt-production"

oc --context="${CONTEXT}" -n api-gateway delete certificaterequest,order,challenge --all --ignore-not-found=true
"$(dirname "$0")/apply-overlay.sh" "$CONTEXT" "$OVERLAY"
