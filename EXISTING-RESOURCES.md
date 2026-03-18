# Using Existing Azure Resources

This guide explains how to deploy the Application Gateway and Confluent Cloud integration into your existing Azure infrastructure.

## Overview

By default, this Terraform configuration creates:
- ✓ New Resource Group
- ✓ New Virtual Network
- ✓ New Subnets (Application Gateway + Backend)

However, you can configure it to use existing resources instead. This is useful when:
- You have existing network infrastructure
- You want to deploy into a shared VNet
- You need to comply with organizational networking standards
- You want to integrate with existing subnets

## Configuration Options

### Option 1: Use Existing Resource Group

```hcl
# terraform.tfvars
create_resource_group        = false
existing_resource_group_name = "my-existing-rg"
```

### Option 2: Use Existing VNet

```hcl
# terraform.tfvars
create_vnet                        = false
existing_vnet_name                 = "my-existing-vnet"
existing_vnet_resource_group_name  = "my-vnet-rg"  # Optional, if VNet is in different RG
```

### Option 3: Use Existing Subnets

```hcl
# terraform.tfvars
create_subnets               = false
existing_appgw_subnet_name   = "appgw-subnet"
existing_backend_subnet_name = "backend-subnet"
```

**Important:** The Application Gateway subnet must have:
```
private_link_service_network_policies_enabled = false
```

### Mix and Match

You can combine options. For example:
- Use existing VNet but create new subnets
- Use existing Resource Group but create new VNet
- Use all existing resources

## Complete Example: Use Existing Everything

```hcl
# terraform.tfvars

# Use existing Resource Group
create_resource_group        = false
existing_resource_group_name = "shared-infrastructure-rg"

# Use existing VNet
create_vnet                        = false
existing_vnet_name                 = "hub-vnet"
existing_vnet_resource_group_name  = "network-rg"

# Use existing Subnets
create_subnets               = false
existing_appgw_subnet_name   = "application-gateway-subnet"
existing_backend_subnet_name = "applications-subnet"

# Still need to specify these for Application Gateway configuration
appgw_subnet_prefix   = "10.1.5.0/24"  # Must match actual subnet CIDR
backend_subnet_prefix = "10.1.6.0/24"  # For reference only

# Rest of configuration...
location        = "westeurope"
resource_prefix = "confluent-pl"
ibm_mq_backend_targets = ["10.1.6.10"]
```

## Subnet Requirements

### Application Gateway Subnet

**Minimum Requirements:**
- Subnet size: `/24` or larger recommended (minimum `/28`)
- No other resources in the subnet (dedicated to App Gateway)
- `private_link_service_network_policies_enabled = false`
- Not delegated to any service

**To verify existing subnet:**
```bash
az network vnet subnet show \
  --resource-group network-rg \
  --vnet-name hub-vnet \
  --name application-gateway-subnet \
  --query '{addressPrefix:addressPrefix, privateEndpointNetworkPolicies:privateEndpointNetworkPolicies, privateLinkServiceNetworkPolicies:privateLinkServiceNetworkPolicies}'
```

**To update existing subnet for Private Link:**
```bash
az network vnet subnet update \
  --resource-group network-rg \
  --vnet-name hub-vnet \
  --name application-gateway-subnet \
  --private-link-service-network-policies-enabled false
```

### Backend Subnet

**Minimum Requirements:**
- Subnet size: Depends on your backend resources
- Can be shared with other resources
- Should have network connectivity to your backend services (IBM MQ, databases, etc.)

## Network Security Groups

This Terraform configuration creates an NSG for the Application Gateway subnet with required rules:
- Allow GatewayManager (65200-65535)
- Allow AzureLoadBalancer
- Deny all other inbound traffic

**If using existing subnets with existing NSGs:**
- The Terraform NSG will be created and associated with the AppGW subnet
- This will replace any existing NSG association
- To prevent this, comment out the NSG resources in `main.tf` and ensure your existing NSG has the required rules

## Validation Steps

After configuring to use existing resources, validate before deploying:

### 1. Check Resource Group
```bash
az group show --name my-existing-rg
```

### 2. Check VNet
```bash
az network vnet show \
  --resource-group network-rg \
  --name hub-vnet \
  --query '{name:name, addressSpace:addressSpace, location:location}'
```

### 3. Check Subnets
```bash
# Application Gateway subnet
az network vnet subnet show \
  --resource-group network-rg \
  --vnet-name hub-vnet \
  --name application-gateway-subnet

# Backend subnet
az network vnet subnet show \
  --resource-group network-rg \
  --vnet-name hub-vnet \
  --name applications-subnet
```

### 4. Validate Terraform Plan
```bash
terraform plan
```

Look for:
- No errors about missing resources
- Correct subnet IDs being referenced
- Application Gateway creation in the right location

## Troubleshooting

### Error: "Resource Group not found"
- Verify the resource group name is correct
- Check you have permissions to read the resource group
- Ensure you're authenticated to the correct Azure subscription

### Error: "Virtual Network not found"
- Check the VNet name and resource group name
- Verify `existing_vnet_resource_group_name` if VNet is in a different RG
- Ensure the VNet exists in the correct subscription

### Error: "Subnet not found"
- Verify subnet names match exactly (case-sensitive)
- Check the subnet exists in the specified VNet
- Confirm you're referencing the correct VNet

### Error: "Application Gateway subnet requirements not met"
- Ensure subnet is `/24` or larger (minimum `/28`)
- Verify `private_link_service_network_policies_enabled = false`
- Check no other resources are deployed in the subnet
- Confirm subnet is not delegated

### Error: "Address space conflict"
- When using existing subnets, ensure `appgw_subnet_prefix` matches the actual subnet CIDR
- The Application Gateway uses this to calculate its private IP address
- Mismatch will cause deployment errors

## Best Practices

1. **Use separate resource groups** for different lifecycle management
   - Network RG (long-lived)
   - Application RG (may be recreated)

2. **Document subnet allocations** when using shared VNets
   - Reserve IP ranges for specific purposes
   - Avoid overlapping address space

3. **Test with create_* = true first**
   - Deploy to a test environment with new resources
   - Once validated, migrate to existing resources

4. **Keep NSG rules centralized** if using existing NSGs
   - Document the required App Gateway rules
   - Consider using Terraform to manage the NSG even if using existing subnets

5. **Use tags** to identify resources
   - Even with existing resources, tag the App Gateway and Public IP
   - Helps with cost tracking and resource management

## Migration Path

To migrate from new resources to existing resources:

1. Deploy initially with all `create_* = true`
2. Document the created resource names and IDs
3. Update `terraform.tfvars` to reference existing resources
4. Run `terraform plan` to see what will change
5. If needed, use `terraform state mv` to preserve resources
6. Apply changes incrementally (one resource type at a time)

## See Also

- [Azure Application Gateway Subnet Requirements](https://learn.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure)
- [Azure Private Link Network Policies](https://learn.microsoft.com/en-us/azure/private-link/disable-private-link-service-network-policy)
- [Terraform Import](https://www.terraform.io/docs/cli/import/index.html)
