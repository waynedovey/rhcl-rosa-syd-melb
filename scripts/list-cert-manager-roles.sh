#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <oc-context> [<oc-context> ...]"
  exit 1
fi

for CTX in "$@"; do
  ROLE_ARN="$(oc --context="$CTX" -n cert-manager get sa cert-manager -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}')"
  ACCOUNT_ID="$(printf '%s' "$ROLE_ARN" | cut -d: -f5)"
  ROLE_NAME="${ROLE_ARN##*/}"
  printf '%s\t%s\t%s\n' "$CTX" "$ACCOUNT_ID" "$ROLE_ARN"
done
