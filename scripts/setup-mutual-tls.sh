#!/bin/bash
# Setup IBM MQ Mutual TLS with Self-Signed CA
#
# This script creates:
# 1. Self-signed Certificate Authority (CA)
# 2. IBM MQ server certificate signed by CA
# 3. Confluent connector client certificate signed by CA
# 4. Java keystores for the connector
#
# Usage:
#   ./setup-mutual-tls.sh [dns_domain]
#
# Example:
#   ./setup-mutual-tls.sh ibmmq2.peter.com
#
# Prerequisites:
# - IBM MQ installed on Ubuntu
# - Java keytool available
# - runmqakm available (part of IBM MQ)
# - Queue Manager QM1 running

set -e

echo "=========================================="
echo "IBM MQ Mutual TLS Setup"
echo "=========================================="
echo ""

# Configuration
QM_NAME="QM1"
MQ_USER="mqm"
MQ_DATA_PATH="/var/mqm/qmgrs/${QM_NAME}"
SSL_DIR="${MQ_DATA_PATH}/ssl"
WORK_DIR="./ssl-certs"
CA_VALIDITY_DAYS=3650  # 10 years
CERT_VALIDITY_DAYS=365 # 1 year

# DNS domain for MQ server certificate (passed as argument or default)
DNS_DOMAIN="${1:-mq-server.local}"

# Certificate details
CA_DN="CN=Test CA,OU=Testing,O=ConfluentDemo,C=US"
MQ_SERVER_DN="CN=${DNS_DOMAIN},OU=MQ,O=ConfluentDemo,C=US"
CLIENT_DN="CN=confluent-connector,OU=Connectors,O=ConfluentDemo,C=US"

# Passwords (for testing - use secure passwords in production)
CA_PASSWORD="ca-password-123"
MQ_KEYDB_PASSWORD="mq-keydb-password-123"
KEYSTORE_PASSWORD="connector-keystore-123"
TRUSTSTORE_PASSWORD="connector-truststore-123"

echo "Configuration:"
echo "  Queue Manager: ${QM_NAME}"
echo "  DNS Domain:    ${DNS_DOMAIN}"
echo "  SSL Directory: ${SSL_DIR}"
echo "  Work Directory: ${WORK_DIR}"
echo ""

if [ "$DNS_DOMAIN" = "mq-server.local" ]; then
  echo "⚠️  WARNING: Using default DNS domain 'mq-server.local'"
  echo "   For Confluent connector, this should match your dns_domain in terraform.tfvars"
  echo "   Usage: $0 ibmmq2.peter.com"
  echo ""
fi

# Ensure SSL directory exists
if [ ! -d "${SSL_DIR}" ]; then
  echo "Creating SSL directory..."
  sudo -u ${MQ_USER} mkdir -p "${SSL_DIR}"
  sudo chmod 755 "${SSL_DIR}"
fi

# Create work directory
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "=========================================="
echo "Step 1: Create Self-Signed CA"
echo "=========================================="
echo ""

# Create CA keystore using Java keytool
echo "Creating CA certificate and keystore..."
keytool -genkeypair \
  -alias ca-cert \
  -keyalg RSA \
  -keysize 4096 \
  -validity ${CA_VALIDITY_DAYS} \
  -keystore ca-keystore.jks \
  -storepass "${CA_PASSWORD}" \
  -keypass "${CA_PASSWORD}" \
  -dname "${CA_DN}"

# Export CA certificate to PEM format
echo "Exporting CA certificate..."
keytool -export \
  -alias ca-cert \
  -file ca-cert.pem \
  -keystore ca-keystore.jks \
  -storepass "${CA_PASSWORD}" \
  -rfc

echo "✓ CA created: ca-cert.pem"
echo ""

echo "=========================================="
echo "Step 2: Create IBM MQ Server Certificate"
echo "=========================================="
echo ""

# Create MQ key database if it doesn't exist
if [ ! -f "${SSL_DIR}/key.kdb" ]; then
  echo "Creating MQ key database..."
  sudo -u ${MQ_USER} runmqakm -keydb -create \
    -db "${SSL_DIR}/key.kdb" \
    -pw "${MQ_KEYDB_PASSWORD}" \
    -type cms \
    -stash
  echo "✓ MQ key database created"
