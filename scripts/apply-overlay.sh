#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <oc-context> <overlay-path>"
  echo "Example: DOMAIN=sandbox4065.opentlc.com $0 rosa-syd manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi

if [[ -z "${DOMAIN:-}" ]]; then
  echo "ERROR: DOMAIN environment variable is not set."
  echo "Example: export DOMAIN=sandbox4065.opentlc.com"
  exit 1
fi

if ! command -v kustomize >/dev/null 2>&1; then
  echo "ERROR: kustomize is required for dynamic DOMAIN rendering."
  echo "Install kustomize or render with 'oc kustomize' manually and pipe through envsubst."
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "ERROR: envsubst is required for dynamic DOMAIN rendering."
  echo "On macOS: brew install gettext && brew link --force gettext"
  exit 1
fi

overlay_path="$2"
kustomize build "$overlay_path" | envsubst '${DOMAIN}' | oc --context="$1" apply -f -
