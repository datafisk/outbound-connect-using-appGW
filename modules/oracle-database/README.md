# Oracle Database Module

This Terraform module provisions Oracle Database XE 21c on an Azure VM with Docker, fully configured for Confluent XStream CDC.

## What This Module Does

✅ **Creates Azure VM** with Ubuntu 22.04 LTS  
✅ **Installs Docker** and Docker Compose  
✅ **Deploys Oracle XE 21c** container  
✅ **Configures for CDC**:
   - Archive log mode enabled
   - Supplemental logging enabled  
   - Redo logs configured  

✅ **Creates XStream users**:
   - `C##GGADMIN` (XStream admin)
   - `C##CFLTUSER` (XStream connect user)

✅ **Sets up sample schema**:
   - Application user: `ordermgmt`
   - Schema: ORDERMGMT
   - Tables: ORDERS, CUSTOMERS, PRODUCTS, etc.
   - Initial data loaded
   - Data generator procedures

✅ **Network configuration**:
   - NSG allowing Oracle 1521 from App Gateway subnet
   - Optional public IP for SSH access

## Usage

### Basic Usage

```hcl
module "oracle_database" {
  source = "./modules/oracle-database/terraform"

  resource_prefix      = "my-poc"
  resource_group_name  = "my-resource-group"
  vnet_name            = "my-vnet"
  appgw_subnet_prefix  = "10.0.1.0/24"
  
  # SSH Configuration
  ssh_public_key       = file("~/.ssh/id_rsa.pub")
  ssh_private_key_path = "~/.ssh/id_rsa"

  # Oracle Configuration
  oracle_sys_password  = "Confluent123!"
  oracle_pdb_name      = "XEPDB1"

  tags = {
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
```

### Advanced Configuration

```hcl
module "oracle_database" {
  source = "./modules/oracle-database/terraform"

  resource_prefix      = "prod-oracle"
  resource_group_name  = "production-rg"
  vnet_name            = "production-vnet"
  
  # Use existing subnet
  create_subnet        = false
  existing_subnet_id   = azurerm_subnet.oracle.id
  appgw_subnet_prefix  = "10.0.1.0/24"

  # Larger VM for production
  vm_size              = "Standard_D8s_v3"  # 8 vCPUs, 32 GB RAM
  os_disk_size_gb      = 512

  # No public IP (access via Bastion/VPN)
  create_public_ip     = false
  allowed_ssh_cidr     = "10.0.0.0/16"

  # Oracle tuning
  oracle_memory_mb     = 8000
  
  # SSH Configuration
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path

  # Automated XStream setup
  configure_xstream    = true

  tags = var.tags
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| resource_prefix | Prefix for resource names | string | required |
| resource_group_name | Name of the resource group | string | required |
| vnet_name | Name of the virtual network | string | required |
| appgw_subnet_prefix | App Gateway subnet CIDR (for NSG rules) | string | required |
| ssh_public_key | SSH public key for VM access | string | required |
| ssh_private_key_path | Path to SSH private key for provisioning | string | required |
| create_subnet | Whether to create a new subnet | bool | true |
| existing_subnet_id | ID of existing subnet to use | string | "" |
| oracle_subnet_prefix | Address prefix for Oracle subnet | string | "10.0.5.0/24" |
| create_public_ip | Whether to create a public IP for SSH | bool | true |
| oracle_private_ip | Static private IP for Oracle VM (optional) | string | "" |
| vm_size | Azure VM size for Oracle | string | "Standard_D4s_v3" |
| os_disk_size_gb | OS disk size in GB | number | 256 |
| admin_username | Admin username for the VM | string | "oracleadmin" |
| oracle_sys_password | Oracle SYS password | string (sensitive) | "Confluent123!" |
| oracle_pdb_name | Oracle PDB name | string | "XEPDB1" |
| oracle_characterset | Oracle character set | string | "AL32UTF8" |
| oracle_memory_mb | Oracle SGA memory in MB | number | 4000 |
| enable_archivelog | Enable archive log mode (required for CDC) | bool | true |
| configure_xstream | Automatically configure XStream CDC | bool | true |
| tags | Tags to apply to resources | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| oracle_private_ip | Private IP address of Oracle VM |
| oracle_public_ip | Public IP address of Oracle VM (if created) |
| oracle_vm_id | ID of the Oracle VM |
| oracle_connection_string | JDBC connection string for XStream connector |
| oracle_hostname | Oracle hostname for connector configuration |
| oracle_port | Oracle database port (1521) |
| oracle_pdb_name | Oracle PDB name |
| oracle_xstream_user | Oracle XStream CDC user (C##GGADMIN) |
| ssh_command | SSH command to connect to Oracle VM |

## Post-Deployment

### 1. Verify Oracle is Running

```bash
# SSH to VM
ssh oracleadmin@<oracle-public-ip>

