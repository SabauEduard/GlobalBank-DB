#!/bin/bash
# ============================================
# Oracle Cloud Connection Helper — GlobalBank DB
# ============================================

if [ -f .env ]; then
    set -a
    . .env
    set +a
fi

export PATH="${SQLCL_PATH}:$PATH"

function usage() {
    echo "GlobalBank DB — Oracle Cloud Connection Helper"
    echo ""
    echo "Usage:"
    echo "  ./connect.sh global          # Connect as GLOBAL_USER (central node)"
    echo "  ./connect.sh admin-global    # Connect as ADMIN on ATP1 (bankdb)"
    echo "  ./connect.sh bucharest       # Connect as BUCHAREST_USER (local node)"
    echo "  ./connect.sh cluj            # Connect as CLUJ_USER (local node)"
    echo "  ./connect.sh admin-local     # Connect as ADMIN on ATP2 (globalbanklocal)"
    echo "  ./connect.sh run <node> <script.sql>"
    echo ""
    echo "Nodes: global | admin-global | bucharest | cluj | admin-local"
}

function connect_global() {
    export TNS_ADMIN="${GLOBAL_WALLET_DIR}"
    sql "${GLOBAL_SCHEMA_USER}/${GLOBAL_SCHEMA_PASSWORD}@${GLOBAL_TNS_ALIAS}"
}

function connect_admin_global() {
    export TNS_ADMIN="${GLOBAL_WALLET_DIR}"
    sql "${GLOBAL_ADMIN_USER}/${GLOBAL_ADMIN_PASSWORD}@${GLOBAL_TNS_ALIAS}"
}

function connect_bucharest() {
    export TNS_ADMIN="${LOCAL_WALLET_DIR}"
    sql "${BUCHAREST_SCHEMA_USER}/${BUCHAREST_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}"
}

function connect_cluj() {
    export TNS_ADMIN="${LOCAL_WALLET_DIR}"
    sql "${CLUJ_SCHEMA_USER}/${CLUJ_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}"
}

function connect_admin_local() {
    export TNS_ADMIN="${LOCAL_WALLET_DIR}"
    # Password may contain @; use CONNECT inside /nolog session to avoid parsing issues
    printf 'CONNECT %s/"%s"@%s\n' "${LOCAL_ADMIN_USER}" "${LOCAL_ADMIN_PASSWORD}" "${LOCAL_TNS_ALIAS}" | cat - <(echo) | sql /nolog
}

function run_script() {
    local node="$1"
    local script="$2"
    case "$node" in
        global)
            export TNS_ADMIN="${GLOBAL_WALLET_DIR}"
            sql "${GLOBAL_SCHEMA_USER}/${GLOBAL_SCHEMA_PASSWORD}@${GLOBAL_TNS_ALIAS}" < "$script"
            ;;
        admin-global)
            export TNS_ADMIN="${GLOBAL_WALLET_DIR}"
            sql "${GLOBAL_ADMIN_USER}/${GLOBAL_ADMIN_PASSWORD}@${GLOBAL_TNS_ALIAS}" < "$script"
            ;;
        bucharest)
            export TNS_ADMIN="${LOCAL_WALLET_DIR}"
            sql "${BUCHAREST_SCHEMA_USER}/${BUCHAREST_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}" < "$script"
            ;;
        cluj)
            export TNS_ADMIN="${LOCAL_WALLET_DIR}"
            sql "${CLUJ_SCHEMA_USER}/${CLUJ_SCHEMA_PASSWORD}@${LOCAL_TNS_ALIAS}" < "$script"
            ;;
        admin-local)
            export TNS_ADMIN="${LOCAL_WALLET_DIR}"
            { printf 'CONNECT %s/"%s"@%s\n' "${LOCAL_ADMIN_USER}" "${LOCAL_ADMIN_PASSWORD}" "${LOCAL_TNS_ALIAS}"; cat "$script"; echo "EXIT;"; } | sql -S /nolog
            ;;
        *)
            echo "Unknown node: $node. Use: global | admin-global | bucharest | cluj | admin-local"
            exit 1
            ;;
    esac
}

case "$1" in
    global)       connect_global ;;
    admin-global) connect_admin_global ;;
    bucharest)    connect_bucharest ;;
    cluj)         connect_cluj ;;
    admin-local)  connect_admin_local ;;
    run)          run_script "$2" "$3" ;;
    *)            usage ;;
esac
