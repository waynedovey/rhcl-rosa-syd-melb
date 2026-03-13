#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <oc-context> <aws-access-key-id> <aws-secret-access-key> <aws-region>"
  exit 1
fi
CTX="$1"
AWS_ACCESS_KEY_ID="$2"
AWS_SECRET_ACCESS_KEY="$3"
AWS_REGION="$4"

oc --context="$CTX" create namespace api-gateway --dry-run=client -o yaml | oc --context="$CTX" apply -f -
oc --context="$CTX" -n api-gateway delete secret aws-credentials --ignore-not-found
oc --context="$CTX" -n api-gateway create secret generic aws-credentials \
  --type=kuadrant.io/aws \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="$AWS_REGION"
