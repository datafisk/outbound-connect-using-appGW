#!/bin/bash
# Add a TCP route for an Azure SQL failover group to an existing Application Gateway (Option 4).
# Dry run by default: prints the az commands. Pass --apply to execute them.
# NOT yet run against a live gateway; review the printed commands first.
#
# Usage: ./setup.sh <appgw-rg> <appgw-name> <fog-fqdn> <listener-port> [--apply]
#   e.g. ./setup.sh vpc-peered-cce-se my-appgw peter-fog.database.windows.net 1433 --apply
#
# Use a different <listener-port> per SQL failover group sharing the same AppGW.

set -e

if [ $# -lt 4 ]; then
    sed -n '2,9p' "$0"
    exit 1
fi

RG="$1"; GW="$2"; FQDN="$3"; PORT="$4"; APPLY="$5"
NAME="sql-${FQDN%%.*}-${PORT}"          # e.g. sql-peter-fog-1433
IDLE_SECONDS="${IDLE_SECONDS:-900}"      # keep above any client keepalive/idle interval
FRONTEND_IP="${FRONTEND_IP:-appGwPrivateFrontendIpIPv4}"
PRIORITY="${PRIORITY:-120}"

run() {
    echo "+ $*"
    [ "$APPLY" = "--apply" ] && "$@"
    return 0
}

echo "Gateway: $GW ($RG)  failover group: $FQDN  listener port: $PORT"
[ "$APPLY" = "--apply" ] || echo "(dry run, pass --apply to execute)"
echo

# The backend pool holds the failover group FQDN. The gateway resolves it through the
# VNet's DNS (private DNS zone privatelink.database.windows.net linked to the AppGW VNet),
# so the CNAME chain ends at the private endpoint of whichever server is primary.
run az network application-gateway address-pool create \
    --gateway-name "$GW" -g "$RG" -n "pool-$NAME" --servers "$FQDN"

run az network application-gateway frontend-port create \
    --gateway-name "$GW" -g "$RG" -n "port_$PORT" --port "$PORT"

run az network application-gateway settings create \
    --gateway-name "$GW" -g "$RG" -n "settings-$NAME" \
    --port 1433 --protocol Tcp --timeout "$IDLE_SECONDS"

run az network application-gateway listener create \
    --gateway-name "$GW" -g "$RG" -n "listener-$NAME" \
    --frontend-port "port_$PORT" --frontend-ip "$FRONTEND_IP"

run az network application-gateway rule create \
    --gateway-name "$GW" -g "$RG" -n "route-$NAME" \
    --listener "listener-$NAME" --address-pool "pool-$NAME" \
    --settings "settings-$NAME" --priority "$PRIORITY"

echo
echo "Next:"
echo "  az network application-gateway show-backend-health --name $GW -g $RG"
echo "  Point the Confluent EAP/egress DNS entry for $FQDN at the AppGW private frontend IP"
echo "  (connector keeps connection.host=$FQDN and connection.port=$PORT)."
