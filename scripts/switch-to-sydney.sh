#!/usr/bin/env bash
set -euo pipefail
oc --context=rosa-syd -n api-gateway patch dnspolicy shared-app-dns --type=merge -p '
spec:
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 100
'
oc --context=rosa-melb -n api-gateway patch dnspolicy shared-app-dns --type=merge -p '
spec:
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 0
'
