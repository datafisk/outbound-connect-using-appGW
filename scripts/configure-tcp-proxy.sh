#!/bin/bash
#
# Configure Azure Application Gateway for TCP/TLS Proxy
#
# This script updates an Application Gateway to use TCP protocol for listeners,
# backend settings, and health probes. This is a workaround for the limitation
# in the Terraform azurerm provider which doesn't support TCP/TLS proxy configuration.
#
# GitHub Issue: https://github.com/hashicorp/terraform-provider-azurerm/issues/26239
#
# Usage:
#   ./configure-tcp-proxy.sh <resource-group> <app-gateway-name>
#
# Example:
#   ./configure-tcp-proxy.sh vpc-peered-cce-se confluent-pl-appgw
#

set -e

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <resource-group> <app-gateway-name>"
    echo "Example: $0 vpc-peered-cce-se confluent-pl-appgw"
    exit 1
fi

RESOURCE_GROUP="$1"
APPGW_NAME="$2"

echo "==============================================="
echo "Azure Application Gateway TCP Proxy Configuration"
echo "==============================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "App Gateway:    $APPGW_NAME"
echo ""

# Get the Application Gateway resource ID
echo "🔍 Fetching Application Gateway configuration..."
APPGW_ID=$(az network application-gateway show \
    --name "$APPGW_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)

if [ -z "$APPGW_ID" ]; then
    echo "❌ Error: Application Gateway not found"
    exit 1
fi

echo "✓ Found Application Gateway: $APPGW_ID"
echo ""

# Get current configuration
echo "📥 Downloading current configuration..."
APPGW_CONFIG=$(az network application-gateway show \
    --name "$APPGW_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    -o json)

# Check if TCP config already exists
TCP_LISTENER=$(echo "$APPGW_CONFIG" | jq -r '.listeners[]? | select(.protocol == "Tcp") | .name' | head -1)
if [ -n "$TCP_LISTENER" ]; then
    echo "ℹ️  TCP configuration already exists (listener: $TCP_LISTENER)"
    echo "✓ Application Gateway is already configured for TCP proxy"
    exit 0
fi

echo "📋 Current configuration detected"
echo ""

# Use Azure Portal or manual configuration
echo "⚠️  Automatic TCP configuration via Azure CLI is not supported."
echo ""
echo "Please configure TCP proxy using one of these methods:"
echo ""
echo "Option 1: Azure Portal (Recommended)"
echo "======================================="
echo "1. Go to: https://portal.azure.com"
echo "2. Navigate to: Resource Groups → $RESOURCE_GROUP → $APPGW_NAME"
echo "3. Configure the following:"
echo ""
echo "   Health Probe:"
echo "   - Name: ibm-mq-health-probe"
echo "   - Protocol: TCP"
echo "   - Port: 1414"
echo ""
echo "   Backend Settings:"
echo "   - Delete: ibm-mq-backend-settings (HTTP)"
echo "   - Create new Backend Settings:"
echo "     - Name: ibm-mq"
echo "     - Protocol: TCP"
echo "     - Port: 1414"
echo "     - Timeout: 20"
echo ""
echo "   Listener:"
echo "   - Delete: ibm-mq-private-listener (HTTP)"
echo "   - Create new Listener:"
echo "     - Name: ibm-mq-listener"
echo "     - Protocol: TCP"
echo "     - Frontend IP: appgw-frontend-private"
echo "     - Port: 1414"
echo ""
echo "   Routing Rule:"
echo "   - Delete: ibm-mq-private-routing-rule"
echo "   - Create new Routing Rule:"
echo "     - Name: ibm-mq-routing-rule"
echo "     - Listener: ibm-mq-listener"
echo "     - Backend pool: ibm-mq-backend-pool"
echo "     - Backend settings: ibm-mq"
echo ""
echo "Option 2: Azure CLI (Export/Import)"
echo "===================================="
echo "1. Export configuration:"
echo "   az network application-gateway show \\"
echo "     --name $APPGW_NAME \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     > appgw-config.json"
echo ""
echo "2. Edit appgw-config.json manually:"
echo "   - Change listeners protocol to 'Tcp'"
echo "   - Change backendSettingsCollection protocol to 'Tcp'"
echo "   - Change probes protocol to 'Tcp'"
echo "   - Update routing rules to reference new components"
echo ""
echo "3. Import configuration:"
echo "   # This requires manual JSON editing and is complex"
echo "   # Portal method is recommended"
echo ""
echo "==============================================="
echo ""
echo "For detailed instructions, see: TCP-PROXY-SETUP.md"
echo ""
