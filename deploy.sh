#!/bin/bash
set -e

echo "=========================================="
echo "Azure Application Gateway Deployment"
echo "For Confluent Cloud Private Link"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install: https://www.terraform.io/downloads"
    exit 1
fi

# Check Azure login
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Running 'az login'..."
    az login
fi

echo "✅ Prerequisites check passed"
echo ""

# Display current Azure subscription
echo "Current Azure Subscription:"
az account show --query "{Name:name, SubscriptionId:id}" -o table
echo ""

read -p "Is this the correct subscription? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please switch subscription using: az account set --subscription <subscription-id>"
    exit 1
fi

# Check if terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "⚠️  Please edit terraform.tfvars to customize your deployment"
    read -p "Press Enter to continue after editing terraform.tfvars..." -r
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init
echo ""

# Plan
echo "Creating Terraform plan..."
terraform plan -out=tfplan
echo ""

# Apply
read -p "Do you want to apply this plan? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Applying Terraform configuration..."
    terraform apply tfplan
    rm tfplan
    echo ""
    echo "=========================================="
    echo "✅ Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Private Link Service Alias (use this in Confluent Cloud):"
    terraform output -raw private_link_service_alias
    echo ""
    echo ""
    echo "Next steps:"
    echo "1. Copy the Private Link Service Alias above"
    echo "2. Create a Private Link connection in Confluent Cloud"
    echo "3. Approve the connection in Azure Portal or via CLI"
    echo "4. Configure your connector using the example in connectors/ibm-mq-source.json"
    echo ""
    echo "For detailed instructions, see SETUP.md"
else
    rm tfplan
    echo "Deployment cancelled"
fi
