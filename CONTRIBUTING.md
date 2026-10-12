# Contributing to Confluent Connector Patterns

Thank you for considering contributing to this repository! This guide will help you add new connector patterns or improve existing ones.

## Table of Contents

- [Pattern Criteria](#pattern-criteria)
- [Adding a New Pattern](#adding-a-new-pattern)
- [Pattern Structure](#pattern-structure)
- [Documentation Requirements](#documentation-requirements)
- [Testing Requirements](#testing-requirements)
- [Submission Process](#submission-process)

## Pattern Criteria

A pattern should be added to this repository if it meets the following criteria:

### Must Have

✅ **Production-Ready**: The pattern has been tested and validated in a real environment

✅ **Reusable**: The pattern solves a common use case that other users will encounter

✅ **Complete**: Includes infrastructure code, connector configuration, and documentation

✅ **Documented**: Has clear architecture documentation and step-by-step deployment guide

✅ **Tested**: Includes testing procedures and validation steps

### Nice to Have

- Cost analysis and optimization strategies
- Multiple deployment approaches (with pros/cons)
- Troubleshooting guide with common issues
- Automated deployment scripts
- Failover/HA testing procedures

## Adding a New Pattern

### 1. Use the Pattern Template

Copy the template structure:

```bash
cp -r patterns/_template patterns/your-pattern-name
cd patterns/your-pattern-name
```

### 2. Pattern Naming

Use lowercase with hyphens:
- ✅ `azure-sql-failover`
- ✅ `ibm-mq`
- ✅ `mongodb-atlas`
- ❌ `AzureSQLFailover`
- ❌ `ibm_mq`

### 3. Required Files

Every pattern must include:

```
patterns/your-pattern-name/
├── README.md                      # Overview with TL;DR
├── ARCHITECTURE.md                # Technical architecture (optional but recommended)
├── COST-ANALYSIS.md               # Cost breakdown (optional but recommended)
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── connector-config/
│   ├── connector.json.template
│   └── generate-config.sh
├── scripts/
│   └── deploy.sh
└── docs/
    ├── QUICKSTART.md
    └── TROUBLESHOOTING.md
```

## Pattern Structure

### README.md

The pattern README.md should include:

```markdown
# Pattern Name

## TL;DR

[1-2 paragraph summary of the problem and solution]

## Overview

[What this pattern is, what problem it solves]

## Architecture

[Architecture diagram and explanation]

## Components

[List of Azure/Confluent resources]

## Prerequisites

[Required tools, permissions, etc.]

## Quick Start

[Condensed deployment steps]

## Available Approaches

[If multiple approaches exist, document each]

## Documentation

[Links to detailed docs]

## Cost Analysis

[Link to COST-ANALYSIS.md or inline summary]

## Key Learnings

[Important insights discovered during development]

## Related Patterns

[Links to similar patterns]
```

### Terraform

Use consistent variable naming:

```hcl
# variables.tf
variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
```

Include a complete `terraform.tfvars.example`:

```hcl
# terraform.tfvars.example
resource_group_name = "your-resource-group"
location            = "eastus"

tags = {
  owner_email = "your.email@example.com"
  project     = "connector-pattern"
  environment = "test"
}
```

### Connector Configuration

Use a template with placeholders:

```json
{
  "name": "{{CONNECTOR_NAME}}",
  "config": {
    "connector.class": "{{CONNECTOR_CLASS}}",
    "connection.host": "{{HOST}}",
    "connection.port": "{{PORT}}"
  }
}
```

Provide a `generate-config.sh` script that:
- Reads terraform outputs when available
- Prompts for missing values
- Validates inputs
- Generates final connector JSON

### Scripts

Include a `deploy.sh` script that:

```bash
#!/bin/bash
set -e

# 1. Validate prerequisites
# 2. Deploy infrastructure (terraform)
# 3. Configure connectivity (EAP/AppGW)
# 4. Deploy connector
# 5. Verify deployment
```

## Documentation Requirements

### ARCHITECTURE.md (Recommended)

Include:
- Detailed architecture diagram
- Component descriptions
- Traffic flow explanation
- Security considerations
- HA/failover mechanics

### COST-ANALYSIS.md (Recommended)

Provide:
- Component-level cost breakdown
- Monthly cost estimates
- Cost comparison (if multiple approaches)
- Optimization strategies
- ROI analysis

### docs/QUICKSTART.md

Step-by-step deployment guide:
1. Prerequisites check
2. Infrastructure deployment
3. Connectivity setup
4. Connector deployment
5. Verification steps

### docs/TROUBLESHOOTING.md

Common issues and solutions:
- Issue description
- Cause
- Solution steps
- Prevention tips

## Testing Requirements

### Required Tests

1. **Initial Deployment**: Pattern deploys successfully from scratch
2. **Connector Functionality**: Data flows correctly
3. **Connectivity**: Verify private connectivity (not public)

### Recommended Tests (for HA patterns)

4. **Failover Test**: Connector continues working after failover
5. **Failback Test**: Bidirectional failover works
6. **Failure Scenarios**: Test edge cases and failures

### Test Documentation

Include in `docs/FAILOVER-TESTING.md` (or similar):
- Test objectives
- Test procedures
- Expected results
- Actual results
- Lessons learned

## Submission Process

### 1. Development

1. Create a feature branch:
   ```bash
   git checkout -b pattern/your-pattern-name
   ```

2. Develop and test your pattern

3. Ensure all documentation is complete

### 2. Validation

Before submitting, verify:

- [ ] Pattern deploys successfully from scratch
- [ ] All required files are present
- [ ] Documentation is complete and accurate
- [ ] Code follows repository conventions
- [ ] terraform.tfvars.example has no secrets
- [ ] Scripts are executable (`chmod +x`)
- [ ] Links in documentation work correctly
- [ ] Cost analysis is accurate (if included)

### 3. Pull Request

1. Commit your changes:
   ```bash
   git add patterns/your-pattern-name/
   git commit -m "Add [pattern-name] connector pattern"
   ```

2. Push to GitHub:
   ```bash
   git push origin pattern/your-pattern-name
   ```

3. Open a Pull Request with:
   - **Title**: `Add [Pattern Name] connector pattern`
   - **Description**: 
     - What the pattern does
     - Why it's useful
     - Testing performed
     - Cost estimate

4. PR template:
   ```markdown
   ## Pattern Overview
   [Brief description]

   ## Use Case
   [What problem does this solve?]

   ## Testing
   - [ ] Deployed from scratch successfully
   - [ ] Connector working
   - [ ] Documentation reviewed
   - [ ] Cost analysis accurate

   ## Screenshots/Diagrams
   [Architecture diagram, if applicable]

   ## Cost Estimate
   [Monthly cost range]
   ```

### 4. Review Process

Maintainers will review:
- Completeness of documentation
- Code quality and conventions
- Testing thoroughness
- Cost accuracy
- Reusability and value

### 5. Approval and Merge

Once approved:
- Pattern will be merged to main branch
- Added to root README.md pattern list
- Included in repository index

## Code Conventions

### Terraform

```hcl
# Use snake_case for variables and resources
variable "resource_group_name" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Use descriptive output names
output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  value       = azurerm_mssql_server.primary.fully_qualified_domain_name
}
```

### Bash Scripts

```bash
#!/bin/bash

# Enable strict mode
set -e

# Use descriptive variable names (UPPER_CASE for constants)
RESOURCE_GROUP="my-rg"
LOCATION="eastus"

# Check prerequisites before proceeding
check_prerequisites() {
    command -v az >/dev/null 2>&1 || { echo "Azure CLI required"; exit 1; }
    command -v confluent >/dev/null 2>&1 || { echo "Confluent CLI required"; exit 1; }
}

# Provide helpful output
echo "=== Deploying Pattern ==="
echo "Resource Group: $RESOURCE_GROUP"
```

### Connector JSON

```json
{
  "name": "descriptive-connector-name",
  "config": {
    "connector.class": "ConnectorClass",
    "tasks.max": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter"
  }
}
```

## Questions?

- Open a GitHub issue with the `question` label
- Reach out to maintainers

## Thank You!

Your contributions help the Confluent community build better, more reliable connector deployments!
