#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/ibm-mq-source.env"
TEMPLATE_FILE="${SCRIPT_DIR}/ibm-mq-source.json"
OUTPUT_FILE="${SCRIPT_DIR}/ibm-mq-source.generated.json"

echo "IBM MQ Connector Configuration Generator"
echo "=========================================="
echo ""

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: $ENV_FILE not found"
    echo ""
    echo "Please create it from the example:"
    echo "  cp connectors/ibm-mq-source.env.example connectors/ibm-mq-source.env"
    echo ""
    echo "Then edit it with your values."
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "❌ Error: $TEMPLATE_FILE not found"
    exit 1
fi

# Load environment variables
echo "Loading configuration from $ENV_FILE..."
set -a
source "$ENV_FILE"
set +a

# Verify required variables are set
required_vars=(
    "CONFLUENT_API_KEY"
    "CONFLUENT_API_SECRET"
    "CONFLUENT_BOOTSTRAP_SERVERS"
    "MQ_HOSTNAME"
    "MQ_PORT"
    "MQ_TRANSPORT"
    "MQ_QUEUE_MANAGER"
    "MQ_CHANNEL"
    "JMS_DESTINATION_NAME"
    "JMS_DESTINATION_TYPE"
)

# Optional variables (MQ credentials)
optional_vars=(
    "MQ_USERNAME"
    "MQ_PASSWORD"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "❌ Error: Missing required variables in $ENV_FILE:"
    printf '  - %s\n' "${missing_vars[@]}"
    exit 1
fi

# Generate the configuration by substituting variables
echo "Generating connector configuration..."

# Export optional variables (empty if not set)
export MQ_USERNAME="${MQ_USERNAME:-}"
export MQ_PASSWORD="${MQ_PASSWORD:-}"

# Use envsubst to replace variables (or sed if envsubst not available)
if command -v envsubst &> /dev/null; then
    envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"
else
    # Fallback to sed for variable substitution
    cp "$TEMPLATE_FILE" "$OUTPUT_FILE"
    all_vars=("${required_vars[@]}" "${optional_vars[@]}")
    for var in "${all_vars[@]}"; do
        sed -i.bak "s|\${$var}|${!var}|g" "$OUTPUT_FILE"
    done
    rm -f "${OUTPUT_FILE}.bak"
fi

# Remove lines with empty credentials if not provided
if [ -z "$MQ_USERNAME" ]; then
    echo "ℹ️  No MQ username provided - using unauthenticated connection"
    # Remove the mq.username line from the generated file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' '/\"mq\.username\":/d' "$OUTPUT_FILE"
    else
        # Linux
        sed -i '/\"mq\.username\":/d' "$OUTPUT_FILE"
    fi
fi

if [ -z "$MQ_PASSWORD" ]; then
    echo "ℹ️  No MQ password provided - using unauthenticated connection"
    # Remove the mq.password line from the generated file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' '/\"mq\.password\":/d' "$OUTPUT_FILE"
    else
        # Linux
        sed -i '/\"mq\.password\":/d' "$OUTPUT_FILE"
    fi
fi

echo "✅ Configuration generated successfully!"
echo ""
echo "Output file: $OUTPUT_FILE"
echo ""
echo "You can now deploy this connector using:"
echo "  1. Confluent Cloud UI: Copy/paste the content of $OUTPUT_FILE"
echo "  2. Confluent CLI: confluent connect create --config $OUTPUT_FILE"
echo ""
echo "Note: The generated file contains sensitive credentials."
echo "      It is automatically ignored by git (.gitignore)."
