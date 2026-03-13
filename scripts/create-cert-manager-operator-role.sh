#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --cluster-name <name> --oc-context <context>"
  exit 1
}

CLUSTER_NAME=""
OC_CONTEXT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --oc-context) OC_CONTEXT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$CLUSTER_NAME" && -n "$OC_CONTEXT" ]] || usage

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
OIDC_URL="$(oc --context="$OC_CONTEXT" get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' 2>/dev/null || true)"
if [[ -z "$OIDC_URL" ]]; then
  echo "Could not discover serviceAccountIssuer from context $OC_CONTEXT"
  exit 1
fi
OIDC_ENDPOINT="${OIDC_URL#https://}"
ROLE_NAME="${CLUSTER_NAME}-cert-manager-operator"
POLICY_NAME="${CLUSTER_NAME}-cert-manager-policy"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/trust-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ENDPOINT}:sub": "system:serviceaccount:cert-manager:cert-manager"
        }
      }
    }
  ]
}
JSON

cat > "$TMPDIR/policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/Z07828883BTBHTW06APRZ"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
JSON

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"
  echo "IAM role already exists: $ROLE_NAME"
  echo "Use this role ARN in OperatorHub and for cert-manager Route53 annotation:"
  echo "$ARN"
  exit 0
fi

echo "Creating IAM role: $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "file://$TMPDIR/trust-policy.json" >/dev/null

if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" >/dev/null 2>&1; then
  aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "file://$TMPDIR/policy.json" >/dev/null
fi

aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" >/dev/null
ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"

echo "Created role ARN:"
echo "$ARN"
