# Tableflow to Azure Storage via Application Gateway and NGINX

Confluent Cloud Tableflow writes Iceberg/Delta tables to your ADLS Gen2 storage account. This pattern keeps that traffic private: Confluent egress → Application Gateway → NGINX (SNI routing) → Private Link endpoints → storage account with public access disabled.

## Options

1. **NGINX VM:** Confluent egress → AppGW → NGINX VM (stream, SNI preread) → private endpoints
2. **NGINXaaS:** Confluent egress → AppGW → NGINXaaS (same config) → private endpoints

Both use the same NGINX config, see [docs/nginx-stream.conf.example](./docs/nginx-stream.conf.example).

## Why NGINX is in the path

Tableflow talks to **two** hostnames on the same account, both on port 443:

- `<account>.blob.core.windows.net`
- `<account>.dfs.core.windows.net`

Each needs its own private endpoint (sub-resources `blob` and `dfs`), so something has to pick the right endpoint per connection. NGINX's `stream` module does this with `ssl_preread`, routing on the TLS SNI name without terminating TLS.

## Architecture

```
Confluent Tableflow
  │  egress DNS: <account>.blob/.dfs.core.windows.net → EAP
  ▼
EAP → Application Gateway (private frontend, TCP/TLS listener 443)
  ▼
NGINX stream (ssl_preread, routes on SNI, no TLS termination)
  ├─ <account>.blob.core.windows.net → private endpoint (blob)
  └─ <account>.dfs.core.windows.net  → private endpoint (dfs)
  ▼
Storage account (public network access disabled)
```

## Setup

### 1. Entra service principal for Confluent (provider integration)

Confluent creates a multi-tenant app; you create its service principal in your tenant. This needs an Entra role such as **Application Administrator**. Without one the command fails with "the backing application ... must in the local tenant".

```bash
az ad sp create --id <CONFLUENT_APP_ID>          # shown in the provider integration wizard
```

Then finish the integration in the Confluent Cloud console ("Complete" / validate).

### 2. Storage account and roles

```bash
az group create -n <rg> -l <region>
az storage account create -n <account> -g <rg> -l <region> --sku Standard_LRS --kind StorageV2 \
  --enable-hierarchical-namespace true --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container-rm create --storage-account <account> -g <rg> -n tableflow

SP=<service principal object id>
az role assignment create --assignee-object-id $SP --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope <storage account resource id>
az role assignment create --assignee-object-id $SP --assignee-principal-type ServicePrincipal \
  --role "Reader" --scope <resource group id>
```

Tableflow itself needs only these two. Roles the wizard lists for Cosmos DB, Key Vault, Azure Data Explorer and SQL are for other integrations. Assign them per resource when those exist, and never at subscription scope.

### 3. Private endpoints (blob and dfs)

```bash
./scripts/setup-private-endpoints.sh <vnet-rg> <vnet> <subnet> <storage-account-resource-id>          # dry run
./scripts/setup-private-endpoints.sh <vnet-rg> <vnet> <subnet> <storage-account-resource-id> --apply
```

If the VNet and the storage account are in **different Entra tenants**, Azure can't auto-approve. The script creates manual-approval requests and you approve them on the storage side (the script prints the commands).

### 4. Private DNS

Create `privatelink.blob.core.windows.net` and `privatelink.dfs.core.windows.net`, link both to the VNet, and add an A record for each of your account's names pointing at its private endpoint IP. NGINX must resolve names to those IPs, or you must hardcode the IPs in its map (see the example).

### 5. NGINX stream config

See [docs/nginx-stream.conf.example](./docs/nginx-stream.conf.example). The same file is used on the VM and on NGINXaaS. It resolves the SNI name through Azure DNS (`168.63.129.16`), so the private DNS zones from step 4 must be linked to the VNet.

### 6. AppGW and Confluent egress

Point the AppGW TCP/TLS listener (443) at NGINX. In Confluent, create egress DNS entries for both storage hostnames pointing at the EAP that targets the gateway.

## Cutover order and operational notes

Tableflow suspends on storage-access errors and **does not resume itself**. In our test it stayed failed for 2+ hours until "Resume Tableflow" was clicked. Per Confluent's docs, storage and catalog access errors always pause the topic, whatever the record failure setting.

1. Build and verify the whole private path first.
2. Change the egress DNS to the EAP.
3. Disable storage public access.
4. Resume Tableflow and confirm files appear in the container.

Treat anything that breaks the path (DNS changes, NGINX or AppGW restarts, private endpoint changes) as needing a manual resume. Set up a Confluent Cloud notification for Tableflow syncing failures so a suspension doesn't go unnoticed.

## Source filtering

NSG rules are not enforced on private endpoint traffic unless `privateEndpointNetworkPolicies` is enabled on the endpoint subnet. In a subnet shared with other private endpoints, enabling it affects all of them. Check before relying on an NSG to limit sources.

## Option 2: NGINXaaS

Replace the NGINX VM with Azure NGINXaaS running the same config, unchanged. NGINXaaS is injected into a delegated subnet of the VNet, so it reaches the private endpoints and the linked private DNS zones the same way the VM does.

### Logs

The deployment's logging ships `/var/log/nginx/stream-access.log`. The lines arrive in Azure Monitor / Log Analytics as table `NGXOperationLogs`, with the `FilePath` field set to that log file. Each line shows the source port, listener and destination:

```
[22/Oct/2026:13:14:13 +0000] remote address <appgw-ip>:43862 with SNI name "<account>.dfs.core.windows.net" proxied to "<dfs-pe-ip>:443" by listener=<nginx-ip>:443 TCP 200 8558 1930 20.000
```
