#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 <oc-context> [aws_access_key_id aws_secret_access_key aws_region]

Preferred:
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  export AWS_REGION=ap-southeast-2
  $0 rosa-syd
  $0 rosa-melb

Fallback positional form:
  $0 rosa-syd <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> ap-southeast-2
EOF
}

if [[ $# -lt 1 || $# -gt 4 ]]; then
  usage
  exit 1
fi

CTX="$1"
AWS_ACCESS_KEY_ID="${2:-${AWS_ACCESS_KEY_ID:-}}"
AWS_SECRET_ACCESS_KEY="${3:-${AWS_SECRET_ACCESS_KEY:-}}"
AWS_REGION="${4:-${AWS_REGION:-ap-southeast-2}}"

if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
  echo "ERROR: AWS credentials not provided."
  echo
  usage
  exit 1
fi

echo "Using context: ${CTX}"
echo "Using AWS region: ${AWS_REGION}"

oc --context="${CTX}" create namespace api-gateway --dry-run=client -o yaml |   oc --context="${CTX}" apply -f -

oc --context="${CTX}" -n api-gateway delete secret aws-credentials --ignore-not-found

oc --context="${CTX}" -n api-gateway create secret generic aws-credentials   --type=kuadrant.io/aws   --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"   --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"   --from-literal=AWS_REGION="${AWS_REGION}"

echo "Created secret api-gateway/aws-credentials on context ${CTX}"
