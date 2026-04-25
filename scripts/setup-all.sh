#!/usr/bin/env bash
# GlobalBank DB — Master Setup Script
# Recreates the entire distributed DB from scratch.
# Usage: bash scripts/setup-all.sh
# Prerequisites: .env file in project root, wallets in place,
#                cwallet.sso uploaded to DATA_PUMP_DIR on ATP1.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Load .env ────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo "ERROR: .env not found in $ROOT"
  exit 1
fi
while IFS='=' read -r key value; do
  key="${key## }"; key="${key%% }"
  [[ -z "$key" || "$key" == \#* ]] && continue
  export "$key"="$value"
done < <(grep -v '^#' .env | grep '=')

HOME_EXPANDED="${HOME}"
GLOBAL_WALLET_DIR="${GLOBAL_WALLET_DIR/\$HOME/$HOME_EXPANDED}"
LOCAL_WALLET_DIR="${LOCAL_WALLET_DIR/\$HOME/$HOME_EXPANDED}"

SQLCL="${SQLCL_PATH:-/opt/homebrew/Caskroom/sqlcl/26.1.0.086.1709/sqlcl/bin}/sql"

# ── Helper: run SQL file ─────────────────────────────────────
run_atp1_admin() {
  echo "  [ATP1/ADMIN] $1"
  TNS_ADMIN="$GLOBAL_WALLET_DIR" WALLET_PASSWORD="$WALLET_PASSWORD" \
    "$SQLCL" -S "${GLOBAL_ADMIN_USER}/${GLOBAL_ADMIN_PASSWORD}@${GLOBAL_TNS_ALIAS}" \
    "@$ROOT/$1"
}

run_atp1_global() {
  echo "  [ATP1/GLOBAL_USER] $1"
  TNS_ADMIN="$GLOBAL_WALLET_DIR" WALLET_PASSWORD="$WALLET_PASSWORD" \
    "$SQLCL" -S "${GLOBAL_SCHEMA_USER}/${GLOBAL_SCHEMA_PASSWORD}@${GLOBAL_TNS_ALIAS}" \
    "@$ROOT/$1"
}

run_atp2_admin() {
  echo "  [ATP2/ADMIN] $1"
  TNS_ADMIN="$LOCAL_WALLET_DIR" \
    "$SQLCL" -S "${LOCAL_ADMIN_USER}/${LOCAL_ADMIN_PASSWORD}@${LOCAL_TNS_ALIAS}" \
    "@$ROOT/$1"
}

run_atp2_bucharest() {
  echo "  [ATP2/BUCHAREST_USER] $1"
  TNS_ADMIN="$LOCAL_WALLET_DIR" \
    "$SQLCL" -S "${BUCHAREST_SCHEMA_USER}/${BUCHAREST_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}" \
    "@$ROOT/$1"
}

run_atp2_cluj() {
  echo "  [ATP2/CLUJ_USER] $1"
  TNS_ADMIN="$LOCAL_WALLET_DIR" \
    "$SQLCL" -S "${CLUJ_SCHEMA_USER}/${CLUJ_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}" \
    "@$ROOT/$1"
}

# ────────────────────────────────────────────────────────────
echo ""
echo "=== Phase 0: Cleanup (optional — comment out to skip) ==="
run_atp1_admin  "sql/global/00-cleanup.sql"
run_atp2_admin  "sql/local/00-cleanup-local.sql"

echo ""
echo "=== Phase 1: Create users & DB Links ==="
run_atp1_admin  "sql/global/00-setup-global-user.sql"
run_atp2_admin  "sql/bucharest/00-setup-bucharest.sql"
run_atp2_admin  "sql/cluj/00-setup-cluj.sql"
run_atp1_global "sql/global/01-db-links.sql"
run_atp1_global "sql/global/01b-db-links-global-user.sql"

echo ""
echo "=== Phase 2: Schema creation ==="
run_atp1_global   "sql/global/02-schema-central.sql"
run_atp2_bucharest "sql/bucharest/01-schema-bucharest.sql"
run_atp2_cluj      "sql/cluj/01-schema-cluj.sql"

echo ""
echo "=== Phase 3: Seed data ==="
run_atp1_global   "sql/global/03-populate-central.sql"
run_atp2_bucharest "sql/bucharest/02-populate-bucharest.sql"
run_atp2_cluj      "sql/cluj/02-populate-cluj.sql"

echo ""
echo "=== Phase 4: Distributed DB objects (views, triggers, indexes) ==="
run_atp1_global "sql/global/04-transparency.sql"
run_atp1_global "sql/global/05-constraints.sql"
run_atp1_global "sql/global/06-optimization.sql"
run_atp1_global "sql/global/07-cross-node-fk.sql"
run_atp1_global "sql/global/08-replication.sql"

echo ""
echo "=== Setup complete! ==="
echo "  Verify: python3 scripts/upload-wallet-to-datapump.py  (if DB Links broken)"
echo "  Start app: python3 app/app.py"
