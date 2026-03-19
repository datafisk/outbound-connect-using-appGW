# TCP/TLS Proxy Configuration Automation
#
# This resource automatically configures the Application Gateway for TCP/TLS proxy
# after deployment using PowerShell. This is a workaround for the Terraform provider limitation.
#
# Set auto_configure_tcp_proxy = true in terraform.tfvars to enable automatic configuration.
#
# Prerequisites:
#   - PowerShell with Az module installed
#   - Azure authentication: Connect-AzAccount
#
# Manual configuration:
#   PowerShell: .\scripts\configure-tcp-proxy.ps1 -ResourceGroup <rg> -AppGatewayName <name>
#   Portal: Follow instructions in TCP-PROXY-SETUP.md

resource "null_resource" "configure_tcp_proxy" {
  count = var.auto_configure_tcp_proxy ? 1 : 0

  # Run the PowerShell configuration script after the Application Gateway is created
  provisioner "local-exec" {
    command     = "pwsh -File ${path.module}/scripts/configure-tcp-proxy.ps1 -ResourceGroup ${local.resource_group_name} -AppGatewayName ${azurerm_application_gateway.main.name}"
    interpreter = ["pwsh", "-Command"]
  }

  # Re-run if the Application Gateway ID changes
  triggers = {
    appgw_id = azurerm_application_gateway.main.id
  }

  depends_on = [
    azurerm_application_gateway.main
  ]
}

variable "auto_configure_tcp_proxy" {
  description = "Automatically configure TCP proxy after deployment (requires Azure CLI)"
  type        = bool
  default     = false
}
