#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <oc-context>"
  exit 1
}

[[ $# -eq 1 ]] || usage
CTX="$1"
ROLE_ARN="$(oc --context="$CTX" -n cert-manager get sa cert-manager -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}')"

if [[ -z "$ROLE_ARN" ]]; then
  echo "No eks.amazonaws.com/role-arn annotation found on cert-manager service account in context $CTX" >&2
  exit 2
fi

echo "$ROLE_ARN"
