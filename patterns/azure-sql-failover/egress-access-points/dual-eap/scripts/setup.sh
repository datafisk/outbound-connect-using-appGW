#!/bin/bash
# Preflight for the dual-EAP option (Option 3).
# Read-only: checks Azure private endpoints and public DNS, prints the values
# needed to create the Confluent egress access points and DNS entries.
#
# Usage: ./setup.sh <resource-group> <failover-group-name> <server-1> <server-2>

set -e

if [ $# -ne 4 ]; then
    echo "Usage: $0 <resource-group> <failover-group-name> <server-1> <server-2>"
    exit 1
fi

RG="$1"; FOG="$2"; S1="$3"; S2="$4"
DOMAIN="database.windows.net"
STATUS=0

echo "=== Azure SQL servers ==="
for S in "$S1" "$S2"; do
    ID=$(az sql server show -g "$RG" -n "$S" --query id -o tsv)
    LOC=$(az sql server show -g "$RG" -n "$S" --query location -o tsv)
    echo "$S ($LOC)"
    echo "  resource id : $ID"
    echo "  subresource : sqlServer"
    echo "  egress DNS  : $S.$DOMAIN -> <EAP for $LOC>"
done

echo
echo "=== Private endpoints connected to these servers ==="
for S in "$S1" "$S2"; do
    COUNT=$(az sql server show -g "$RG" -n "$S" \
        --query "length(privateEndpointConnections[?properties.privateLinkServiceConnectionState.status=='Approved'])" -o tsv)
    echo "$S: $COUNT approved private endpoint connection(s)"
    [ "$COUNT" = "0" ] && { echo "  WARNING: no approved private endpoints"; STATUS=1; }
done

echo
echo "=== Failover group ==="
az sql failover-group show -g "$RG" -s "$S1" -n "$FOG" \
    --query "{role:replicationRole, state:replicationState, partner:partnerServers[0].id}" -o json 2>/dev/null \
    || { echo "Could not read failover group $FOG on $S1 (try swapping the server arguments)"; STATUS=1; }

echo
echo "=== Public DNS (what the connector resolves for $FOG) ==="
if command -v dig >/dev/null 2>&1; then
    dig +short "$FOG.$DOMAIN" CNAME
    echo "(first lines should be the CNAME chain ending at the current primary)"
else
    echo "dig not found; skipping DNS check"
fi

echo
echo "REMINDER: create egress DNS entries for $S1.$DOMAIN and $S2.$DOMAIN only."
echo "          Do NOT create one for $FOG.$DOMAIN."
exit $STATUS