else
  echo "MQ key database already exists"
fi

# Import CA certificate into MQ keystore
echo "Importing CA certificate into MQ keystore..."
# Copy CA cert to /tmp for mqm user access
sudo cp "$(pwd)/ca-cert.pem" /tmp/ca-cert.pem
sudo chmod 644 /tmp/ca-cert.pem

sudo -u ${MQ_USER} runmqakm -cert -add \
  -db "${SSL_DIR}/key.kdb" \
  -stashed \
  -label "CA Cert" \
  -file "/tmp/ca-cert.pem" \
  -format ascii

# Clean up temp file
sudo rm /tmp/ca-cert.pem

# Create server certificate request
echo "Creating MQ server certificate request..."
# Write to /tmp first (mqm user has access), then copy it
sudo -u ${MQ_USER} runmqakm -certreq -create \
  -db "${SSL_DIR}/key.kdb" \
  -stashed \
  -label "ibmmqserver" \
  -dn "${MQ_SERVER_DN}" \
  -file "/tmp/mq-server.csr"

# Copy the CSR to our work directory
sudo cp /tmp/mq-server.csr "$(pwd)/mq-server.csr"
sudo chmod 644 "$(pwd)/mq-server.csr"
sudo rm /tmp/mq-server.csr

# Sign the server certificate with CA
echo "Signing MQ server certificate with CA..."
keytool -gencert \
  -alias ca-cert \
  -keystore ca-keystore.jks \
  -storepass "${CA_PASSWORD}" \
  -infile mq-server.csr \
  -outfile mq-server-signed.pem \
  -validity ${CERT_VALIDITY_DAYS} \
  -rfc

# Import signed certificate back into MQ keystore
echo "Importing signed certificate into MQ keystore..."
# Copy signed cert to /tmp for mqm user access
sudo cp "$(pwd)/mq-server-signed.pem" /tmp/mq-server-signed.pem
sudo chmod 644 /tmp/mq-server-signed.pem

sudo -u ${MQ_USER} runmqakm -cert -receive \
  -db "${SSL_DIR}/key.kdb" \
  -stashed \
  -file "/tmp/mq-server-signed.pem" \
  -format ascii

# Clean up temp file
sudo rm /tmp/mq-server-signed.pem

echo "✓ MQ server certificate created and signed"
echo ""

echo "=========================================="
echo "Step 3: Create Client Certificate for Connector"
echo "=========================================="
echo ""

# Generate client key pair
echo "Creating client key pair..."
keytool -genkeypair \
  -alias client-key \
  -keyalg RSA \
  -keysize 2048 \
  -validity ${CERT_VALIDITY_DAYS} \
  -keystore connector-keystore.jks \
  -storepass "${KEYSTORE_PASSWORD}" \
  -keypass "${KEYSTORE_PASSWORD}" \
  -dname "${CLIENT_DN}"

# Create certificate signing request
echo "Creating client certificate request..."
keytool -certreq \
  -alias client-key \
  -keystore connector-keystore.jks \
  -storepass "${KEYSTORE_PASSWORD}" \
  -file client-cert.csr

# Sign client certificate with CA
echo "Signing client certificate with CA..."
keytool -gencert \
  -alias ca-cert \
  -keystore ca-keystore.jks \
  -storepass "${CA_PASSWORD}" \
  -infile client-cert.csr \
  -outfile client-cert-signed.pem \
  -validity ${CERT_VALIDITY_DAYS} \
  -rfc

# Import CA certificate into client keystore (required before importing signed cert)
echo "Importing CA certificate into client keystore..."
keytool -import -trustcacerts \
  -alias ca-cert \
  -file ca-cert.pem \
  -keystore connector-keystore.jks \
  -storepass "${KEYSTORE_PASSWORD}" \
  -noprompt

# Import signed client certificate
echo "Importing signed client certificate into keystore..."
keytool -import \
  -alias client-key \
  -file client-cert-signed.pem \
  -keystore connector-keystore.jks \
  -storepass "${KEYSTORE_PASSWORD}" \
  -noprompt

echo "✓ Client certificate created and signed"
echo ""

