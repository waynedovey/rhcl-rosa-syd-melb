#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Create an AWS IAM role ARN for the cert-manager Operator for Red Hat OpenShift on a ROSA STS cluster.

This script creates a trust policy for the operator service account and creates an IAM role that you can
paste into the OperatorHub "role ARN" field before installing the operator.

Defaults:
  namespace: cert-manager-operator
  service account: cert-manager-operator-controller-manager
  role name: <cluster-name>-cert-manager-operator

Examples:
  ./scripts/create-cert-manager-operator-role.sh \
    --cluster-name rosa-syd \
    --oc-context rosa-syd

  ./scripts/create-cert-manager-operator-role.sh \
    --cluster-name rosa-melb \
    --oc-context rosa-melb \
    --policy-document ./iam/optional-extra-policy.json

Arguments:
  --cluster-name NAME           Required. Friendly cluster name for the IAM role.
  --oc-context CONTEXT          Optional. oc context to query the cluster OIDC issuer.
  --oidc-endpoint HOST          Optional. OIDC issuer host without https://.
  --namespace NAME              Optional. Default: cert-manager-operator
  --service-account NAME        Optional. Default: cert-manager-operator-controller-manager
  --role-name NAME              Optional. Default: <cluster-name>-cert-manager-operator
  --policy-document PATH        Optional. JSON policy document to attach to the role.
  --policy-name NAME            Optional. Defaults to <role-name>-policy when --policy-document is used.
  --output-dir PATH             Optional. Default: ./generated/iam
  --tags k=v,k=v               Optional. Comma-separated AWS IAM tags.

Notes:
  * For the OperatorHub install screen on ROSA STS, Red Hat documents entering the ARN of the AWS IAM role
    for the operator service account. Use the ARN printed by this script in that field.
  * The Route53 DNS-01 role used by the cert-manager controller for Let's Encrypt is separate from this
    operator install role.
  * If your installed namespace or service account differ from the defaults, override them with flags.
USAGE
}

CLUSTER_NAME=""
OC_CONTEXT=""
OIDC_ENDPOINT=""
NAMESPACE="cert-manager-operator"
SERVICE_ACCOUNT="cert-manager-operator-controller-manager"
ROLE_NAME=""
POLICY_DOCUMENT=""
POLICY_NAME=""
OUTPUT_DIR="./generated/iam"
TAGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --oc-context) OC_CONTEXT="$2"; shift 2 ;;
    --oidc-endpoint) OIDC_ENDPOINT="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT="$2"; shift 2 ;;
    --role-name) ROLE_NAME="$2"; shift 2 ;;
    --policy-document) POLICY_DOCUMENT="$2"; shift 2 ;;
    --policy-name) POLICY_NAME="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "--cluster-name is required" >&2
  usage
  exit 1
fi

if [[ -z "$OIDC_ENDPOINT" ]]; then
  if [[ -n "$OC_CONTEXT" ]]; then
    OIDC_ENDPOINT="$(oc --context="$OC_CONTEXT" get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' 2>/dev/null | sed 's|^https://||')"
  fi
fi

if [[ -z "$OIDC_ENDPOINT" ]]; then
  echo "Unable to determine OIDC endpoint. Pass --oc-context or --oidc-endpoint." >&2
  exit 1
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_NAME="${ROLE_NAME:-${CLUSTER_NAME}-cert-manager-operator}"
POLICY_NAME="${POLICY_NAME:-${ROLE_NAME}-policy}"
mkdir -p "$OUTPUT_DIR"
TRUST_POLICY="$OUTPUT_DIR/${ROLE_NAME}-trust-policy.json"
ROLE_OUT="$OUTPUT_DIR/${ROLE_NAME}-role.json"

cat > "$TRUST_POLICY" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Condition": {
        "StringEquals": {
          "${OIDC_ENDPOINT}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
        }
      },
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity"
    }
  ]
}
JSON

echo "Creating IAM role: ${ROLE_NAME}"
CREATE_ARGS=(aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "file://${TRUST_POLICY}" --output json)
if [[ -n "$TAGS" ]]; then
  IFS=',' read -ra TAG_ARR <<< "$TAGS"
  TAG_ARGS=()
  for kv in "${TAG_ARR[@]}"; do
    KEY="${kv%%=*}"
    VALUE="${kv#*=}"
    TAG_ARGS+=(Key="$KEY",Value="$VALUE")
  done
  CREATE_ARGS+=(--tags "${TAG_ARGS[@]}")
fi
"${CREATE_ARGS[@]}" > "$ROLE_OUT"
ROLE_ARN="$(jq -r '.Role.Arn' "$ROLE_OUT")"

if [[ -n "$POLICY_DOCUMENT" ]]; then
  if [[ ! -f "$POLICY_DOCUMENT" ]]; then
    echo "Policy document not found: $POLICY_DOCUMENT" >&2
    exit 1
  fi
  POLICY_ARN="$(aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "file://${POLICY_DOCUMENT}" --query 'Policy.Arn' --output text)"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" >/dev/null
  echo "Attached policy: $POLICY_ARN"
else
  echo "No policy attached. This is fine if the operator itself does not need AWS API permissions in your setup."
fi

cat <<OUT

Created role ARN:
${ROLE_ARN}

Use this value in the OperatorHub "role ARN" field for the cert-manager Operator for Red Hat OpenShift.

Trust policy:
${TRUST_POLICY}

Assumed subject:
system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}
OUT
