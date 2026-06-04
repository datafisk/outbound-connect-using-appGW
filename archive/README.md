# Archive Directory

This directory contains legacy documentation and research files that have been superseded by newer guides.

## oracle-rac-research/

Research, findings, and old documentation created during Oracle RAC investigation:

- **ORACLE-RAC-AZURE-FINDINGS.md** - Research on Azure limitations for RAC
- **ORACLE-RAC-CLOUD-PROVIDER-OPTIONS.md** - Cloud provider comparison
- **ORACLE-RAC-FILES-SUMMARY.md** - Meta documentation about file structure
- **ORACLE-RAC-SETUP.md** - Old setup guide (superseded by ORACLE-RAC-APPGW-SETUP.md)
- **ORACLE-RAC-QUICK-REFERENCE.md** - Old quick reference (superseded by ORACLE-RAC-QUICKSTART.md)
- **ORACLE-INTEGRATION-SUMMARY.md** - Old integration summary (superseded)

## legacy-terraform/

Old Terraform configurations that were replaced:

- **appgw-oracle-rac-simple.tf** - Early attempt using AzAPI provider (superseded by appgw-oracle-rac.tf)

---

## Current Documentation

For current, maintained documentation, see the root directory:

### Oracle RAC + Confluent Cloud
- **[ORACLE-RAC-QUICKSTART.md](../ORACLE-RAC-QUICKSTART.md)** - 45-minute setup guide
- **[ORACLE-RAC-APPGW-SETUP.md](../ORACLE-RAC-APPGW-SETUP.md)** - Complete setup and troubleshooting
- **[ORACLE-RAC-DEPLOYMENT-GUIDE.md](../ORACLE-RAC-DEPLOYMENT-GUIDE.md)** - RAC cluster deployment (separate)
- **[ORACLE-XSTREAM-SETUP.md](../ORACLE-XSTREAM-SETUP.md)** - XStream CDC connector

### Working Files
- **appgw-oracle-rac.tf** - Production Terraform for AppGW Oracle configuration
- **oracle-rac-connector.json** - Working JDBC connector configuration
- **README.md** - Main repository documentation
