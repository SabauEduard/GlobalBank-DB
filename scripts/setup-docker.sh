#!/usr/bin/env bash
# GlobalBank DB — Docker Setup Script
# Sets up all 3 Oracle XE containers after `docker compose up -d`.
#
# Prerequisites:
#   1. docker compose -f docker/docker-compose.yml up -d
#   2. All 3 containers STATUS = healthy (watch with: docker ps)
#
# Usage: bash scripts/setup-docker.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SQLCL="${SQLCL_PATH:-/opt/homebrew/Caskroom/sqlcl/26.1.0.086.1709/sqlcl/bin}/sql"
ORACLE_PWD="Admin#DB1"
GLOBAL_USER="GLOBAL_USER"
GLOBAL_PASS="SecurePass123!"
BUCHAREST_USER="BUCHAREST_USER"
BUCHAREST_PASS="SecurePass123!"
CLUJ_USER="CLUJ_USER"
CLUJ_PASS="SecurePass123!"

# PDB service name is 'freepdb1' for all 3 gvenzl/oracle-xe containers
CENTRAL_DSN="//localhost:1521/freepdb1"
BUCHAREST_DSN="//localhost:1522/freepdb1"
CLUJ_DSN="//localhost:1523/freepdb1"

# ── Helpers ──────────────────────────────────────────────────
run_central_sys() {
  echo "  [CENTRAL/SYS] $1"
  "$SQLCL" -S "sys/${ORACLE_PWD}@${CENTRAL_DSN} as sysdba" "@$ROOT/$1"
}

run_central_global() {
  echo "  [CENTRAL/GLOBAL_USER] $1"
  "$SQLCL" -S "${GLOBAL_USER}/${GLOBAL_PASS}@${CENTRAL_DSN}" "@$ROOT/$1"
}

run_bucharest_sys() {
  echo "  [BUCHAREST/SYS] $1"
  "$SQLCL" -S "sys/${ORACLE_PWD}@${BUCHAREST_DSN} as sysdba" "@$ROOT/$1"
}

run_bucharest_user() {
  echo "  [BUCHAREST/BUCHAREST_USER] $1"
  "$SQLCL" -S "${BUCHAREST_USER}/${BUCHAREST_PASS}@${BUCHAREST_DSN}" "@$ROOT/$1"
}

run_cluj_sys() {
  echo "  [CLUJ/SYS] $1"
  "$SQLCL" -S "sys/${ORACLE_PWD}@${CLUJ_DSN} as sysdba" "@$ROOT/$1"
}

run_cluj_user() {
  echo "  [CLUJ/CLUJ_USER] $1"
  "$SQLCL" -S "${CLUJ_USER}/${CLUJ_PASS}@${CLUJ_DSN}" "@$ROOT/$1"
}

# ── Wait for a container to be ready ─────────────────────────
wait_for_db() {
  local label=$1 dsn=$2
  echo "  Waiting for $label ..."
  local retries=30
  until "$SQLCL" -S "sys/${ORACLE_PWD}@${dsn} as sysdba" \
      <<< "SELECT 1 FROM DUAL;" 2>/dev/null | grep -qE "^\s+1\s*$"; do
    retries=$((retries - 1))
    if [ $retries -le 0 ]; then
      echo "ERROR: $label did not become ready in time. Check: docker ps"
      exit 1
    fi
    sleep 10
  done
  echo "  $label is ready."
}

# ────────────────────────────────────────────────────────────
echo ""
echo "=== Waiting for all 3 Oracle XE containers ==="
wait_for_db "central (port 1521)"   "$CENTRAL_DSN"
wait_for_db "bucharest (port 1522)" "$BUCHAREST_DSN"
wait_for_db "cluj (port 1523)"      "$CLUJ_DSN"

echo ""
echo "=== Phase 0: Cleanup ==="
run_central_sys   "sql/docker/global/00-cleanup.sql"
run_bucharest_sys "sql/docker/local/00-cleanup-local.sql"
run_cluj_sys      "sql/docker/local/00-cleanup-cluj.sql"

echo ""
echo "=== Phase 1: Create users ==="
run_central_sys   "sql/docker/global/00-setup-global-user.sql"
run_bucharest_sys "sql/bucharest/00-setup-bucharest.sql"
run_cluj_sys      "sql/cluj/00-setup-cluj.sql"

echo ""
echo "=== Phase 2: DB Links (central → bucharest + cluj) ==="
run_central_global "sql/docker/global/01-db-links.sql"

echo ""
echo "=== Phase 3: Schema creation ==="
run_central_global  "sql/global/02-schema-central.sql"
run_bucharest_user  "sql/bucharest/01-schema-bucharest.sql"
run_cluj_user       "sql/cluj/01-schema-cluj.sql"

echo ""
echo "=== Phase 4: Seed data ==="
run_central_global  "sql/global/03-populate-central.sql"
run_bucharest_user  "sql/bucharest/02-populate-bucharest.sql"
run_cluj_user       "sql/cluj/02-populate-cluj.sql"

echo ""
echo "=== Phase 5: Views, triggers, indexes, replication ==="
run_central_global "sql/global/04-transparency.sql"
run_central_global "sql/global/05-constraints.sql"
run_central_global "sql/global/06-optimization.sql"
run_central_global "sql/global/07-cross-node-fk.sql"
run_central_global "sql/global/08-replication.sql"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "  Central   (GLOBAL_USER):    localhost:1521/freepdb1  [globalbank-central]"
echo "  Bucharest (BUCHAREST_USER): localhost:1522/freepdb1  [globalbank-bucharest]"
echo "  Cluj      (CLUJ_USER):      localhost:1523/freepdb1  [globalbank-cluj]"
echo ""
echo "  Next: cp .env.docker .env && python3 app/app.py"
