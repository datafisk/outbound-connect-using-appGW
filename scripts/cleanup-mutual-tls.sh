#!/bin/bash
# Cleanup IBM MQ SSL/TLS Configuration
#
# This script removes all SSL certificates and keystores created by setup-mutual-tls.sh
# allowing you to start fresh.
#
# WARNING: This will delete MQ's SSL configuration!

set -e

QM_NAME="QM1"
MQ_USER="mqm"
MQ_DATA_PATH="/var/mqm/qmgrs/${QM_NAME}"
SSL_DIR="${MQ_DATA_PATH}/ssl"
WORK_DIR="./ssl-certs"

echo "=========================================="
echo "IBM MQ SSL/TLS Cleanup"
echo "=========================================="
echo ""
echo "This will remove:"
echo "  - Work directory: ${WORK_DIR}"
echo "  - MQ SSL keystore: ${SSL_DIR}/key.*"
echo "  - Any temp files in /tmp"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Remove work directory
if [ -d "${WORK_DIR}" ]; then
  echo "Removing work directory: ${WORK_DIR}"
  rm -rf "${WORK_DIR}"
  echo "✓ Work directory removed"
else
  echo "Work directory does not exist (already clean)"
fi

# Remove MQ SSL keystores
if [ -f "${SSL_DIR}/key.kdb" ]; then
  echo "Removing MQ SSL keystore files..."
  sudo -u ${MQ_USER} rm -f "${SSL_DIR}/key.kdb"
  sudo -u ${MQ_USER} rm -f "${SSL_DIR}/key.sth"
  sudo -u ${MQ_USER} rm -f "${SSL_DIR}/key.rdb"
  sudo -u ${MQ_USER} rm -f "${SSL_DIR}/key.crl"
  echo "✓ MQ keystore files removed"
else
  echo "MQ keystore does not exist (already clean)"
fi

# Remove temp files
echo "Removing any temp files..."
sudo rm -f /tmp/ca-cert.pem
sudo rm -f /tmp/mq-server.csr
sudo rm -f /tmp/mq-server-signed.pem
echo "✓ Temp files cleaned"

# Reset MQ SSL configuration (optional)
echo ""
read -p "Do you want to reset MQ SSL configuration? (yes/no): " RESET_MQ

if [ "$RESET_MQ" = "yes" ]; then
  echo "Resetting MQ SSL configuration..."
  sudo -u ${MQ_USER} runmqsc ${QM_NAME} << EOF
ALTER QMGR CERTLABL(' ')
ALTER QMGR SSLKEYR(' ')
ALTER CHANNEL('CONFLUENT.CHL') CHLTYPE(SVRCONN) SSLCIPH(' ') SSLCAUTH(OPTIONAL)
REFRESH SECURITY TYPE(SSL)
EOF
  echo "✓ MQ SSL configuration reset"
fi

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "You can now run setup-mutual-tls.sh again."
echo ""
