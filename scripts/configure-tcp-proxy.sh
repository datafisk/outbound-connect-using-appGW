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

# Extract the HTTP listener, settings, and probe names
HTTP_LISTENER_NAME=$(echo "$APPGW_CONFIG" | jq -r '.httpListeners[0].name // empty')
HTTP_SETTINGS_NAME=$(echo "$APPGW_CONFIG" | jq -r '.backendHttpSettingsCollection[0].name // empty')
PROBE_NAME=$(echo "$APPGW_CONFIG" | jq -r '.probes[0].name // empty')

echo "📋 Current HTTP Configuration:"
echo "   - HTTP Listener: ${HTTP_LISTENER_NAME:-Not found}"
echo "   - Backend Settings: ${HTTP_SETTINGS_NAME:-Not found}"
echo "   - Health Probe: ${PROBE_NAME:-Not found}"
echo ""

# Check if TCP config already exists
TCP_LISTENER=$(echo "$APPGW_CONFIG" | jq -r '.listeners[]? | select(.protocol == "Tcp") | .name' | head -1)
if [ -n "$TCP_LISTENER" ]; then
    echo "ℹ️  TCP configuration already exists (listener: $TCP_LISTENER)"
    echo "✓ Application Gateway is already configured for TCP proxy"
    exit 0
fi

# Prepare the TCP configuration updates
echo "🔧 Preparing TCP configuration..."

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
API_VERSION="2023-11-01"

# Build the PATCH request body
# We'll create new TCP listener, backend settings, and probe
# Then update the routing rule to use them

cat > /tmp/appgw-tcp-config.json <<EOF
{
  "properties": {
    "listeners": [
      {
        "name": "ibm-mq-listener",
        "properties": {
          "frontendIPConfiguration": {
            "id": "${APPGW_ID}/frontendIPConfigurations/appgw-frontend-private"
          },
          "frontendPort": {
            "id": "${APPGW_ID}/frontendPorts/ibm-mq-port"
          },
          "protocol": "Tcp"
        }
      }
    ],
    "backendSettingsCollection": [
      {
        "name": "ibm-mq",
        "properties": {
          "port": 1414,
          "protocol": "Tcp",
          "timeout": 20
        }
      }
    ],
    "probes": [
      {
        "name": "${PROBE_NAME}",
        "properties": {
          "protocol": "Tcp",
          "interval": 30,
          "timeout": 30,
          "unhealthyThreshold": 3,
          "minServers": 0,
          "match": {
            "statusCodes": ["200-399"]
          }
        }
      }
    ],
    "routingRules": [
      {
        "name": "ibm-mq-routing-rule",
        "properties": {
          "ruleType": "Basic",
          "priority": 100,
          "listener": {
            "id": "${APPGW_ID}/listeners/ibm-mq-listener"
          },
          "backendAddressPool": {
            "id": "${APPGW_ID}/backendAddressPools/ibm-mq-backend-pool"
          },
          "backendSettings": {
            "id": "${APPGW_ID}/backendSettingsCollection/ibm-mq"
          }
        }
      }
    ]
  }
}
EOF

echo "✓ TCP configuration prepared"
echo ""

# Apply the configuration using Azure REST API
echo "🚀 Applying TCP configuration..."
echo "⏳ This may take 5-10 minutes..."
echo ""

az rest \
    --method PATCH \
    --uri "https://management.azure.com${APPGW_ID}?api-version=${API_VERSION}" \
    --body @/tmp/appgw-tcp-config.json \
    --output none

# Wait for the update to complete
echo "⏳ Waiting for Application Gateway to update..."
az network application-gateway wait \
    --name "$APPGW_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --updated \
    --timeout 600

# Clean up temp file
rm -f /tmp/appgw-tcp-config.json

echo ""
echo "✅ TCP Proxy Configuration Complete!"
echo ""
echo "Configuration Summary:"
echo "  ✓ TCP Listener created (ibm-mq-listener)"
echo "  ✓ TCP Backend Settings created (ibm-mq)"
echo "  ✓ TCP Health Probe updated (${PROBE_NAME})"
echo "  ✓ Routing Rule updated (ibm-mq-routing-rule)"
echo ""
echo "==============================================="
