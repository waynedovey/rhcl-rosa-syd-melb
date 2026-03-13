#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <oc-context>"
  exit 1
fi
CTX="$1"
oc --context="$CTX" -n api-gateway delete certificaterequest shared-app-gw-https-1 --ignore-not-found
oc --context="$CTX" -n api-gateway delete certificate shared-app-gw-https --ignore-not-found
oc --context="$CTX" -n api-gateway delete order,challenge --all --ignore-not-found
