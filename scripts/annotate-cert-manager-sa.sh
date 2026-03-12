#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <oc-context> <role-arn>"
  exit 1
fi
CTX="$1"
ROLE_ARN="$2"
oc --context="$CTX" -n cert-manager annotate serviceaccount cert-manager   eks.amazonaws.com/role-arn="$ROLE_ARN" --overwrite
oc --context="$CTX" patch certmanager.operator.openshift.io/cluster --type merge   -p '{"spec":{"controllerConfig":{"overrideArgs":["--dns01-recursive-nameservers-only","--dns01-recursive-nameservers=1.1.1.1:53"]}}}'
oc --context="$CTX" -n cert-manager delete pods -l app.kubernetes.io/name=cert-manager
