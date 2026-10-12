#!/bin/bash

# Master Pattern Deployment Script
# Usage: ./scripts/deploy-pattern.sh <pattern-name> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Install from: https://aka.ms/InstallAzureCLIDeb"
        exit 1
    fi

    # Check Confluent CLI
    if ! command -v confluent &> /dev/null; then
        print_error "Confluent CLI not found. Install from: https://cnfl.io/cli"
        exit 1
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Install from: https://terraform.io"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_warn "jq not found. Some features may not work. Install: brew install jq"
    fi

    # Check Azure authentication
    if ! az account show &> /dev/null; then
        print_error "Not authenticated to Azure. Run: az login"
        exit 1
    fi

    # Check Confluent authentication
    if ! confluent environment list &> /dev/null; then
        print_error "Not authenticated to Confluent Cloud. Run: confluent login"
        exit 1
    fi

    print_info "✓ All prerequisites met"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 <pattern-name> [options]

Deploy a Confluent connector pattern

Available patterns:
  azure-sql-failover    Azure SQL Server with failover group
  ibm-mq                IBM MQ Source connector
  oracle-rac            Oracle Real Application Clusters

Options:
  --approach <name>     Specify deployment approach (pattern-specific)
  --skip-terraform      Skip terraform deployment
  --skip-connector      Skip connector deployment
  --help                Show this help message

Examples:
  $0 azure-sql-failover --approach dual-eap
  $0 ibm-mq
  $0 oracle-rac --skip-connector

EOF
    exit 1
}

# Parse arguments
PATTERN=""
APPROACH=""
SKIP_TERRAFORM=false
SKIP_CONNECTOR=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --approach)
            APPROACH="$2"
            shift 2
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-connector)
            SKIP_CONNECTOR=true
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$PATTERN" ]; then
                PATTERN="$1"
            else
                print_error "Multiple patterns specified"
                usage
            fi
            shift
            ;;
    esac
done

# Validate pattern name
if [ -z "$PATTERN" ]; then
    print_error "No pattern specified"
    usage
fi

PATTERN_DIR="$REPO_ROOT/patterns/$PATTERN"

if [ ! -d "$PATTERN_DIR" ]; then
    print_error "Pattern not found: $PATTERN"
    print_info "Available patterns:"
    ls -1 "$REPO_ROOT/patterns" | grep -v "^_" || true
    exit 1
fi

# Main deployment flow
main() {
    print_info "=== Deploying Pattern: $PATTERN ==="
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Deploy based on pattern
    case $PATTERN in
        azure-sql-failover)
            deploy_azure_sql_failover
            ;;
        ibm-mq)
            deploy_ibm_mq
            ;;
        oracle-rac)
            deploy_oracle_rac
            ;;
        *)
            print_error "Deployment logic not implemented for: $PATTERN"
            print_info "Please follow the pattern's README.md for manual deployment"
            exit 1
            ;;
    esac

    echo ""
    print_info "=== Deployment Complete ==="
}

# Azure SQL Failover deployment
deploy_azure_sql_failover() {
    print_info "Deploying Azure SQL Failover pattern..."

    # Determine approach
    if [ -z "$APPROACH" ]; then
        print_info "No approach specified. Available approaches:"
        echo "  1. dual-eap  (Recommended, ~\$15/month)"
        echo "  2. appgw     (Alternative, ~\$150-180/month)"
        read -p "Select approach (1 or 2): " choice
        case $choice in
            1) APPROACH="dual-eap" ;;
            2) APPROACH="appgw" ;;
            *) print_error "Invalid choice"; exit 1 ;;
        esac
    fi

    print_info "Using approach: $APPROACH"
    echo ""

    # Deploy terraform
    if [ "$SKIP_TERRAFORM" = false ]; then
        print_info "Step 1: Deploying infrastructure with Terraform..."
        cd "$PATTERN_DIR/terraform"

        if [ ! -f "terraform.tfvars" ]; then
            print_warn "terraform.tfvars not found. Please create it from terraform.tfvars.example"
            read -p "Press Enter to continue after creating terraform.tfvars..."
        fi

        terraform init
        terraform plan
        read -p "Proceed with terraform apply? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            terraform apply
        else
            print_warn "Terraform deployment skipped by user"
        fi
        echo ""
    else
        print_info "Skipping Terraform deployment"
        echo ""
    fi

    # Setup connectivity
    print_info "Step 2: Setting up connectivity..."
    cd "$PATTERN_DIR/egress-access-points/$APPROACH"

    if [ -f "scripts/setup.sh" ]; then
        ./scripts/setup.sh
    else
        print_warn "Automated setup script not found"
        print_info "Please follow the instructions in: egress-access-points/$APPROACH/README.md"
        read -p "Press Enter when connectivity setup is complete..."
    fi
    echo ""

    # Deploy connector
    if [ "$SKIP_CONNECTOR" = false ]; then
        print_info "Step 3: Deploying connector..."
        cd "$PATTERN_DIR/connector-config"

        if [ ! -f "sql-sink.generated.json" ]; then
            print_info "Generating connector configuration..."
            ./generate-config.sh
        fi

        print_info "Creating connector..."
        read -p "Proceed with connector creation? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            confluent connect cluster create --config-file sql-sink.generated.json
        else
            print_warn "Connector deployment skipped by user"
            print_info "To deploy manually: confluent connect cluster create --config-file sql-sink.generated.json"
        fi
    else
        print_info "Skipping connector deployment"
    fi
}

# IBM MQ deployment
deploy_ibm_mq() {
    print_info "Deploying IBM MQ pattern..."
    print_warn "Deployment logic for IBM MQ not yet implemented"
    print_info "Please follow: $PATTERN_DIR/README.md"
}

# Oracle RAC deployment
deploy_oracle_rac() {
    print_info "Deploying Oracle RAC pattern..."
    print_warn "Deployment logic for Oracle RAC not yet implemented"
    print_info "Please follow: $PATTERN_DIR/README.md"
}

# Run main
main
