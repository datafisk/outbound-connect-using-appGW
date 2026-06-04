# Orphan Files Analysis

## Summary

Found **12 orphan/obsolete files** that can be archived or deleted:

- 3 Documentation files (migration guides, legacy setup)
- 4 Shell scripts (Azure RAC dead ends, obsolete TCP config)
- 1 Terraform module directory (Azure RAC - dead end)
- Several files in modules that are Azure RAC related

---

## Files to Archive

### 📁 Root Documentation (3 files)

#### 1. `MIGRATION-TCP-NATIVE.md`
**Status:** ✅ Migration complete, historical only  
**Action:** Archive to `archive/legacy-docs/`  
**Reason:** Documents migration from PowerShell to native Terraform TCP support (April 2026). Migration is complete, file now only has historical value.

#### 2. `TCP-PROXY-SETUP.md`
**Status:** ⚠️ Partially obsolete, still referenced  
**Action:** Review and update, or archive non-Terraform sections  
**Reason:** Documents both new (Terraform) and legacy (PowerShell/Portal) TCP setup. The Terraform section is now the default. Legacy sections only needed for pre-existing AppGWs.  
**Referenced in:** README.md mentions it for IBM MQ configuration  
**Recommendation:** Keep but add warning at top that native Terraform is now preferred

#### 3. No other docs to archive

---

### 📁 Root Scripts (4 files)

#### 1. `configure-tcp-proxy.sh`
**Status:** ❌ Obsolete  
**Action:** Delete or archive to `archive/legacy-scripts/`  
**Reason:** Used to manually configure TCP proxy before Terraform support. No longer needed since we have native Terraform TCP support (April 2026).

#### 2. `check-azure-rac-quota.sh`
**Status:** ❌ Dead end  
**Action:** Archive to `archive/azure-rac-abandoned/`  
**Reason:** Checks Azure quota for Oracle RAC deployment in Azure. We abandoned Azure RAC and deployed to OCI instead.

#### 3. `find-available-rac-vm.sh`
**Status:** ❌ Dead end  
**Action:** Archive to `archive/azure-rac-abandoned/`  
**Reason:** Finds available VM sizes for Azure RAC. Dead end since we went with OCI RAC.

#### 4. `install-oracle-rac.sh`
**Status:** ❌ Dead end  
**Action:** Archive to `archive/azure-rac-abandoned/`  
**Reason:** Installs Oracle RAC on Azure VMs. Dead end since we deployed to OCI instead.

#### 5. `deploy.sh`
**Status:** ⚠️ Review needed  
**Action:** Check if referenced in documentation  
**Reason:** General deployment helper script. May still be useful for main infrastructure deployment.  
**Analysis needed:** Check if this is referenced anywhere or if users would benefit from it

---

### 📁 Terraform Modules

#### 1. `modules/oracle-rac/` (entire directory)
**Status:** ❌ Dead end (Azure RAC attempt)  
**Action:** Archive entire directory to `archive/azure-rac-module/`  
**Reason:** This module was for deploying Oracle RAC **on Azure** (Shared Disks, Azure VMs). We abandoned this approach and deployed RAC **on OCI** instead using `modules/oci-oracle-rac/`.

**Contents to archive:**
```
modules/oracle-rac/
├── README.md
├── EXISTING-RESOURCES.md
├── scripts/
│   ├── check-rac-status.sh
│   ├── configure-asm-disks.sh
│   ├── configure-xstream.sh
│   ├── install-database.sh
│   ├── install-grid-infrastructure.sh
│   └── setup-rac-wizard.sh
└── terraform/
    ├── compute.tf
    ├── main.tf
    ├── network.tf
    ├── outputs.tf
    ├── storage.tf
    └── variables.tf
```

**Note:** This represents significant work but is no longer the chosen path. Azure doesn't support RAC well (no multiattach for certain disk types, complex networking). OCI is the better platform for RAC.

---

## Files to KEEP

### 📁 Documentation (KEEP - All Current)

✅ **README.md** - Main repository documentation  
✅ **CONFLUENT-SETUP.md** - Confluent Cloud credential setup  
✅ **EXISTING-RESOURCES.md** - Using existing Azure resources  
✅ **IBM-MQ-HEARTBEAT.md** - IBM MQ heartbeat configuration  
✅ **MULTI-CONNECTOR.md** - Multi-connector setup guide  
✅ **OCI-GETTING-STARTED.md** - OCI setup for RAC (used!)  
✅ **ORACLE-RAC-APPGW-SETUP.md** - Complete Oracle RAC + AppGW guide  
✅ **ORACLE-RAC-DEPLOYMENT-GUIDE.md** - Oracle RAC deployment on OCI  
✅ **ORACLE-RAC-QUICKSTART.md** - Quick start for RAC + AppGW  
✅ **ORACLE-XSTREAM-SETUP.md** - XStream CDC connector  
✅ **REPO-CLEANUP-SUMMARY.md** - Repository cleanup summary  
✅ **SETUP.md** - Main setup guide  
✅ **SSL-TLS-SETUP.md** - SSL/TLS mutual auth setup  

### 📁 Terraform (KEEP - All Active)

✅ **main.tf** - Main infrastructure  
✅ **variables.tf** - Variable definitions  
✅ **terraform.tfvars.example** - Example configuration  
✅ **appgw-oracle-rac.tf** - AppGW Oracle RAC configuration  

### 📁 Connectors (KEEP - All Active)

