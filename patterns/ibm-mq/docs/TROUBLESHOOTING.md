# IBM MQ Connector Troubleshooting Guide

Common issues and solutions for IBM MQ Source connector deployment.

## Connection Issues

### Error: "Connection refused" or "MQRC_HOST_NOT_AVAILABLE"

**Symptoms:**
- Connector cannot connect to IBM MQ
- Error code: MQRC_HOST_NOT_AVAILABLE (2538)

**Causes:**
1. MQ listener not running
2. Firewall blocking port 1414
3. Wrong hostname/IP address
4. Network connectivity issues

**Solutions:**

1. **Check MQ listener status:**
```bash
sudo su - mqm
runmqsc QM1
DISPLAY LISTENER(SYSTEM.SSL.LISTENER.TCP)
end
```

Expected output: `STATUS(RUNNING)`

2. **Start listener if stopped:**
```bash
runmqsc QM1
START LISTENER(SYSTEM.SSL.LISTENER.TCP)
end
```

3. **Check firewall:**
```bash
# Azure NSG
az network nsg rule list --nsg-name <nsg-name> --resource-group <rg>

# Ubuntu firewall
sudo ufw status
sudo ufw allow 1414/tcp
```

4. **Verify connectivity:**
```bash
# From local machine or Confluent connector VNet
nc -zv <mq-hostname> 1414
telnet <mq-hostname> 1414
```

---

## TLS/SSL Issues

### Error: "SSL Handshake Failed" or "MQRC_SSL_INITIALIZATION_ERROR"

**Symptoms:**
- Connection attempt fails during TLS handshake
- Error code: MQRC_SSL_INITIALIZATION_ERROR (2393)

**Causes:**
1. Certificate CN doesn't match hostname
2. Wrong keystore or truststore
3. Incorrect keystore password
4. Missing CA certificate in truststore

**Solutions:**

1. **Verify certificate CN matches hostname:**
```bash
keytool -list -v -keystore ssl-certs/connector-keystore.jks -storepass <KEYSTORE_PASSWORD> \
  | grep "Owner:"
```

Should show: `CN=<hostname-used-in-connector>`

2. **Verify CA certificate in truststore:**
```bash
keytool -list -v -keystore ssl-certs/connector-truststore.jks -storepass <KEYSTORE_PASSWORD>
```

Should list the CA certificate.

3. **Check MQ SSL channel configuration:**
```bash
sudo su - mqm
runmqsc QM1
DISPLAY CHANNEL(CONFLUENT.CHL)
end
```

Expected: `SSLCIPH(TLS_RSA_WITH_AES_256_CBC_SHA256)` or similar

4. **Recreate certificates if needed:**
```bash
cd scripts/
./cleanup-mutual-tls.sh
./setup-mutual-tls.sh <correct-dns-domain>
```

### Error: "Certificate Not Trusted"

**Cause**: CA certificate not in truststore or wrong CA

**Solution**:
```bash
# Re-import CA certificate
keytool -import -alias ca-cert \
  -file ssl-certs/ca-cert.pem \
  -keystore ssl-certs/connector-truststore.jks \
  -storepass <KEYSTORE_PASSWORD>
```

---

## Authentication/Authorization Issues

### Error: "MQRC_NOT_AUTHORIZED" (2035)

**Symptoms:**
- Connection succeeds but authentication fails
- Error code: MQRC_NOT_AUTHORIZED (2035)

**Causes:**
1. Client certificate not authorized on MQ channel
2. User permissions not set
3. CHLAUTH rules blocking connection

**Solutions:**

1. **Check channel authentication:**
```bash
sudo su - mqm
runmqsc QM1
DISPLAY CHLAUTH(CONFLUENT.CHL)
end
```

2. **Set channel permissions:**
```bash
runmqsc QM1
SET CHLAUTH(CONFLUENT.CHL) TYPE(SSLPEERMAP) SSLPEER('CN=connector-client') USERSRC(NOACCESS) ACTION(REPLACE)
end
```

3. **Grant queue permissions:**
```bash
setmqaut -m QM1 -t qmgr -p mqm +connect +inq
setmqaut -m QM1 -n DEV.QUEUE.1 -t queue -p mqm +browse +get +inq
```

---

## Message Flow Issues

### Messages Not Appearing in Kafka

**Symptoms:**
- Connector shows RUNNING
- MQ queue has messages (CURDEPTH > 0)
- No messages in Kafka topic

**Causes:**
1. Wrong queue name
2. Queue empty (messages already consumed)
3. Connector not configured for queue
4. Message conversion errors

**Solutions:**

1. **Verify queue has messages:**
```bash
echo "DISPLAY QLOCAL(DEV.QUEUE.1) CURDEPTH" | runmqsc QM1
```

2. **Check connector configuration:**
```bash
confluent connect cluster describe <connector-id> | grep "mq.queue"
```

Should match actual queue name.

3. **Generate test messages:**
```bash
cd scripts/
./mq-message-generator.sh 10
```

4. **Check connector logs:**
```bash
confluent connect cluster describe <connector-id>
# Look for errors in trace output
```