# Check Docker container
docker ps

# Should see:
# CONTAINER ID   IMAGE                                         STATUS
# abc123...      container-registry.oracle.com/database/express:21.3.0-xe   Up 5 minutes
```

### 2. Connect to Oracle

```bash
# From the Oracle VM
docker exec -it oracle21c sqlplus sys/Confluent123!@XE as sysdba

# Check database status
SQL> SELECT name, open_mode, log_mode FROM v$database;

# Should show:
# NAME      OPEN_MODE            LOG_MODE
# XE        READ WRITE           ARCHIVELOG
```

### 3. Verify XStream Users

```sql
SQL> SELECT username, account_status FROM dba_users 
     WHERE username IN ('C##GGADMIN', 'C##CFLTUSER', 'ORDERMGMT');

# Should show:
# USERNAME       ACCOUNT_STATUS
# C##GGADMIN     OPEN
# C##CFLTUSER    OPEN
# ORDERMGMT      OPEN
```

### 4. Check Sample Data

```bash
# Connect as application user
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1

SQL> SELECT COUNT(*) FROM orders;
SQL> SELECT COUNT(*) FROM customers;
SQL> SELECT COUNT(*) FROM products;
```

### 5. Create XStream Outbound Server

```sql
# Connect as XStream admin
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

# Create outbound server
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name     => 'XOUT',
    table_names     => 'ORDERMGMT.ORDERS,ORDERMGMT.CUSTOMERS',
    source_database => 'XEPDB1'
  );
END;
/

# Verify
SELECT server_name, capture_name, status FROM DBA_XSTREAM_OUTBOUND;
```

## Maintenance

### Stop Oracle

```bash
ssh oracleadmin@<oracle-ip>
cd /opt/oracle
docker-compose down
```

### Start Oracle

```bash
ssh oracleadmin@<oracle-ip>
cd /opt/oracle
docker-compose up -d
```

### View Logs

```bash
docker logs oracle21c
docker logs -f oracle21c  # Follow logs
```

### Backup Oracle Data

```bash
# Oracle data is in Docker volume: oracle-data
docker volume inspect oracle_oracle-data

# Backup commands (from VM)
sudo tar czf oracle-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/volumes/oracle_oracle-data/
```

## Troubleshooting

### Container won't start

```bash
# Check startup logs
docker logs oracle21c

# Check disk space
df -h

# Recreate container
cd /opt/oracle
docker-compose down
docker-compose up -d
```

### Can't connect from App Gateway

```bash
# Check NSG rules
az network nsg rule list \
  --resource-group <rg> \
  --nsg-name <oracle-nsg> \
  --query "[?destinationPortRange=='1521']"

# Check listener
docker exec oracle21c lsnrctl status
```

### XStream setup failed

```bash
# Re-run setup manually
ssh oracleadmin@<oracle-ip>

# Copy scripts if needed
docker cp /path/to/scripts oracle21c:/tmp/

# Run setup
docker exec -it oracle21c bash
cd /tmp/scripts
./00_setup_cdc.sh Confluent123! XEPDB1
```

## Destroying the Module

```bash
# From Terraform
terraform destroy -target=module.oracle_database

# This will:
# - Stop and remove the VM
# - Delete the NIC and NSG
# - Delete the public IP (if created)
# - Oracle data in Docker volumes will be lost
```

## Requirements

- Terraform >= 1.3
- Azure CLI authenticated
- SSH key pair generated
- Network: VNet with available subnet CIDR

## License

Oracle Database XE is free to use under Oracle's license terms.

## Reference

- [Oracle Container Registry](https://container-registry.oracle.com)
- [Oracle XE Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/21/xeinl/)
- [Docker Hub - Oracle Database](https://hub.docker.com/_/oracle-database-enterprise-edition)
