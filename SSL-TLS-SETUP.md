# IBM MQ SSL/TLS Configuration Guide

This guide walks you through setting up mutual TLS authentication between Confluent Cloud connectors and IBM MQ using self-signed certificates.

## Overview

The setup involves:
1. Creating a self-signed Certificate Authority (CA)
2. Generating and signing certificates for IBM MQ server
3. Generating and signing certificates for Confluent connector (client)
4. Configuring IBM MQ to require mutual TLS
5. Configuring the Confluent connector to use the certificates

## Prerequisites

- IBM MQ installed on Ubuntu
- Queue Manager `QM1` running
- Java `keytool` available
- IBM MQ `runmqakm` command available
- Access to run commands as `mqm` user (sudo)

## Step 1: Run the Setup Script

The automated script creates all necessary certificates and configures MQ.

```bash
# Make the script executable
chmod +x scripts/setup-mutual-tls.sh

# Run the script (requires sudo for MQ configuration)
./scripts/setup-mutual-tls.sh
```

**What the script does:**
- Creates self-signed CA certificate
- Creates IBM MQ server certificate signed by CA
- Creates client certificate for connector signed by CA
- Configures MQ queue manager with SSL settings
- Configures `CONFLUENT.CHL` channel for mutual TLS
- Creates Java keystores (connector-keystore.jks, connector-truststore.jks)

**Output files in `ssl-certs/` directory:**
- `ca-cert.pem` - CA certificate (for reference)
- `connector-keystore.jks` - Client keystore with signed certificate
- `connector-truststore.jks` - Truststore with CA certificate
- `ca-keystore.jks` - CA private key (keep secure!)
- `mq-server.csr` - MQ server certificate request
- `mq-server-signed.pem` - Signed MQ server certificate
- `client-cert.csr` - Client certificate request
- `client-cert-signed.pem` - Signed client certificate

## Step 2: Upload Keystores to Confluent Cloud

Confluent Cloud connectors need access to the keystore and truststore files. You'll need to upload them as secrets.

### Option 1: Base64 Encode and Store in Secrets Manager

```bash
cd ssl-certs

# Encode keystore
base64 connector-keystore.jks > connector-keystore.b64

# Encode truststore
base64 connector-truststore.jks > connector-truststore.b64
```

Then upload these to your preferred secrets manager (AWS Secrets Manager, Azure Key Vault, etc.).

### Option 2: Direct Upload to Confluent Cloud

If using Confluent Cloud's built-in secrets management:

```bash
# Upload via Confluent CLI (if supported)
# Or reference them in your connector configuration
```

## Step 3: Update Terraform Configuration

Update your `terraform.tfvars` with SSL/TLS settings:

```hcl
# IBM MQ SSL/TLS Configuration
# Note: Use Java/JVM cipher suite name (differs from IBM MQ cipher spec)
mq_ssl_cipher_suite = "SSL_RSA_WITH_AES_128_CBC_SHA256"

# Option A: If keystores are uploaded to Confluent Cloud
mq_ssl_keystore_location = "confluent-secret://keystore"
mq_ssl_keystore_password = "connector-keystore-123"
mq_ssl_truststore_location = "confluent-secret://truststore"
mq_ssl_truststore_password = "connector-truststore-123"

# Option B: If using base64-encoded secrets
# mq_ssl_keystore_location = "${base64:file://path/to/connector-keystore.b64}"
# mq_ssl_truststore_location = "${base64:file://path/to/connector-truststore.b64}"
```

**Important Notes:**
- **Cipher Suite Names Differ**: IBM MQ uses `ANY_TLS12` while Java/JVM uses `SSL_RSA_WITH_AES_128_CBC_SHA256` or `TLS_RSA_WITH_AES_128_CBC_SHA256`
  - IBM MQ cipher spec: `ANY_TLS12` (allows any TLS 1.2 cipher)
  - Java cipher suite: `SSL_RSA_WITH_AES_128_CBC_SHA256` (specific cipher for connector)
  - Both can negotiate a compatible cipher during handshake
- Passwords are from the setup script output (change for production!)
- Confluent Cloud has specific requirements for how keystores are referenced
- Check Confluent documentation for the exact secret reference format

## Step 4: Deploy the Connector

```bash
# Apply Terraform configuration with SSL settings
terraform apply
```

The connector will now use mutual TLS to connect to IBM MQ.

## Step 5: Generate Test Messages

To validate your connector configuration, use the message generator script to continuously put JSON messages onto the queue:

```bash
# On the IBM MQ server
./scripts/mq-message-generator.sh DEV.QUEUE.1 QM1 30
```

**What it does:**
- Generates JSON messages with timestamps and random data
- Puts messages onto the queue every 30 seconds (configurable)
- Runs continuously until stopped with Ctrl+C
- Shows message count and timestamps

**Example output:**
```
==========================================
IBM MQ Message Generator
==========================================

Configuration:
  Queue:          DEV.QUEUE.1
  Queue Manager:  QM1
  Interval:       30 seconds

Press Ctrl+C to stop

Starting message generation...

[2026-03-20 14:30:00] Message #1 sent to DEV.QUEUE.1
[2026-03-20 14:30:30] Message #2 sent to DEV.QUEUE.1
[2026-03-20 14:31:00] Message #3 sent to DEV.QUEUE.1
```

**Custom usage:**
```bash
# Different queue
./scripts/mq-message-generator.sh MY.QUEUE QM1 30

# Faster interval (10 seconds)
./scripts/mq-message-generator.sh DEV.QUEUE.1 QM1 10

# Run in background
nohup ./scripts/mq-message-generator.sh DEV.QUEUE.1 QM1 30 > /tmp/mq-generator.log 2>&1 &

# Stop background process
pkill -f mq-message-generator
```

## Step 6: Verify the Connection

### Check MQ Logs

```bash
# On the IBM MQ server
tail -f /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG
```

Look for successful SSL handshake messages.

### Check Connector Status

```bash
# Get connector status
terraform output connector_status

# Or via Confluent Cloud UI
# Navigate to Connectors → Your Connector → Status
```

Expected: `RUNNING` status

### Monitor Messages Flowing

```bash
# Watch messages being consumed from MQ
echo "DISPLAY QSTATUS(DEV.QUEUE.1) CURDEPTH" | runmqsc QM1

# Check Kafka topic for messages
# Via Confluent Cloud UI or CLI
confluent kafka topic consume ibm-mq-messages --from-beginning
```

The queue depth should remain low if the connector is successfully consuming messages.

### Test SSL Connection with MQ Sample Client

```bash
# Set environment variables
export MQSERVER='CONFLUENT.CHL/TCP/localhost(1414)'
export MQSSLKEYR='/path/to/ssl-certs/connector-keystore'
export MQSSLRESET=999999999

# Test with amqsputc sample
echo "TEST MESSAGE" | /opt/mqm/samp/bin/amqsputc DEV.QUEUE.1 QM1
```

## Troubleshooting

### Error: "MQRC_SSL_INITIALIZATION_ERROR (2393)"

**Cause**: Keystore or truststore not accessible or incorrect password

**Solution**:
- Verify keystore files are uploaded correctly
- Check passwords match those from setup script
- Verify Confluent Cloud can access the secret location

### Error: "MQRC_SSL_PEER_NAME_MISMATCH (2398)"

**Cause**: Certificate CN doesn't match expected hostname

**Solution**:
- Check MQ server certificate CN matches connection hostname
- For testing, you may need to disable peer name validation (not recommended for production)

### Error: "MQRC_SSL_CERT_STORE_ERROR (2381)"

**Cause**: MQ can't find or access its key database

**Solution**:
```bash
# Verify MQ keystore exists and has correct permissions
ls -la /var/mqm/qmgrs/QM1/ssl/key.*
sudo chown mqm:mqm /var/mqm/qmgrs/QM1/ssl/key.*
sudo chmod 600 /var/mqm/qmgrs/QM1/ssl/key.*
```

### Error: "MQRC_NOT_AUTHORIZED (2035)" with SSL

**Cause**: SSL handshake succeeded but authorization failed

**Solution**:
- Verify CHLAUTH rules allow the client certificate's DN
- Check connection authentication settings

```bash
# Allow connections with client certificates
runmqsc QM1 << EOF
SET CHLAUTH('CONFLUENT.CHL') TYPE(SSLPEERMAP) SSLPEER('CN=confluent-connector,OU=Connectors,O=ConfluentDemo,C=US') USERSRC(MAP) MCAUSER('confluent') ACTION(ADD)
REFRESH SECURITY TYPE(SSL)
EOF
```

### Verify Certificate Chain

```bash
# Check certificates in keystore
keytool -list -v -keystore ssl-certs/connector-keystore.jks -storepass connector-keystore-123

# Check certificates in truststore
keytool -list -v -keystore ssl-certs/connector-truststore.jks -storepass connector-truststore-123

# Check MQ certificates
sudo runmqakm -cert -list -db /var/mqm/qmgrs/QM1/ssl/key.kdb -stashed
```

