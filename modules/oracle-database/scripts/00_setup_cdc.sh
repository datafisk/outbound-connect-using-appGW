#!/bin/bash
# Oracle XStream CDC Setup Script
# Sets up Oracle Database for Confluent XStream CDC Connector
#
# Usage: ./00_setup_cdc.sh [SYS_PASSWORD] [PDB_NAME]
#
# Defaults: SYS_PASSWORD=Confluent123!, PDB_NAME=XEPDB1

set -e

# Configuration
SYS_PASSWORD="${1:-Confluent123!}"
PDB_NAME="${2:-XEPDB1}"
CDB_NAME="XE"
ORDERMGMT_PASSWORD="kafka"
CONTAINER_NAME="oracle21c"

# Use sudo for docker commands (group membership may not be active yet)
DOCKER="sudo docker"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Oracle XStream CDC Setup ==="
echo "Container: $CONTAINER_NAME"
echo "CDB: $CDB_NAME"
echo "PDB: $PDB_NAME"
echo ""

# Function to run SQL in Docker container
run_sql() {
    local user=$1
    local pass=$2
    local service=$3
    local sql_file=$4

    echo "Running: $sql_file as $user@$service"
    $DOCKER exec $CONTAINER_NAME bash -c "sqlplus -S $user/$pass@$service as sysdba @/opt/oracle/scripts/setup/$(basename $sql_file)"
}

# Copy scripts into container
echo "[1/7] Copying setup scripts to container..."
$DOCKER cp "$SCRIPT_DIR" $CONTAINER_NAME:/opt/oracle/scripts/setup/

# Step 1: Configure database for CDC
echo "[2/7] Configuring database (redo logs, archivelog, supplemental logging)..."
docker exec $CONTAINER_NAME bash -c "export ORACLE_SID=$CDB_NAME && sqlplus /nolog @/opt/oracle/scripts/setup/01_setup_database.sql"

# Step 2: Create application user
echo "[3/7] Creating ordermgmt user in PDB..."
run_sql "sys" "$SYS_PASSWORD" "$PDB_NAME" "02_create_user.sql"

# Step 3: Create schema and tables
echo "[4/7] Creating schema and data model..."
docker exec $CONTAINER_NAME sqlplus ordermgmt/$ORDERMGMT_PASSWORD@$PDB_NAME @/opt/oracle/scripts/setup/03_create_schema_datamodel.sql

# Step 4: Load initial data
echo "[5/7] Loading initial data..."
docker exec $CONTAINER_NAME sqlplus ordermgmt/$ORDERMGMT_PASSWORD@$PDB_NAME @/opt/oracle/scripts/setup/04_load_data.sql

# Step 5: Create data generator procedures
echo "[6/7] Creating data generator procedures..."
docker exec $CONTAINER_NAME sqlplus ordermgmt/$ORDERMGMT_PASSWORD@$PDB_NAME @/opt/oracle/scripts/setup/06_data_generator.sql

# Step 6: Create CDC users (common users for container database)
echo "[7/7] Creating XStream users (C##GGADMIN, C##CFLTUSER)..."
run_sql "sys" "$SYS_PASSWORD" "$CDB_NAME" "05_21c_create_user.sql"
run_sql "sys" "$SYS_PASSWORD" "$PDB_NAME" "05_21c_privs.sql"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Database Configuration:"
echo "  CDB: $CDB_NAME"
echo "  PDB: $PDB_NAME"
echo "  XStream User: C##GGADMIN / Confluent12!"
echo "  Application User: ordermgmt / kafka"
echo "  Schema: ORDERMGMT"
echo ""
echo "Next Steps:"
echo "1. Create XStream Outbound Server:"
echo "   docker exec -it $CONTAINER_NAME sqlplus C##GGADMIN/Confluent12!@$CDB_NAME"
echo "   SQL> exec dbms_xstream_adm.create_outbound(..."
echo ""
echo "2. Configure Confluent XStream CDC Connector with:"
echo "   - database.hostname: [Your Oracle VM IP]"
echo "   - database.port: 1521"
echo "   - database.user: C##GGADMIN"
echo "   - database.password: Confluent12!"
echo "   - database.dbname: $CDB_NAME"
echo "   - database.pdb.name: $PDB_NAME"
echo ""