### Connector Shows FAILED State

**Symptoms:**
- Connector task shows FAILED
- Error in connector status

**Solutions:**

1. **Get detailed error:**
```bash
confluent connect cluster describe <connector-id> -o json | jq '.info.tasks[0].trace'
```

2. **Common fixes:**
   - Restart connector: `confluent connect cluster update <connector-id> --config <json-file>`
   - Verify all configurations are correct
   - Check MQ queue manager is running

---

## Idle Timeout and Reconnection Issues

### Connector Repeatedly Reconnecting

**Symptoms:**
- Connector logs show frequent reconnections
- Connection drops during idle periods
- Error: "Connection reset by peer"

**Causes:**
1. Application Gateway idle timeout too low
2. MQ heartbeat interval not configured
3. Misaligned timeout values

**Solutions:**

1. **Verify heartbeat configuration in connector:**
```json
{
  "mq.client.heartbeat.interval": "300"
}
```

2. **Check Application Gateway idle timeout:**
```bash
az network application-gateway show \
  --name <appgw-name> \
  --resource-group <rg> \
  --query 'backendHttpSettingsCollection[0].requestTimeout'
```

Should be > 300 seconds (preferably 900 for 15 minutes).

3. **Update idle timeout if needed:**
```bash
# Via Terraform
# Set appgw_idle_timeout_minutes = 15 in terraform.tfvars
terraform apply

# Or via Azure CLI
az network application-gateway http-settings update \
  --gateway-name <appgw-name> \
  --resource-group <rg> \
  --name <settings-name> \
  --timeout 900
```

See [HEARTBEAT-CONFIG.md](./HEARTBEAT-CONFIG.md) for detailed configuration.

---

## Performance Issues

### Slow Message Processing

**Symptoms:**
- Messages take long time to appear in Kafka
- High latency
- Connector lag increasing

**Causes:**
1. Single task connector (low parallelism)
2. Network latency
3. Large messages
4. MQ queue manager overloaded

**Solutions:**

1. **Increase connector tasks:**
```json
{
  "tasks.max": "3"
}
```

2. **Check network latency:**
```bash
# From connector VNet to MQ
ping <mq-hostname>
```

3. **Monitor MQ queue manager:**
```bash
# CPU usage
echo "DISPLAY QMSTATUS TYPE(ALL)" | runmqsc QM1
```

---

## Certificate Expiration

### Error: "Certificate Expired"

**Symptoms:**
- Previously working connector suddenly fails
- TLS handshake error with expiration message

**Cause**: Self-signed certificates have expired (typically 365 days)

**Solution**:

1. **Check certificate expiration:**
```bash
keytool -list -v -keystore ssl-certs/connector-keystore.jks \
  -storepass <KEYSTORE_PASSWORD> | grep "Valid"
```

2. **Regenerate all certificates:**
```bash
cd scripts/
./cleanup-mutual-tls.sh
./setup-mutual-tls.sh <dns-domain>
```

3. **Upload new keystores to Confluent:**
```bash
cd ssl-certs/
base64 connector-keystore.jks > connector-keystore.b64
base64 connector-truststore.jks > connector-truststore.b64
# Upload to secrets manager
```

4. **Update connector with new keystores**

---

## Debugging Commands

### Check MQ Queue Manager Status

```bash
sudo su - mqm
dspmq -m QM1
```

### Check Channel Status

```bash
echo "DISPLAY CHSTATUS(CONFLUENT.CHL) ALL" | runmqsc QM1
```

### Check Queue Depth

```bash
echo "DISPLAY QLOCAL(DEV.QUEUE.1) CURDEPTH MAXDEPTH" | runmqsc QM1
```

### View MQ Errors

```bash
# Queue manager errors
cat /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG

# Channel errors
cat /var/mqm/qmgrs/QM1/errors/AMQERR*.LOG | grep CONFLUENT.CHL
```

### Test TLS Connection

```bash
# Using openssl
openssl s_client -connect <mq-hostname>:1414 -CAfile ssl-certs/ca-cert.pem

# Using MQ sample
/opt/mqm/samp/bin/amqsputc DEV.QUEUE.1 QM1
```

---

## Getting Help

If you're still experiencing issues:

1. **Collect diagnostics:**
   - Connector status and logs
   - MQ error logs
   - Network connectivity tests
   - Certificate details

2. **Check documentation:**
   - [SSL-TLS-SETUP.md](./SSL-TLS-SETUP.md)
   - [HEARTBEAT-CONFIG.md](./HEARTBEAT-CONFIG.md)
   - [IBM MQ Documentation](https://www.ibm.com/docs/en/ibm-mq)

3. **Open GitHub issue** with diagnostics attached

---

## Related Documentation

- [../README.md](../README.md) - Pattern overview
- [SSL-TLS-SETUP.md](./SSL-TLS-SETUP.md) - Complete SSL setup guide
- [HEARTBEAT-CONFIG.md](./HEARTBEAT-CONFIG.md) - Heartbeat configuration
- [TCP-PROXY-SETUP.md](./TCP-PROXY-SETUP.md) - TCP proxy for testing
