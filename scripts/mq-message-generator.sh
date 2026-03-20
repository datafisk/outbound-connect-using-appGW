#!/bin/bash
# IBM MQ Message Generator
#
# This script continuously puts JSON messages onto an IBM MQ queue
# to help validate connector configurations.
#
# Usage:
#   ./mq-message-generator.sh [queue_name] [queue_manager] [interval_seconds]
#
# Example:
#   ./mq-message-generator.sh DEV.QUEUE.1 QM1 30
#
# Press Ctrl+C to stop

set -e

# Configuration
QUEUE_NAME="${1:-DEV.QUEUE.1}"
QM_NAME="${2:-QM1}"
INTERVAL="${3:-30}"
MESSAGE_COUNT=0

echo "=========================================="
echo "IBM MQ Message Generator"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Queue:          ${QUEUE_NAME}"
echo "  Queue Manager:  ${QM_NAME}"
echo "  Interval:       ${INTERVAL} seconds"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Check if queue manager is running
if ! dspmq | grep -q "QMNAME(${QM_NAME}).*STATUS(Running)"; then
  echo "Error: Queue manager ${QM_NAME} is not running"
  echo ""
  echo "Start it with: strmqm ${QM_NAME}"
  exit 1
fi

# Function to generate JSON message
generate_message() {
  local count=$1
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local random_value=$RANDOM

  cat <<EOF
{
  "message_id": ${count},
  "timestamp": "${timestamp}",
  "source": "mq-message-generator",
  "data": {
    "value": ${random_value},
    "description": "Test message generated for Confluent connector validation"
  },
  "metadata": {
    "queue": "${QUEUE_NAME}",
    "queue_manager": "${QM_NAME}"
  }
}
EOF
}

# Function to put message to queue
put_message() {
  local message=$1

  # Use amqsput to put the message
  # Note: This uses local bindings (requires script to run on MQ server)
  echo "${message}" | /opt/mqm/samp/bin/amqsput "${QUEUE_NAME}" "${QM_NAME}" > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# Trap Ctrl+C
trap 'echo ""; echo "Stopped. Total messages sent: ${MESSAGE_COUNT}"; exit 0' INT TERM

# Main loop
echo "Starting message generation..."
echo ""

while true; do
  MESSAGE_COUNT=$((MESSAGE_COUNT + 1))

  # Generate message
  MESSAGE=$(generate_message ${MESSAGE_COUNT})

  # Put message to queue
  if put_message "${MESSAGE}"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Message #${MESSAGE_COUNT} sent to ${QUEUE_NAME}"
  else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed to send message #${MESSAGE_COUNT}"
  fi

  # Wait for interval
  sleep ${INTERVAL}
done
