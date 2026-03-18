output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
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
  value       = azurerm_subnet.backend.id
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

output "confluent_connection_instructions" {
  description = "Instructions for connecting from Confluent Cloud"
  value       = <<-EOT
    ==========================================
    Confluent Cloud Private Link Setup
    ==========================================

    1. In Confluent Cloud Console:
       - Navigate to: Environments → Your Environment → Network
       - Click "Add network" → Select "Private Link"
       - Choose: Azure, Region: ${var.location}

    2. Provide Application Gateway details:
       Resource ID: ${azurerm_application_gateway.main.id}

       OR manually enter:
       - Subscription ID: ${split("/", azurerm_application_gateway.main.id)[2]}
       - Resource Group: ${azurerm_resource_group.main.name}
       - Resource Name: ${azurerm_application_gateway.main.name}
       - Resource Type: Microsoft.Network/applicationGateways

    3. After Confluent creates the Private Endpoint:
       - Go to Azure Portal → Application Gateway → Private Link Center
       - Find the pending connection from Confluent Cloud
       - Click "Approve"

    4. Configure IBM MQ Connector:
       - Edit: connectors/ibm-mq-source.env
       - Set MQ_HOSTNAME to the Private Endpoint DNS/IP from Confluent Cloud
       - Set MQ_PORT to ${var.ibm_mq_frontend_port}
       - Run: cd connectors && ./generate-config.sh
       - Deploy connector in Confluent Cloud

    ==========================================
    Application Gateway Configuration
    ==========================================

    Frontend (Confluent Cloud → App Gateway):
    - Private IP: ${cidrhost(var.appgw_subnet_prefix, 10)}
    - Port: ${var.ibm_mq_frontend_port} (TCP)

    Backend (App Gateway → IBM MQ):
    - Backend Pool: ibm-mq-backend-pool
    - Targets: ${length(var.ibm_mq_backend_targets) > 0 ? join(", ", var.ibm_mq_backend_targets) : "None configured - add via terraform.tfvars"}
    - Port: ${var.ibm_mq_backend_port}
    - Health Probe: TCP on port ${var.ibm_mq_backend_port}

    ${length(var.ibm_mq_backend_targets) == 0 ? "\n    ⚠️  WARNING: No backend targets configured!\n    Add IBM MQ servers to terraform.tfvars:\n    ibm_mq_backend_targets = [\"10.0.2.10\"]  # or FQDN\n    Then run: terraform apply\n" : ""}
    ==========================================
  EOT
}
