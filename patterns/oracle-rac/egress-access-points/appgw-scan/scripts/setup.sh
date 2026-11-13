#!/bin/bash
# Add a TCP route for the Oracle RAC node VIPs to an EXISTING shared Application Gateway.
# Dry run by default: prints the az commands. Pass --apply to execute them.
# Adds objects only (pool, probe, settings, listener, rule). It never replaces the gateway,
# so other listeners on the same gateway are untouched.
#
# Usage: ./setup.sh <appgw-rg> <appgw-name> <listener-port> <node-vip> [<node-vip> ...] [--apply]
#   e.g. ./setup.sh my-resource-group my-appgw 1521 10.0.1.10 10.0.1.11 --apply
#
# TLS/SNI listener (as on a gateway that terminates TLS for oracle.<domain>): set LISTENER_HOST
#   and SSL_CERT, e.g.  LISTENER_HOST=oracle.example.com SSL_CERT=appgw-server ./setup.sh ...
#   Without them a plain TCP listener is created. Listeners sharing a port must all be the same
#   type, so a plain TCP listener cannot be added on a port that already has a TLS listener.
# NOT yet run against a live gateway; read the printed commands before applying.
#
# Env overrides: LISTENER_HOST, SSL_CERT, SUBSCRIPTION (az subscription id/name), NAME (object name suffix, default oracle-rac-<port>), IDLE_SECONDS (default 900),
#   FRONTEND_IP (default appGwPrivateFrontendIpIPv4), PRIORITY (default 130),
#   PROBE_INTERVAL (default 5), PROBE_THRESHOLD (default 2)

set -e

[ $# -ge 4 ] || { sed -n '2,19p' "$0"; exit 1; }

RG="$1"; GW="$2"; PORT="$3"; shift 3
APPLY=""; NODES=()
for a in "$@"; do [ "$a" = "--apply" ] && APPLY="--apply" || NODES+=("$a"); done
[ ${#NODES[@]} -ge 1 ] || { echo "need at least one node VIP"; exit 1; }

NAME="${NAME:-oracle-rac-${PORT}}"
IDLE_SECONDS="${IDLE_SECONDS:-900}"      # keep above any client keepalive/idle interval
FRONTEND_IP="${FRONTEND_IP:-appGwPrivateFrontendIpIPv4}"
PRIORITY="${PRIORITY:-130}"
PROBE_INTERVAL="${PROBE_INTERVAL:-5}"
PROBE_THRESHOLD="${PROBE_THRESHOLD:-2}"

run() {
    local cmd=("$@")
    [ -n "$SUBSCRIPTION" ] && cmd+=(--subscription "$SUBSCRIPTION")
    echo "+ ${cmd[*]}"
    [ "$APPLY" = "--apply" ] && "${cmd[@]}"
    return 0
}

echo "Gateway: $GW ($RG)  listener port: $PORT  nodes: ${NODES[*]}"
[ "$APPLY" = "--apply" ] || echo "(dry run, pass --apply to execute)"
echo

# Backend pool: the RAC node VIPs (srvctl config vip), NOT the SCAN addresses and not the physical IPs.
# The service must be registered on every node in the pool: the probe below cannot detect ORA-12514.
run az network application-gateway address-pool create \
    --gateway-name "$GW" -g "$RG" -n "pool-$NAME" --servers "${NODES[@]}"

# TCP health probe on the listener port. It cannot see ORA-12514 (service not registered),
# only whether the port accepts connections.
run az network application-gateway probe create \
    --gateway-name "$GW" -g "$RG" -n "probe-$NAME" \
    --protocol Tcp --port "$PORT" --interval "$PROBE_INTERVAL" --threshold "$PROBE_THRESHOLD" --timeout 5

run az network application-gateway settings create \
    --gateway-name "$GW" -g "$RG" -n "settings-$NAME" \
    --port "$PORT" --protocol Tcp --timeout "$IDLE_SECONDS" --probe "probe-$NAME"

# Reuses the frontend port if the gateway already has one for this number.
if az network application-gateway frontend-port show --gateway-name "$GW" -g "$RG" -n "port_$PORT" ${SUBSCRIPTION:+--subscription "$SUBSCRIPTION"} >/dev/null 2>&1; then
    echo "(frontend port port_$PORT already exists, reusing)"
else
    run az network application-gateway frontend-port create \
        --gateway-name "$GW" -g "$RG" -n "port_$PORT" --port "$PORT"
fi

LISTENER_ARGS=()
[ -n "$LISTENER_HOST" ] && LISTENER_ARGS+=(--host-names "$LISTENER_HOST")
[ -n "$SSL_CERT" ] && LISTENER_ARGS+=(--ssl-cert "$SSL_CERT")
run az network application-gateway listener create \
    --gateway-name "$GW" -g "$RG" -n "listener-$NAME" \
    --frontend-port "port_$PORT" --frontend-ip "$FRONTEND_IP" "${LISTENER_ARGS[@]}"

run az network application-gateway routing-rule create \
    --gateway-name "$GW" -g "$RG" -n "route-$NAME" \
    --listener "listener-$NAME" --address-pool "pool-$NAME" \
    --settings "settings-$NAME" --priority "$PRIORITY"

echo
echo "Next:"
echo "  show-backend-health returns nothing for TCP pools. Test through the gateway instead:"
echo "  sqlplus <user>/<password>@//<appgw-private-ip>:$PORT/<service_name>"
echo "  Point the Confluent egress DNS entry for the Oracle hostname at the EAP that targets this gateway."
