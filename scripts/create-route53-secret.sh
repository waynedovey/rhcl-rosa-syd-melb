#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Create or replace the RHCL Route53 provider secret in api-gateway.

Required environment variables:
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
Optional:
  AWS_REGION (default: ap-southeast-2)

Usage:
  ./scripts/create-route53-secret.sh <oc-context>

Example:
  AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... ./scripts/create-route53-secret.sh rosa-syd
USAGE
}

CTX="${1:-}"
if [[ -z "$CTX" ]]; then
  usage
  exit 1
fi

: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"

oc --context="$CTX" create namespace api-gateway --dry-run=client -o yaml | oc --context="$CTX" apply -f -
oc --context="$CTX" -n api-gateway delete secret aws-credentials --ignore-not-found
oc --context="$CTX" -n api-gateway create secret generic aws-credentials \
  --type=kuadrant.io/aws \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="$AWS_REGION"

echo "Created/updated secret aws-credentials in api-gateway on context: $CTX"
