# Migration to Native Terraform TCP Support

## Summary

**✅ Success!** Your infrastructure has been refactored to use native Terraform support for Application Gateway TCP/TLS proxy configuration.

As of **April 2026**, the Terraform azurerm provider (version 4.67+) includes full support for TCP/TLS proxy via native `listener`, `backend`, and `routing_rule` blocks. This eliminates the need for PowerShell scripts or manual Azure Portal configuration.

## What Changed

### Removed Files
- ❌ `tcp-proxy-automation.tf` - Terraform null_resource automation (no longer needed)
- ❌ `scripts/configure-tcp-proxy.ps1` - PowerShell configuration script (no longer needed)
- ❌ `scripts/configure-tcp-proxy.sh` - Bash helper script (no longer needed)

### Updated Files

#### `versions.tf`
- **Before**: `version = "~> 4.15"`
- **After**: `version = "~> 4.67"` (minimum version with TCP support)

#### `main.tf` - Application Gateway Configuration
**Replaced legacy HTTP blocks with native TCP blocks:**

| Before (HTTP placeholders) | After (Native TCP) |
|---|---|
| `http_listener { protocol = "Http" }` | `listener { protocol = "Tcp" }` |
| `backend_http_settings { protocol = "Http" }` | `backend { protocol = "Tcp" }` |
| `request_routing_rule` | `routing_rule` |
| `probe { protocol = "Http", path = "/" }` | `probe { protocol = "Tcp" }` |

**Removed lifecycle ignore block** - All configuration is now managed by Terraform

#### `terraform.tfvars`
- Removed `auto_configure_tcp_proxy = true` (variable no longer exists)

#### Documentation
- Updated `README.md` to reflect native Terraform support
- Updated `TCP-PROXY-SETUP.md` with migration guidance and legacy information

## How to Apply

### For Existing Infrastructure

If you have an **existing Application Gateway** that was configured with the PowerShell script:

1. **Backup current state:**
   ```bash
   terraform state pull > terraform.tfstate.backup
   ```

2. **Upgrade provider:**
   ```bash
   terraform init -upgrade
   ```

3. **Review changes:**
   ```bash
   terraform plan
   ```

   Terraform will show that it needs to:
   - Add new `listener`, `backend`, and `routing_rule` resources
   - Remove old HTTP placeholders

4. **Apply changes:**
   ```bash
   terraform apply
   ```

5. **Verify Application Gateway:**
   ```bash
   az network application-gateway show \
     --name <appgw-name> \
     --resource-group <rg-name> \
     --query '{listeners: listeners[].{name:name, protocol:protocol}, backends: backendSettingsCollection[].{name:name, protocol:protocol}}' \
     -o table
   ```

### For New Deployments

Simply deploy as normal - TCP proxy is automatically configured:

```bash
terraform init
terraform plan
terraform apply
```

## New Configuration Schema

### TCP Listener
```hcl
listener {
  name                           = "ibm-mq-listener"
  protocol                       = "Tcp"
  frontend_ip_configuration_name = "appgw-frontend-private"
  frontend_port_name             = "ibm-mq-port"
}
```

### TCP Backend Settings
```hcl
backend {
  name               = "ibm-mq-backend-settings"
  port               = 1414
  protocol           = "Tcp"
  timeout_in_seconds = 20
  probe_name         = "ibm-mq-health-probe"
}
```

### TCP Routing Rule
```hcl
routing_rule {
  name                      = "ibm-mq-routing-rule"
  priority                  = 100
  listener_name             = "ibm-mq-listener"
  backend_address_pool_name = "ibm-mq-backend-pool"
  backend_name              = "ibm-mq-backend-settings"
}
```

### TCP Health Probe
```hcl
probe {
  name                = "ibm-mq-health-probe"
  protocol            = "Tcp"
  port                = 1414
  interval            = 30
  timeout             = 30
  unhealthy_threshold = 3
}
```

## Benefits

✅ **100% Infrastructure as Code** - No manual steps required  
✅ **Reproducible** - Identical deployments every time  
✅ **Version Controlled** - All configuration tracked in Git  
✅ **Simplified Deployment** - No PowerShell dependency  
✅ **State Managed** - Terraform tracks all resources  
✅ **Consistent** - Same configuration across environments  

## Troubleshooting

### Issue: Provider version not updating

**Solution:**
```bash
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### Issue: Terraform shows many changes

This is expected during migration. The changes should show:
- Adding `listener` (Tcp)
- Adding `backend` (Tcp)
- Adding `routing_rule`
- Updating `probe` to Tcp protocol

### Issue: Configuration validation fails

**Check:**
1. Provider version is 4.67 or higher: `terraform version`
2. No syntax errors: `terraform validate`
3. Correct parameter names (`timeout_in_seconds`, not `timeout`)

## References

- [GitHub Issue #26239](https://github.com/hashicorp/terraform-provider-azurerm/issues/26239) - Feature request (Closed)
- [GitHub PR #30376](https://github.com/hashicorp/terraform-provider-azurerm/pull/30376) - Implementation (Merged)
- [Azure Application Gateway TCP/TLS Proxy Documentation](https://learn.microsoft.com/en-us/azure/application-gateway/how-to-tcp-tls-proxy)

---

**Migration completed:** April 23, 2026  
**Provider version:** azurerm 4.67+ (using 4.69.0)
