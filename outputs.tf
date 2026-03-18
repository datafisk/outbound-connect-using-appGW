output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.resource_group_name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = local.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = local.vnet_name
}

output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "application_gateway_private_ip" {
  description = "Private IP address of the Application Gateway (for Private Link)"
  value       = cidrhost(var.appgw_subnet_prefix, 10)
}

output "backend_subnet_id" {
  description = "ID of the backend subnet for placing IBM MQ and other backend resources"
  value       = local.backend_subnet_id
}

output "application_gateway_private_link_configuration_id" {
  description = "Private Link Configuration ID of the Application Gateway"
  value       = "${azurerm_application_gateway.main.id}/privateLinkConfigurations/private-link-config"
}

output "ibm_mq_backend_pool" {
  description = "IBM MQ backend pool configuration"
  value = {
    name    = "ibm-mq-backend-pool"
    targets = var.ibm_mq_backend_targets
    port    = var.ibm_mq_backend_port
  }
}

output "confluent_network_id" {
  description = "Confluent Cloud Egress Network ID"
  value       = local.confluent_network_id
}

output "confluent_private_link_attachment_id" {
  description = "Confluent Private Link Attachment ID"
  value       = local.private_link_attachment_id
}

output "confluent_connection_status" {
  description = "Confluent Private Link Connection Status"
  value       = confluent_private_link_attachment_connection.appgw.azure[0].private_endpoint_resource_id
}

output "setup_instructions" {
  description = "Next steps for completing the setup"
  value       = <<-EOT
    ==========================================
    Confluent Cloud Egress Setup - COMPLETE
    ==========================================

    ✓ Azure Application Gateway deployed
    ✓ Private Link configuration enabled
    ✓ Confluent Cloud ${var.create_confluent_network ? "network created" : "using existing network"}
    ✓ Confluent Cloud ${var.create_private_link_attachment ? "private link attachment created" : "using existing attachment"}
    ✓ Connection to App Gateway established

    Next Steps:

    1. Approve the Private Endpoint Connection (if required):
       - Go to Azure Portal → Application Gateway → Private Link Center
       - Find the pending connection from Confluent Cloud
       - Click "Approve" (or it may auto-approve)

    2. Configure IBM MQ Connector:
       - Network ID: ${confluent_network.egress.id}
       - Use this network when creating your connector
       - Edit: connectors/ibm-mq-source.env
       - Set MQ_HOSTNAME to: ${cidrhost(var.appgw_subnet_prefix, 10)}
       - Set MQ_PORT to: ${var.ibm_mq_frontend_port}
       - Run: cd connectors && ./generate-config.sh
       - Deploy connector in Confluent Cloud

    ==========================================
    Configuration Details
    ==========================================

    Azure Side:
    - Resource Group: ${local.resource_group_name}
    - VNet: ${local.vnet_name}
    - App Gateway: ${azurerm_application_gateway.main.name}
    - Private Link IP: ${cidrhost(var.appgw_subnet_prefix, 10)}
    - Frontend Port: ${var.ibm_mq_frontend_port}
    - Backend Targets: ${length(var.ibm_mq_backend_targets) > 0 ? join(", ", var.ibm_mq_backend_targets) : "⚠️  None configured!"}
    - Backend Port: ${var.ibm_mq_backend_port}

    Confluent Cloud Side:
    - Environment: ${var.confluent_environment_id}
    - Network: ${confluent_network.egress.id}
    - Region: ${var.confluent_cloud_region}
    - Connection: ${confluent_private_link_attachment_connection.appgw.id}

    ${length(var.ibm_mq_backend_targets) == 0 ? "\n    ⚠️  WARNING: No backend targets configured!\n    Add IBM MQ servers to terraform.tfvars:\n    ibm_mq_backend_targets = [\"10.0.2.10\"]\n    Then run: terraform apply\n" : ""}
    ==========================================
  EOT
}
