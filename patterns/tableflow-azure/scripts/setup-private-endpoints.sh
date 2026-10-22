#!/bin/bash
# Create blob and dfs private endpoints for a Tableflow storage account (manual-approval flow).
# Dry run by default: prints the az commands. Pass --apply to execute them.
#
# Usage: ./setup-private-endpoints.sh <vnet-rg> <vnet> <subnet> <storage-account-resource-id> [--apply]
#
# Uses manual approval so it also works when the VNet and storage account are in
# different subscriptions or Entra tenants (auto-approval fails across tenants).

set -e

if [ $# -lt 4 ]; then
    sed -n '2,8p' "$0"
    exit 1
fi

VNET_RG="$1"; VNET="$2"; SUBNET="$3"; STORAGE_ID="$4"; APPLY="$5"
ACCOUNT="${STORAGE_ID##*/}"
LOCATION="${LOCATION:-$(az network vnet show -g "$VNET_RG" -n "$VNET" --query location -o tsv)}"

run() {
    echo "+ $*"
    [ "$APPLY" = "--apply" ] && "$@"
    return 0
}

[ "$APPLY" = "--apply" ] || echo "(dry run, pass --apply to execute)"

for SUB in blob dfs; do
    run az network private-endpoint create -g "$VNET_RG" -l "$LOCATION" -n "$ACCOUNT-$SUB-pe" \
        --vnet-name "$VNET" --subnet "$SUBNET" \
        --private-connection-resource-id "$STORAGE_ID" --group-id "$SUB" \
        --connection-name "$ACCOUNT-$SUB" --manual-request true \
        --request-message "Tableflow private path"
done

echo
echo "Approve on the storage account side (sign in to its tenant/subscription first):"
echo "  for id in \$(az network private-endpoint-connection list --id $STORAGE_ID \\"
echo "      --query \"[?properties.privateLinkServiceConnectionState.status=='Pending'].id\" -o tsv); do"
echo "    az network private-endpoint-connection approve --id \$id --description 'Tableflow'; done"
echo
echo "Then create DNS records for both names, using each endpoint's private IP:"
echo "  az network nic list -g $VNET_RG --query \"[?contains(name,'$ACCOUNT')].{n:name,ip:ipConfigurations[0].privateIPAddress}\" -o tsv"
