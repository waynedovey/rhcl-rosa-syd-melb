#!/usr/bin/env bash
set -euo pipefail
for CTX in "$@"; do
  echo "=== $CTX ==="
  oc --context="$CTX" get gatewayclass || true
  oc --context="$CTX" -n api-gateway get gateway,dnspolicy,tlspolicy,secret || true
  oc --context="$CTX" -n api-gateway get certificates,certificaterequests || true
  oc --context="$CTX" -n demo-app get pods,svc,httproute || true
  echo
 done
