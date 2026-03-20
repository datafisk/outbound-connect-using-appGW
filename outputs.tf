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
  value       = cidrhost(var.appgw_subnet_prefix, 50)
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

output "application_gateway_resource_id" {
  description = "Application Gateway Resource ID for Confluent Cloud egress access point"
  value       = azurerm_application_gateway.main.id
}

output "confluent_access_point_id" {
  description = "Confluent Cloud Egress Access Point ID"
  value       = confluent_access_point.appgw_egress.id
}

output "confluent_access_point_ip" {
  description = "Private endpoint IP address assigned by Confluent"
  value       = try(confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_ip_address, "pending")
}

output "confluent_private_endpoint_resource_id" {
  description = "Azure Private Endpoint Resource ID created by Confluent"
  value       = try(confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_resource_id, "pending")
}

output "confluent_dns_record_id" {
  description = "Confluent DNS Record ID (if created)"
  value       = var.create_dns_record ? confluent_dns_record.appgw_egress[0].id : "Not configured"
}

output "confluent_dns_domain" {
  description = "Custom DNS domain for the egress access point (if configured)"
  value       = var.create_dns_record ? var.dns_domain : "Not configured"
}

output "connector_id" {
  description = "IBM MQ Source Connector ID (if created)"
  value       = var.create_connector ? confluent_connector.ibm_mq_source[0].id : "Not created - set create_connector=true to deploy"
}

output "connector_status" {
  description = "IBM MQ Source Connector status (if created)"
  value       = var.create_connector ? confluent_connector.ibm_mq_source[0].status : "Not created"
}

output "appgw_subnet_cidr" {
  description = "Application Gateway subnet CIDR - Add this to IBM MQ firewall allow list"
  value       = var.appgw_subnet_prefix
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
    ✓ Confluent Cloud egress access point created

    Next Steps:

    1. ⚠️  CRITICAL: Configure IBM MQ Server Access
       App Gateway Subnet: ${var.appgw_subnet_prefix}

       Step 1 - OS Firewall (Linux iptables):
         sudo iptables -A INPUT -p tcp --dport 1414 -s ${var.appgw_subnet_prefix} -j ACCEPT

       Step 1 - OS Firewall (Windows):
         New-NetFirewallRule -DisplayName "IBM MQ - App Gateway" `
           -Direction Inbound -Protocol TCP -LocalPort 1414 `
           -RemoteAddress ${var.appgw_subnet_prefix} -Action Allow

       Step 2 - MQ Channel Authentication (REQUIRED):
         runmqsc QM1 << EOF
         SET CHLAUTH('CONFLUENT.CHL') TYPE(ADDRESSMAP) ADDRESS('172.200.*') USERSRC(MAP) MCAUSER('confluent') ACTION(ADD)
         REFRESH SECURITY TYPE(SSL)
         EOF

       See TCP-PROXY-SETUP.md for complete configuration details.

    2. Approve the Private Endpoint Connection:
       - Go to Azure Portal → Application Gateway → Private Link Center
       - Find the pending connection from Confluent Cloud
       - Click "Approve"

    3. ${var.create_connector ? "IBM MQ Connector Status:" : "Deploy IBM MQ Connector:"}
       ${var.create_connector ? "✓ Connector deployed automatically: ${confluent_connector.ibm_mq_source[0].id}\n       ✓ Status: ${confluent_connector.ibm_mq_source[0].status}\n       ✓ Using ${var.create_dns_record ? "DNS: ${var.dns_domain}" : "IP: ${confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_ip_address}"}" : "- Set create_connector=true in terraform.tfvars\n       - Configure connector variables (kafka_cluster_id, MQ settings, etc.)\n       - Run: terraform apply\n       - Or manually deploy using Confluent Cloud UI with network: ${local.confluent_network_id}"}

    ==========================================
    Configuration Details
    ==========================================

    Azure Side:
    - Resource Group: ${local.resource_group_name}
    - VNet: ${local.vnet_name}
    - App Gateway: ${azurerm_application_gateway.main.name}
    - App Gateway Subnet: ${var.appgw_subnet_prefix} ⚠️  Add to MQ firewall!
    - Private Link IP: ${cidrhost(var.appgw_subnet_prefix, 50)}
    - Frontend Port: ${var.ibm_mq_frontend_port}
    - Backend Targets: ${length(var.ibm_mq_backend_targets) > 0 ? join(", ", var.ibm_mq_backend_targets) : "⚠️  None configured!"}
    - Backend Port: ${var.ibm_mq_backend_port}

    Confluent Cloud Side:
    - Environment: ${var.confluent_environment_id}
    - Network: ${local.confluent_network_id}
    - Region: ${var.confluent_cloud_region}
    - Private Link Attachment: ${local.private_link_attachment_id}
    - Egress Access Point: ${confluent_access_point.appgw_egress.id}
    - Private Endpoint IP: ${try(confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_ip_address, "pending")}
    - Private Endpoint Resource ID: ${try(confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_resource_id, "pending")}
    ${var.create_dns_record ? "- Custom DNS Domain: ${var.dns_domain}" : ""}
    ${var.create_dns_record ? "- DNS Record ID: ${confluent_dns_record.appgw_egress[0].id}" : ""}

    ${length(var.ibm_mq_backend_targets) == 0 ? "\n    ⚠️  WARNING: No backend targets configured!\n    Add IBM MQ servers to terraform.tfvars:\n    ibm_mq_backend_targets = [\"10.0.2.10\"]\n    Then run: terraform apply\n" : ""}
    ==========================================
  EOT
}
