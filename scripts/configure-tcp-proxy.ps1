# Configure Azure Application Gateway for TCP/TLS Proxy
#
# This script updates an Application Gateway to use TCP protocol for listeners,
# backend settings, and health probes. This is a workaround for the limitation
# in the Terraform azurerm provider which doesn't support TCP/TLS proxy configuration.
#
# GitHub Issue: https://github.com/hashicorp/terraform-provider-azurerm/issues/26239
#
# Usage:
#   .\configure-tcp-proxy.ps1 -ResourceGroup <name> -AppGatewayName <name>
#
# Example:
#   .\configure-tcp-proxy.ps1 -ResourceGroup vpc-peered-cce-se -AppGatewayName confluent-pl-appgw
#

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$AppGatewayName
)

$ErrorActionPreference = "Stop"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Azure Application Gateway TCP Proxy Configuration" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource Group: $ResourceGroup"
Write-Host "App Gateway:    $AppGatewayName"
Write-Host ""

# Get Application Gateway
Write-Host "🔍 Fetching Application Gateway configuration..." -ForegroundColor Yellow
try {
    $appgw = Get-AzApplicationGateway -ResourceGroupName $ResourceGroup -Name $AppGatewayName
    Write-Host "✓ Found Application Gateway: $($appgw.Id)" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: Application Gateway not found" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""

# Check if TCP configuration already exists
Write-Host "📥 Checking current configuration..." -ForegroundColor Yellow
$tcpListener = $appgw.Listeners | Where-Object { $_.Protocol -eq "Tcp" } | Select-Object -First 1

if ($tcpListener) {
    Write-Host "ℹ️  TCP configuration already exists (listener: $($tcpListener.Name))" -ForegroundColor Cyan
    Write-Host "✓ Application Gateway is already configured for TCP proxy" -ForegroundColor Green
    exit 0
}

Write-Host "📋 Current HTTP Configuration:" -ForegroundColor Yellow
$httpListener = $appgw.HttpListeners | Select-Object -First 1
$httpSettings = $appgw.BackendHttpSettingsCollection | Select-Object -First 1
$probe = $appgw.Probes | Select-Object -First 1

Write-Host "   - HTTP Listener: $($httpListener.Name)"
Write-Host "   - Backend Settings: $($httpSettings.Name)"
Write-Host "   - Health Probe: $($probe.Name)"
Write-Host ""

# Configure TCP components
Write-Host "🔧 Configuring TCP components..." -ForegroundColor Yellow
Write-Host "⏳ This may take 5-10 minutes..." -ForegroundColor Yellow
Write-Host ""

# Step 1: Create TCP Listener
Write-Host "1️⃣  Creating TCP listener..." -ForegroundColor Cyan
$frontendIP = $appgw.FrontendIpConfigurations | Where-Object { $_.Name -eq "appgw-frontend-private" }
$frontendPort = $appgw.FrontendPorts | Where-Object { $_.Name -eq "ibm-mq-port" }

Add-AzApplicationGatewayListener `
    -ApplicationGateway $appgw `
    -Name "ibm-mq-listener" `
    -Protocol Tcp `
    -FrontendIPConfiguration $frontendIP `
    -FrontendPort $frontendPort | Out-Null

Write-Host "   ✓ TCP listener created" -ForegroundColor Green

# Step 2: Update Health Probe to TCP
Write-Host "2️⃣  Updating health probe to TCP..." -ForegroundColor Cyan
$appgw = Set-AzApplicationGatewayProbeConfig `
    -ApplicationGateway $appgw `
    -Name $probe.Name `
    -Protocol Tcp `
    -Port 1414 `
    -Interval 30 `
    -Timeout 30 `
    -UnhealthyThreshold 3

Write-Host "   ✓ Health probe updated to TCP" -ForegroundColor Green

# Step 3: Create TCP Backend Settings
Write-Host "3️⃣  Creating TCP backend settings..." -ForegroundColor Cyan
Add-AzApplicationGatewayBackendSetting `
    -ApplicationGateway $appgw `
    -Name "ibm-mq" `
    -Port 1414 `
    -Protocol Tcp `
    -Timeout 20 `
    -Probe $probe | Out-Null

Write-Host "   ✓ TCP backend settings created" -ForegroundColor Green

# Apply changes to Azure
Write-Host ""
Write-Host "4️⃣  Applying configuration changes..." -ForegroundColor Cyan
Write-Host "   ⏳ Updating Application Gateway (this takes 5-7 minutes)..." -ForegroundColor Yellow

try {
    $appgw = Set-AzApplicationGateway -ApplicationGateway $appgw
    Write-Host "   ✓ Configuration applied successfully" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Error applying configuration" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Reload configuration
$appgw = Get-AzApplicationGateway -ResourceGroupName $ResourceGroup -Name $AppGatewayName

# Step 5: Create TCP Routing Rule
Write-Host "5️⃣  Creating TCP routing rule..." -ForegroundColor Cyan
$tcpListener = $appgw.Listeners | Where-Object { $_.Name -eq "ibm-mq-listener" }
$backendPool = $appgw.BackendAddressPools | Where-Object { $_.Name -eq "ibm-mq-backend-pool" }
$backendSettings = $appgw.BackendSettingsCollection | Where-Object { $_.Name -eq "ibm-mq" }

Add-AzApplicationGatewayRoutingRule `
    -ApplicationGateway $appgw `
    -Name "ibm-mq-routing-rule" `
    -RuleType Basic `
    -Priority 100 `
    -Listener $tcpListener `
    -BackendAddressPool $backendPool `
    -BackendSettings $backendSettings | Out-Null

Write-Host "   ✓ TCP routing rule created" -ForegroundColor Green

# Apply routing rule
Write-Host ""
Write-Host "6️⃣  Applying routing rule..." -ForegroundColor Cyan
Write-Host "   ⏳ Updating Application Gateway (this takes 5-7 minutes)..." -ForegroundColor Yellow

try {
    $appgw = Set-AzApplicationGateway -ApplicationGateway $appgw
    Write-Host "   ✓ Routing rule applied successfully" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Error applying routing rule" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Reload configuration
$appgw = Get-AzApplicationGateway -ResourceGroupName $ResourceGroup -Name $AppGatewayName

# Step 7: Delete old HTTP routing rule
Write-Host "7️⃣  Removing old HTTP routing rule..." -ForegroundColor Cyan
$httpRule = $appgw.RequestRoutingRules | Where-Object { $_.Name -eq "ibm-mq-private-routing-rule" }
if ($httpRule) {
    Remove-AzApplicationGatewayRequestRoutingRule `
        -ApplicationGateway $appgw `
        -Name $httpRule.Name | Out-Null
    Write-Host "   ✓ HTTP routing rule removed" -ForegroundColor Green
}

# Step 8: Delete old HTTP listener
Write-Host "8️⃣  Removing old HTTP listener..." -ForegroundColor Cyan
if ($httpListener) {
    Remove-AzApplicationGatewayHttpListener `
        -ApplicationGateway $appgw `
        -Name $httpListener.Name | Out-Null
    Write-Host "   ✓ HTTP listener removed" -ForegroundColor Green
}

# Step 9: Delete old HTTP backend settings
Write-Host "9️⃣  Removing old HTTP backend settings..." -ForegroundColor Cyan
if ($httpSettings) {
    Remove-AzApplicationGatewayBackendHttpSetting `
        -ApplicationGateway $appgw `
        -Name $httpSettings.Name | Out-Null
    Write-Host "   ✓ HTTP backend settings removed" -ForegroundColor Green
}

# Final apply to clean up old components
Write-Host ""
Write-Host "🔟  Finalizing cleanup..." -ForegroundColor Cyan
Write-Host "   ⏳ Updating Application Gateway (this takes 5-7 minutes)..." -ForegroundColor Yellow

try {
    $appgw = Set-AzApplicationGateway -ApplicationGateway $appgw
    Write-Host "   ✓ Cleanup completed successfully" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Error during cleanup" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ TCP Proxy Configuration Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  ✓ TCP Listener created (ibm-mq-listener)"
Write-Host "  ✓ TCP Backend Settings created (ibm-mq)"
Write-Host "  ✓ TCP Health Probe updated ($($probe.Name))"
Write-Host "  ✓ TCP Routing Rule created (ibm-mq-routing-rule)"
Write-Host "  ✓ Old HTTP components removed"
Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Approve Private Endpoint connection in Azure Portal"
Write-Host "2. Retry Terraform apply to create DNS record and connector"
Write-Host ""
