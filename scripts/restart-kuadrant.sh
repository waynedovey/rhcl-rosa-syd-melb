#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <oc-context>"
  exit 1
fi
CTX="$1"
oc --context="$CTX" -n openshift-operators rollout restart deployment/kuadrant-operator-controller-manager
oc --context="$CTX" -n openshift-operators rollout status deployment/kuadrant-operator-controller-manager
