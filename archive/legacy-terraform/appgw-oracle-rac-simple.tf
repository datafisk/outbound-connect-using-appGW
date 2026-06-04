# Simple Azure CLI script wrapped in Terraform to add Oracle RAC routing rule
# This uses the AzAPI provider which supports newer Azure features

terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azapi" {}

# Get existing AppGW configuration
data "azapi_resource" "appgw" {
  type      = "Microsoft.Network/applicationGateways@2023-11-01"
  name      = "peter-g-mqtt"
  parent_id = "/subscriptions/54ff81a0-e7f6-4919-9053-4cdd1c5f5ae1/resourceGroups/vpc-peered-cce-se"
}

# Update AppGW with new routing rule
resource "azapi_update_resource" "add_oracle_rac_rule" {
  type      = "Microsoft.Network/applicationGateways@2023-11-01"
  name      = "peter-g-mqtt"
  parent_id = "/subscriptions/54ff81a0-e7f6-4919-9053-4cdd1c5f5ae1/resourceGroups/vpc-peered-cce-se"

  body = jsonencode({
    properties = {
      routingRules = concat(
        jsondecode(data.azapi_resource.appgw.output).properties.routingRules,
        [{
          name = "route-to-oracle-rac-oci"
          properties = {
            ruleType = "Basic"
            priority = 110
            listener = {
              id = "${data.azapi_resource.appgw.id}/listeners/oracle_standalone"
            }
            backendAddressPool = {
              id = "${data.azapi_resource.appgw.id}/backendAddressPools/oracle_rac_oci"
            }
            backendSettings = {
              id = "${data.azapi_resource.appgw.id}/backendSettingsCollection/oracle_1521"
            }
          }
        }]
      )
    }
  })
}
