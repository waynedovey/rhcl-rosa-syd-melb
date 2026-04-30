#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: DOMAIN=<base-domain> [HOSTED_ZONE_ID=<zone-id>] $0 <oc-context> <overlay-path>"
  echo "Example: DOMAIN=sandbox3733.opentlc.com $0 rosa-syd manifests/overlays/sydney/letsencrypt-production"
  exit 1
fi

CONTEXT="$1"
OVERLAY="$2"

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: DOMAIN environment variable is required."
  echo "Example: DOMAIN=sandbox3733.opentlc.com $0 ${CONTEXT} ${OVERLAY}"
  exit 1
fi

if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
  HOSTED_ZONE_ID="$("$SCRIPT_DIR/resolve-hosted-zone-id.sh" "$DOMAIN")"
fi

TMP_RENDERED="$(mktemp)"
TMP_OUTPUT="$(mktemp)"
cleanup() {
  rm -f "$TMP_RENDERED" "$TMP_OUTPUT"
}
trap cleanup EXIT

echo "Using DOMAIN=${DOMAIN}"
echo "Using HOSTED_ZONE_ID=${HOSTED_ZONE_ID}"

oc kustomize "${OVERLAY}" | envsubst '${DOMAIN} ${HOSTED_ZONE_ID}' > "$TMP_RENDERED"

set +e
oc --context="${CONTEXT}" apply -f "$TMP_RENDERED" 2>&1 | tee "$TMP_OUTPUT"
RC=${PIPESTATUS[0]}
set -e

if [[ $RC -eq 0 ]]; then
  exit 0
fi

if grep -q 'field is immutable' "$TMP_OUTPUT" && grep -Eq '(Deployment\.apps|The Deployment |^Deployment )' "$TMP_OUTPUT"; then
  echo
  echo "Detected immutable Deployment selector from a previous manifest version."
  echo "Deleting rendered Deployments and re-applying them..."

  awk '
    function indent_of(s,   n,i,c) {
      n = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == " ") n++
        else break
      }
      return n
    }
    function emit() {
      if (kind == "Deployment" && name != "") {
        if (namespace == "") namespace = "default"
        print namespace "\t" name
      }
    }
    function reset_doc() {
      kind = ""
      name = ""
      namespace = "default"
      inmeta = 0
    }
    BEGIN { reset_doc() }
    /^---[[:space:]]*$/ { emit(); reset_doc(); next }
    {
      indent = indent_of($0)
      if (indent == 0 && $0 ~ /^kind:[[:space:]]*Deployment([[:space:]]*#.*)?$/) {
        kind = "Deployment"
        next
      }
      if (indent == 0 && $0 ~ /^metadata:[[:space:]]*$/) {
        inmeta = 1
        next
      }
      if (inmeta) {
        if (indent == 0 && $0 !~ /^[[:space:]]*$/) {
          inmeta = 0
        } else {
          if ($0 ~ /^[[:space:]]{2}name:[[:space:]]*/) {
            name = $0
            sub(/^[[:space:]]{2}name:[[:space:]]*/, "", name)
          } else if ($0 ~ /^[[:space:]]{2}namespace:[[:space:]]*/) {
            namespace = $0
            sub(/^[[:space:]]{2}namespace:[[:space:]]*/, "", namespace)
          }
        }
      }
    }
    END { emit() }
  ' "$TMP_RENDERED" | while IFS=$'\t' read -r namespace name; do
    [[ -z "$name" ]] && continue
    echo "oc --context=${CONTEXT} -n ${namespace} delete deployment ${name} --ignore-not-found"
    oc --context="${CONTEXT}" -n "${namespace}" delete deployment "$name" --ignore-not-found
  done

  echo
  oc --context="${CONTEXT}" apply -f "$TMP_RENDERED"
  exit 0
fi

exit $RC
