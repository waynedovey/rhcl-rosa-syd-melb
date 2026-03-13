#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <oc-context> <weight>"
  exit 1
fi
CTX="$1"
WEIGHT="$2"
oc --context="$CTX" -n api-gateway patch dnspolicy shared-app-dns --type=merge -p "{\"spec\":{\"loadBalancing\":{\"defaultGeo\":true,\"geo\":\"GEO-NA\",\"weight\":${WEIGHT}}}}"