### Enable SSL Debug Logging in MQ

```bash
# Edit qm.ini
sudo vi /var/mqm/qmgrs/QM1/qm.ini

# Add under SSL stanza:
SSL:
  SSLTraceLevel=9

# Restart queue manager
sudo -u mqm endmqm QM1
sudo -u mqm strmqm QM1

# Check SSL trace
tail -f /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG
```

## Certificate Renewal

Certificates created by the script are valid for 365 days. To renew:

1. Generate new certificates using the same CA
2. Update MQ keystore with new server certificate
3. Update connector keystore with new client certificate
4. Update Confluent Cloud secrets
5. Restart connector

## Production Considerations

### Use Proper Passwords

Replace test passwords with strong, randomly generated passwords:

```bash
# Generate strong passwords
openssl rand -base64 32  # For keystore password
openssl rand -base64 32  # For truststore password
```

### Use a Proper CA

For production:
- Use your organization's CA
- Or use a commercial CA like DigiCert, Let's Encrypt
- Store CA private key in a Hardware Security Module (HSM)

### Certificate Management

- Implement automated certificate renewal before expiry
- Monitor certificate expiration dates
- Keep certificate revocation lists (CRLs) updated
- Use certificate pinning for critical connections

### Secrets Management

- Store passwords in a proper secrets manager (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault)
- Rotate passwords regularly
- Use short-lived credentials where possible
- Enable audit logging for secret access

## Reference

### Cipher Suites

**Important**: IBM MQ and Java/JVM use different naming conventions for cipher suites.

#### Cipher Suite Mapping

| IBM MQ Cipher Spec | Java/JVM Cipher Suite | TLS Version | Notes |
|--------------------|----------------------|-------------|-------|
| `ANY_TLS12` | Any TLS 1.2 suite | TLS 1.2 | Allows negotiation (works well for testing) |
| `ECDHE_RSA_AES_128_CBC_SHA256` | `TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256` | TLS 1.2 | Strong forward secrecy |
| `ECDHE_RSA_AES_256_GCM_SHA384` | `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384` | TLS 1.2 | Strongest option |
| `TLS_RSA_WITH_AES_128_CBC_SHA256` | `SSL_RSA_WITH_AES_128_CBC_SHA256` or `TLS_RSA_WITH_AES_128_CBC_SHA256` | TLS 1.2 | Basic compatibility |

**Setup Script Configuration:**
- MQ side uses: `ANY_TLS12` (flexible, allows negotiation)
- Connector side should use: `SSL_RSA_WITH_AES_128_CBC_SHA256` or `TLS_RSA_WITH_AES_128_CBC_SHA256`

**For Production:**
Use specific cipher specs instead of `ANY_TLS12`:
- Recommended: `ECDHE_RSA_AES_256_GCM_SHA384` (MQ) / `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384` (Java)
- This provides forward secrecy and stronger encryption

### File Permissions

Recommended permissions for certificate files:

```bash
# MQ keystore
chmod 600 /var/mqm/qmgrs/QM1/ssl/key.kdb
chmod 600 /var/mqm/qmgrs/QM1/ssl/key.sth
chown mqm:mqm /var/mqm/qmgrs/QM1/ssl/key.*

# Client keystores (before upload)
chmod 600 ssl-certs/*.jks
```

### Useful Commands

```bash
# Check MQ SSL configuration
echo "DISPLAY QMGR SSLKEYR CERTLABL" | runmqsc QM1

# Check channel SSL settings
echo "DISPLAY CHANNEL(CONFLUENT.CHL) SSLCIPH SSLCAUTH" | runmqsc QM1

# Test local SSL connection
export MQSSLKEYR=/path/to/ssl-certs/connector-keystore
/opt/mqm/samp/bin/amqsputc DEV.QUEUE.1 QM1

# View certificate details
openssl x509 -in ca-cert.pem -text -noout
```

## Additional Resources

- [IBM MQ SSL/TLS Configuration](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=mechanisms-ssltls-security-protocols-in-mq)
- [IBM MQ Cipher Specs](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=tls-ciphersuites-cipherspecifications)
- [Confluent Connector SSL Configuration](https://docs.confluent.io/kafka-connectors/ibm-mq-source/current/configuration_options.html#ssl-configuration)
- [Java Keytool Documentation](https://docs.oracle.com/en/java/javase/11/tools/keytool.html)
