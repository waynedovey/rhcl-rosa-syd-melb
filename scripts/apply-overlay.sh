#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: DOMAIN=<base-domain> $0 <oc-context> <overlay-path>"
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 rosa-syd manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi

CONTEXT="$1"
OVERLAY="$2"

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: DOMAIN environment variable is required."
  echo "Example: DOMAIN=sandbox3271.opentlc.com $0 ${CONTEXT} ${OVERLAY}"
  exit 1
fi

oc kustomize "${OVERLAY}" | envsubst '${DOMAIN}' | oc --context="${CONTEXT}" apply -f -