echo "=========================================="
echo "Step 4: Create Truststore for Connector"
echo "=========================================="
echo ""

# Create truststore with CA certificate
echo "Creating truststore with CA certificate..."
keytool -import -trustcacerts \
  -alias ca-cert \
  -file ca-cert.pem \
  -keystore connector-truststore.jks \
  -storepass "${TRUSTSTORE_PASSWORD}" \
  -noprompt

echo "✓ Truststore created"
echo ""

echo "=========================================="
echo "Step 5: Configure IBM MQ for Mutual TLS"
echo "=========================================="
echo ""

# Update queue manager to use SSL
echo "Configuring queue manager SSL settings..."
sudo -u ${MQ_USER} runmqsc ${QM_NAME} << EOF
ALTER QMGR CERTLABL('ibmmqserver')
ALTER QMGR SSLKEYR('${SSL_DIR}/key')
REFRESH SECURITY TYPE(SSL)
EOF

# Configure channel for mutual TLS
echo ""
echo "Configuring CONFLUENT.CHL channel for mutual TLS..."
# Note: Using ANY_TLS12 for maximum compatibility
# For production, specify exact cipher: ECDHE_RSA_AES_128_CBC_SHA256
sudo -u ${MQ_USER} runmqsc ${QM_NAME} << EOF
DEFINE CHANNEL('CONFLUENT.CHL') CHLTYPE(SVRCONN) TRPTYPE(TCP) SSLCAUTH(REQUIRED) SSLCIPH('ANY_TLS12') REPLACE
REFRESH SECURITY TYPE(SSL)
EOF

echo ""
echo "✓ MQ configured for mutual TLS"
echo ""

echo "=========================================="
echo "Step 6: Verify Configuration"
echo "=========================================="
echo ""

# List certificates in MQ keystore
echo "Certificates in MQ keystore:"
sudo -u ${MQ_USER} runmqakm -cert -list \
  -db "${SSL_DIR}/key.kdb" \
  -stashed

echo ""
echo "Certificates in client keystore:"
keytool -list -v \
  -keystore connector-keystore.jks \
  -storepass "${KEYSTORE_PASSWORD}" \
  | grep -E "(Alias|Owner|Issuer|Serial)"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Files created in ${WORK_DIR}:"
echo "  ca-cert.pem                  - CA certificate (for reference)"
echo "  connector-keystore.jks       - Client keystore (for Confluent connector)"
echo "  connector-truststore.jks     - Truststore with CA cert (for Confluent connector)"
echo ""
echo "MQ Configuration:"
echo "  SSL Directory: ${SSL_DIR}"
echo "  Certificate Label: ibmmqserver"
echo "  Channel: CONFLUENT.CHL"
echo "  MQ Cipher Spec: ANY_TLS12"
echo "  Client Auth: REQUIRED"
echo ""
echo "Passwords (save these securely):"
echo "  Keystore password:   ${KEYSTORE_PASSWORD}"
echo "  Truststore password: ${TRUSTSTORE_PASSWORD}"
echo ""
echo "Next steps:"
echo "  1. Copy connector-keystore.jks and connector-truststore.jks to a secure location"
echo "  2. Update terraform.tfvars with SSL configuration:"
echo ""
echo "     mq_ssl_cipher_suite = \"SSL_RSA_WITH_AES_128_CBC_SHA256\""
echo "     mq_ssl_keystore_location = \"<path-to-keystore>\""
echo "     mq_ssl_keystore_password = \"${KEYSTORE_PASSWORD}\""
echo "     mq_ssl_truststore_location = \"<path-to-truststore>\""
echo "     mq_ssl_truststore_password = \"${TRUSTSTORE_PASSWORD}\""
echo ""
echo "     Note: Cipher suite name differs between IBM MQ and Java:"
echo "           MQ uses: ANY_TLS12"
echo "           Java uses: SSL_RSA_WITH_AES_128_CBC_SHA256 (or TLS_RSA_WITH_AES_128_CBC_SHA256)"
echo ""
echo "  3. Run terraform apply to deploy connector with SSL"
echo ""
echo "Note: In production, use strong passwords and store them in a secrets manager!"
echo ""