✅ **connectors/README.md** - Connector documentation  
✅ **connectors/generate-config.sh** - Config generator  
✅ **connectors/ibm-mq-source.env.example** - IBM MQ config template  
✅ **connectors/ibm-mq-source.generated.json** - Generated config  
✅ **connectors/ibm-mq-source.json** - IBM MQ connector config  
✅ **connectors/oracle-xstream/README.md** - XStream documentation  
✅ **connectors/oracle-xstream/oracle-xstream.env.example** - XStream template  
✅ **oracle-rac-connector.json** - Oracle JDBC connector config  

### 📁 Scripts (KEEP - All Active)

✅ **scripts/cleanup-mutual-tls.sh** - TLS cleanup  
✅ **scripts/mq-message-generator.sh** - IBM MQ test messages  
✅ **scripts/setup-mutual-tls.sh** - TLS setup  

### 📁 Modules (KEEP - Active Modules)

#### modules/oci-oracle-rac/ ✅ (KEEP - This is what we're using!)
```
modules/oci-oracle-rac/
├── README.md
├── db-system.tf
├── network.tf
├── outputs.tf
├── provider.tf
└── variables.tf
```
**Reason:** This is the OCI RAC deployment we actually use. Keep!

#### modules/oracle-database/ ✅ (KEEP - Still useful)
```
modules/oracle-database/
├── README.md
├── scripts/00_setup_cdc.sh
└── terraform/
    ├── main.tf
    ├── outputs.tf
    └── variables.tf
```
**Reason:** Standalone Oracle XE deployment for dev/test. Still useful alternative to RAC.

---

## Recommended Actions

### Phase 1: Archive Dead Ends (High Priority)

```bash
# Create archive structure
mkdir -p archive/azure-rac-abandoned
mkdir -p archive/legacy-scripts
mkdir -p archive/legacy-docs

# Move Azure RAC dead ends
mv check-azure-rac-quota.sh archive/azure-rac-abandoned/
mv find-available-rac-vm.sh archive/azure-rac-abandoned/
mv install-oracle-rac.sh archive/azure-rac-abandoned/
mv modules/oracle-rac archive/azure-rac-abandoned/oracle-rac-module

# Move obsolete scripts
mv configure-tcp-proxy.sh archive/legacy-scripts/

# Move migration guide (historical only)
mv MIGRATION-TCP-NATIVE.md archive/legacy-docs/

# Update archive README
cat >> archive/README.md << 'EOF'

## azure-rac-abandoned/

Azure-based Oracle RAC deployment attempt (abandoned in favor of OCI):

- **check-azure-rac-quota.sh** - Azure quota checker
- **find-available-rac-vm.sh** - VM size finder
- **install-oracle-rac.sh** - Installation automation
- **oracle-rac-module/** - Complete Terraform module for Azure RAC

**Why abandoned:** Azure limitations with shared storage, complex networking, and 
better RAC support on OCI made OCI the better choice for production RAC deployments.

## legacy-scripts/

- **configure-tcp-proxy.sh** - Manual TCP proxy configuration (superseded by native Terraform)

## legacy-docs/

- **MIGRATION-TCP-NATIVE.md** - Migration guide from PowerShell to Terraform TCP (completed April 2026)
EOF
```

### Phase 2: Review Questionable Files (Medium Priority)

**Files needing review:**

1. **TCP-PROXY-SETUP.md**
   - Current status: Referenced in README
   - Action needed: Add prominent note that Terraform is now preferred
   - Keep legacy sections for reference only

2. **deploy.sh**
   - Current status: Unknown if used
   - Action needed: Check if referenced in docs
   - Decision: Keep if useful, otherwise archive

**Review commands:**
```bash
# Check if deploy.sh is referenced
grep -r "deploy.sh" *.md

# Check if TCP-PROXY-SETUP.md legacy sections are still needed
grep -r "TCP-PROXY-SETUP.md" *.md
```

### Phase 3: Update Documentation References (Low Priority)

After archiving, update any documentation that references archived files:

```bash
# Find references to archived files
grep -r "check-azure-rac-quota" *.md
grep -r "configure-tcp-proxy.sh" *.md
grep -r "modules/oracle-rac" *.md
grep -r "MIGRATION-TCP-NATIVE" *.md
```

---

## Impact Assessment

### Files Being Archived: 12 total

**Documentation:** 1 file (MIGRATION-TCP-NATIVE.md)  
**Scripts:** 4 files (configure-tcp-proxy.sh, check-azure-rac-quota.sh, find-available-rac-vm.sh, install-oracle-rac.sh)  
**Modules:** 1 directory (modules/oracle-rac/)  

### Storage Impact

- **Azure RAC module:** ~15 files, significant code (~1500+ lines)
- **Scripts:** 4 files (~500 lines total)
- **Docs:** 1 file (~100 lines)

**Total:** ~2100 lines of code/documentation being archived

### Risk Assessment

**Risk Level:** ✅ LOW

**Why safe to archive:**
1. Azure RAC was never completed or used in production
2. TCP proxy script superseded by Terraform native support
3. Migration guide is historical (migration already complete)
4. All current functionality uses different code (OCI RAC, Terraform TCP)

**Mitigation:**
- Files are archived, not deleted (can be restored if needed)
- Archive directory has README explaining why each file was archived
- Git history preserves all work

---

## Summary

**Recommended Archive Count:** 12 files/directories  
**Keep Count:** 50+ files (all active/current)  
**Review Needed:** 2 files (TCP-PROXY-SETUP.md, deploy.sh)  

**After cleanup:**
- Repository will be cleaner and easier to navigate
- Clear distinction between active and historical work
- Archive preserves all work with explanations
- No loss of functionality or historical context

**Next Steps:**
1. Execute Phase 1 commands to archive dead ends
2. Review TCP-PROXY-SETUP.md and deploy.sh
3. Update archive/README.md
4. Update any documentation references
5. Commit changes with descriptive message
