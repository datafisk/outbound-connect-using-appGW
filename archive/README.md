# Archive Directory

This directory contains legacy documentation and research files that have been superseded by newer guides.

## oracle-rac-research/

Research, findings, and old documentation created during Oracle RAC investigation:

- **ORACLE-RAC-AZURE-FINDINGS.md** - Research on Azure limitations for RAC
- **ORACLE-RAC-CLOUD-PROVIDER-OPTIONS.md** - Cloud provider comparison
- **ORACLE-RAC-FILES-SUMMARY.md** - Meta documentation about file structure
- **ORACLE-RAC-SETUP.md** - Old setup guide (superseded by patterns/oracle-rac/docs/APPGW-SETUP.md)
- **ORACLE-RAC-QUICK-REFERENCE.md** - Old quick reference (superseded by patterns/oracle-rac/docs/QUICKSTART.md)
- **ORACLE-INTEGRATION-SUMMARY.md** - Old integration summary (superseded)

## legacy-terraform/

Old Terraform configurations that were replaced:

- **appgw-oracle-rac-simple.tf** - Early attempt using AzAPI provider (superseded by the Terraform example in patterns/oracle-rac/docs/APPGW-SETUP.md)

---

## Current Documentation

The files listed above were replaced by the per-connector patterns:

- [patterns/oracle-rac](../patterns/oracle-rac/README.md): shared gateway, egress and RAC setup, connector comparison
- [patterns/oracle-rac-xstream](../patterns/oracle-rac-xstream/README.md)
- [patterns/oracle-rac-logminer](../patterns/oracle-rac-logminer/README.md)
- [patterns/oracle-rac-jdbc](../patterns/oracle-rac-jdbc/README.md)
