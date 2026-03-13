#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <oc-context> <role-arn>"
  exit 1
fi
CTX="$1"
ROLE_ARN="$2"

if ! oc --context="$CTX" get ns cert-manager >/dev/null 2>&1; then
  echo "cert-manager namespace not found on context $CTX. Install the cert-manager operator/operand first."
  exit 1
fi

oc --context="$CTX" -n cert-manager annotate serviceaccount cert-manager \
  eks.amazonaws.com/role-arn="$ROLE_ARN" --overwrite

oc --context="$CTX" -n cert-manager delete pods -l app.kubernetes.io/name=cert-manager
oc --context="$CTX" -n cert-manager rollout status deployment/cert-manager

POD="$(oc --context="$CTX" -n cert-manager get pods -l app.kubernetes.io/name=cert-manager -o jsonpath='{.items[0].metadata.name}')"
if oc --context="$CTX" -n cert-manager get pod "$POD" -o yaml | grep -q 'AWS_ROLE_ARN'; then
  echo "Verified AWS_ROLE_ARN and web identity token injection on pod $POD"
else
  echo "Warning: pod $POD does not show AWS_ROLE_ARN. Check pod yaml and cluster STS pod-role injection."
fi
