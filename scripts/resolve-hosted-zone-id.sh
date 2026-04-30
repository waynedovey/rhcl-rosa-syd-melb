#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [domain]"
  echo "Resolves the public Route 53 hosted zone ID for DOMAIN."
  echo "Examples:"
  echo "  $0 sandbox3733.opentlc.com"
  echo "  DOMAIN=sandbox3733.opentlc.com $0"
  exit 1
}

DOMAIN_INPUT="${1:-${DOMAIN:-}}"
if [[ -z "$DOMAIN_INPUT" ]]; then
  usage
fi

DOMAIN_FQDN="${DOMAIN_INPUT%.}."

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed or not in PATH." >&2
  exit 1
fi

ZONE_ID="$(aws route53 list-hosted-zones-by-name       --dns-name "$DOMAIN_FQDN"       --output json | jq -r --arg d "$DOMAIN_FQDN" '
    .HostedZones[]
    | select(.Name == $d)
    | select(.Config.PrivateZone == false)
    | .Id
  ' | head -n1 | sed 's|/hostedzone/||')"

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
  echo "Error: could not resolve a public hosted zone ID for $DOMAIN_INPUT" >&2
  exit 1
fi

echo "$ZONE_ID"
