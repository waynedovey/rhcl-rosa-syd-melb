#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: DOMAIN=<base-domain> [HOSTED_ZONE_ID=<zone-id>] $0 <overlay-path>"
  echo "Example: DOMAIN=sandbox3733.opentlc.com $0 manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi

OVERLAY="$1"

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: DOMAIN environment variable is required."
  echo "Example: DOMAIN=sandbox3733.opentlc.com $0 ${OVERLAY}"
  exit 1
fi

if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
  HOSTED_ZONE_ID="$("$SCRIPT_DIR/resolve-hosted-zone-id.sh" "$DOMAIN")"
fi

echo "Using DOMAIN=${DOMAIN}" >&2
echo "Using HOSTED_ZONE_ID=${HOSTED_ZONE_ID}" >&2

oc kustomize "${OVERLAY}" | envsubst '${DOMAIN} ${HOSTED_ZONE_ID}'
