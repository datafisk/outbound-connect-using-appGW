#!/bin/bash

# Generate Confluent SQL Server Sink Connector Configuration
# This script reads terraform outputs and user inputs to generate connector config

set -e

echo "=== Azure SQL Failover Connector Config Generator ==="
echo ""

# Check if terraform state exists
if [ ! -f "../terraform/terraform.tfstate" ]; then
    echo "Warning: terraform.tfstate not found. You'll need to provide values manually."
    TERRAFORM_AVAILABLE=false
else
    TERRAFORM_AVAILABLE=true
fi

# Function to get terraform output
get_tf_output() {
    local key=$1
    if [ "$TERRAFORM_AVAILABLE" = true ]; then
        cd ../terraform && terraform output -raw $key 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Gather configuration values
echo "Gathering configuration..."

# Failover Group FQDN (from terraform or manual input)
FAILOVER_FQDN=$(get_tf_output "failover_group_fqdn")
if [ -z "$FAILOVER_FQDN" ]; then
    read -p "Enter Failover Group FQDN (e.g., peter-fog.database.windows.net): " FAILOVER_FQDN
fi

# Database name
DATABASE_NAME=$(get_tf_output "database_name")
if [ -z "$DATABASE_NAME" ]; then
    read -p "Enter Database Name: " DATABASE_NAME
fi

# SQL username
SQL_USERNAME=$(get_tf_output "sql_admin_username")
if [ -z "$SQL_USERNAME" ]; then
    read -p "Enter SQL Username: " SQL_USERNAME
fi

# SQL password
echo "Note: Password will not be echoed to terminal"
read -sp "Enter SQL Password: " SQL_PASSWORD
echo ""

# Connector name
read -p "Enter Connector Name [sql-failover-sink]: " CONNECTOR_NAME
CONNECTOR_NAME=${CONNECTOR_NAME:-sql-failover-sink}

# Kafka topic
read -p "Enter Kafka Topic Name: " KAFKA_TOPIC

# Confluent Cloud details
echo ""
echo "Confluent Cloud Configuration:"
read -p "Enter Kafka API Key: " KAFKA_API_KEY
echo "Note: API Secret will not be echoed to terminal"
read -sp "Enter Kafka API Secret: " KAFKA_API_SECRET
echo ""

# Generate the configuration file
echo ""
echo "Generating connector configuration..."

sed -e "s|{{CONNECTOR_NAME}}|$CONNECTOR_NAME|g" \
    -e "s|{{FAILOVER_GROUP_FQDN}}|$FAILOVER_FQDN|g" \
    -e "s|{{SQL_USERNAME}}|$SQL_USERNAME|g" \
    -e "s|{{SQL_PASSWORD}}|$SQL_PASSWORD|g" \
    -e "s|{{DATABASE_NAME}}|$DATABASE_NAME|g" \
    -e "s|{{KAFKA_TOPIC}}|$KAFKA_TOPIC|g" \
    -e "s|{{KAFKA_API_KEY}}|$KAFKA_API_KEY|g" \
    -e "s|{{KAFKA_API_SECRET}}|$KAFKA_API_SECRET|g" \
    sql-sink.json.template > sql-sink.generated.json

echo "✅ Configuration generated: sql-sink.generated.json"
echo ""
echo "Review the configuration:"
echo "  cat sql-sink.generated.json | jq"
echo ""
echo "To deploy the connector:"
echo "  confluent connect cluster create --config-file sql-sink.generated.json"
echo ""
echo "Note: Make sure you're in the correct environment and cluster context:"
echo "  confluent environment use <env-id>"
echo "  confluent kafka cluster use <cluster-id>"
