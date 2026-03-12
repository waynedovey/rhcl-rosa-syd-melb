#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <oc-context>"
  exit 1
fi
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
CTX="$1"
oc --context="$CTX" create namespace api-gateway --dry-run=client -o yaml | oc apply -f -
oc --context="$CTX" -n api-gateway delete secret aws-credentials --ignore-not-found
oc --context="$CTX" -n api-gateway create secret generic aws-credentials   --type=kuadrant.io/aws   --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"   --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"   --from-literal=AWS_REGION="$AWS_REGION"
