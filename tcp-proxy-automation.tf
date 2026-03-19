# TCP/TLS Proxy Configuration Automation
#
# This resource automatically configures the Application Gateway for TCP/TLS proxy
# after deployment. This is a workaround for the Terraform provider limitation.
#
# Set auto_configure_tcp_proxy = true in terraform.tfvars to enable automatic configuration.
#
# Manual configuration:
#   ./scripts/configure-tcp-proxy.sh <resource-group> <app-gateway-name>

resource "null_resource" "configure_tcp_proxy" {
  count = var.auto_configure_tcp_proxy ? 1 : 0

  # Run the configuration script after the Application Gateway is created
  provisioner "local-exec" {
    command = "${path.module}/scripts/configure-tcp-proxy.sh ${local.resource_group_name} ${azurerm_application_gateway.main.name}"
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
