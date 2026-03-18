#!/bin/bash
set -e

echo "=========================================="
echo "Configure Application Gateway TCP/TLS Proxy"
echo "For IBM MQ on port 1414"
echo "=========================================="
echo ""

# Get values from Terraform
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
APPGW_NAME=$(terraform output -raw application_gateway_name)
MQ_PORT=1414

echo "Resource Group: $RESOURCE_GROUP"
echo "App Gateway: $APPGW_NAME"
echo "IBM MQ Port: $MQ_PORT"
echo ""

echo "Configuring TCP/TLS proxy via Azure Portal is recommended"
echo "Terraform azurerm provider doesn't fully support TCP/TLS proxy yet"
echo ""
echo "Manual Configuration Steps:"
echo ""
echo "1. Open Azure Portal: https://portal.azure.com"
echo ""
echo "2. Navigate to:"
echo "   Resource Groups → $RESOURCE_GROUP → $APPGW_NAME"
echo ""
echo "3. Update Health Probe (ibm-mq-health-probe):"
echo "   - Go to: Health probes"
echo "   - Select: ibm-mq-health-probe"
echo "   - Change Protocol to: TCP"
echo "   - Port: $MQ_PORT"
echo "   - Save"
echo ""
echo "4. Update Backend Settings (ibm-mq-backend-settings):"
echo "   - Go to: Backend settings"
echo "   - Select: ibm-mq-backend-settings"
echo "   - Change Backend protocol to: HTTPS"
echo "   - Backend port: $MQ_PORT"
echo "   - Custom probe: ibm-mq-health-probe"
echo "   - Save"
echo ""
echo "5. Verify Configuration:"
echo "   - Backend Health should show status"
echo "   - Once backends are added, health will be checked via TCP"
echo ""
echo "=========================================="
echo "OR use Azure CLI (experimental):"
echo "=========================================="
echo ""

read -p "Would you like to try Azure CLI configuration? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Skipping Azure CLI configuration."
    echo "Please configure manually via Azure Portal."
    exit 0
fi

echo ""
echo "Attempting CLI configuration..."
echo ""

# Get the current configuration
echo "Fetching current configuration..."
CURRENT_CONFIG=$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$RESOURCE_GROUP")

# Use ARM template approach via az rest
echo "Updating via Azure REST API..."

cat > /tmp/appgw-patch.json <<EOF
{
  "properties": {
    "probes": [
      {
        "name": "ibm-mq-health-probe",
        "properties": {
          "protocol": "Tcp",
          "port": $MQ_PORT,
          "interval": 30,
          "timeout": 30,
          "unhealthyThreshold": 3
        }
      }
    ]
  }
}
EOF

az rest --method patch \
  --url "/subscriptions/8018576d-fc49-402a-bb75-7437bff60635/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/applicationGateways/$APPGW_NAME?api-version=2023-11-01" \
  --body @/tmp/appgw-patch.json

echo ""
echo "✅ Configuration updated!"
echo "Please verify in Azure Portal"
