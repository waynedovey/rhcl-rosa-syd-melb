#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <hostname> <elb-hostname>"
  exit 1
fi
curl -vk --connect-to "$1:443:$2:443" "https://$1"
