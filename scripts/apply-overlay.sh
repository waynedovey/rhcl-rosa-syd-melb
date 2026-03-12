#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <oc-context> <overlay-path>"
  echo "Example: $0 rosa-syd manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi
oc --context="$1" apply -k "$2"
