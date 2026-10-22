# Tableflow to Azure Storage via Application Gateway and NGINX

Confluent Cloud Tableflow writes Iceberg/Delta tables to your ADLS Gen2 storage account. This pattern keeps that traffic private: Confluent egress → Application Gateway → NGINX (SNI routing) → Private Link endpoints → storage account with public access disabled.

## Status

| Option | Status |
|--------|--------|
| 1. EAP → AppGW → NGINX VM (stream, SNI preread) → private endpoints | **Tested**: NGINX logs show blob and dfs traffic from the AppGW subnet; Tableflow resumed and ran after a manual resume |
| 2. EAP → AppGW → NGINXaaS → private endpoints | **Tested**: the same config as option 1 routes blob and dfs traffic through NGINXaaS to their private endpoints, Tableflow files appear in the container, and Confluent's Tableflow metrics show the writes (see Results) |
| 3. One EAP + AppGW per hostname (blob, dfs), no NGINX | **Untested.** Expected to work in principle; scales poorly (see below) |

## Why NGINX is in the path

Tableflow talks to **two** hostnames on the same account, both on port 443:

- `<account>.blob.core.windows.net`
- `<account>.dfs.core.windows.net`

Each needs its own private endpoint (sub-resources `blob` and `dfs`), so something has to pick the right endpoint per connection. NGINX's `stream` module does this with `ssl_preread`, routing on the TLS SNI name without terminating TLS. Our working assumption is that an AppGW backend pool can't make that per-hostname choice for two names on one port. We haven't verified this against current AppGW TCP/TLS proxy documentation, so check it before relying on the claim.

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

Logs: the deployment's logging is set to ship `/var/log/nginx/stream-access.log`. The lines arrive in Azure Monitor / Log Analytics as table `NGXOperationLogs`, with the `FilePath` field set to that log file.

Still to check and record here: idle timeouts against the AppGW listener, and cost against the VM.

### Results

Blob and dfs traffic from the AppGW subnet reached their private endpoints through NGINXaaS, logged within a second of each other (source port, listener and destination are visible in each line):

```
[22/Oct/2026:13:14:13 +0000] remote address 172.200.9.5:43874 with SNI name "<account>.blob.core.windows.net" proxied to "172.200.4.16:443" by listener=172.200.7.11:443 TCP 200 75837 50811 20.001
```

```
[22/Oct/2026:13:14:13 +0000] remote address 172.200.9.5:43862 with SNI name "<account>.dfs.core.windows.net" proxied to "172.200.4.17:443" by listener=172.200.7.11:443 TCP 200 8558 1930 20.000
```

Files were confirmed in the storage container, and Confluent's Tableflow metrics show the same writes, with public access to the account disabled.

`172.200.9.5` is an AppGW instance and `172.200.7.11` an NGINXaaS node in its subnet.

## Option 3: AppGW only, one gateway per hostname (untested)

Tableflow needs two hostnames per storage account on port 443. If an AppGW can't choose a backend per hostname on a single port (our working assumption, unverified), each hostname gets its own gateway and its own EAP:

```
<account>.blob.core.windows.net → egress DNS → EAP 1 → AppGW A (TCP listener 443) → blob private endpoint
<account>.dfs.core.windows.net  → egress DNS → EAP 2 → AppGW B (TCP listener 443) → dfs private endpoint
```

The limit is the EAPs: an egress DNS entry maps a hostname to one EAP, and an EAP targets one destination.

**Cost and scale:** per storage account you need 2 EAPs and 2 gateways, which multiplies with every account. At roughly $150-180/month per gateway (see [azure-sql-failover cost analysis](../azure-sql-failover/COST-ANALYSIS.md), not verified for your SKU) this is about $300+/month per account in gateway cost alone. NGINX or NGINXaaS shares one proxy and one gateway across any number of accounts because it routes on the SNI name. EAP quotas per cluster or environment are not verified, so check them first.

**Not verified:**
- That an AppGW TCP-proxy listener passes the TLS session through untouched to a storage private endpoint.
- Whether one gateway with two private frontend IPs could separate the hostnames (we believe v2 allows only one private frontend IP).
- That Confluent accepts two egress entries for the same account that differ only by sub-resource hostname.

Prefer Options 1 or 2 unless you have a hard requirement to avoid NGINX.
