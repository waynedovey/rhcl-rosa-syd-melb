#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: DOMAIN=<base-domain> $0 <overlay-path>"
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi

OVERLAY="$1"

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: DOMAIN environment variable is required."
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 ${OVERLAY}"
  exit 1
fi

oc kustomize "${OVERLAY}" | envsubst '${DOMAIN}'
