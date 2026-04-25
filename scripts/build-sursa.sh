#!/usr/bin/env bash
# T060: Concatenate all SQL source files into submission artifact.
# Usage: bash scripts/build-sursa.sh
# Output: NumeEchipa_Nume_Prenume_Sursa.txt (in project root)

set -euo pipefail

OUT="NumeEchipa_Nume_Prenume_Sursa.txt"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

write_header() {
    echo "========================================================" >> "$OUT"
    echo "FILE: $1" >> "$OUT"
    echo "========================================================" >> "$OUT"
}

> "$OUT"

cat >> "$OUT" << 'HEADER'
========================================================
GlobalBank DB — Sursa SQL Completa
Disciplina: MODBD 2025-2026
========================================================

HEADER

# Phase 0/1 — Infrastructure
for f in \
    sql/global/00-setup-global-user.sql \
    sql/bucharest/00-setup-bucharest.sql \
    sql/cluj/00-setup-cluj.sql \
    sql/global/01-db-links.sql \
    sql/global/01b-db-links-global-user.sql
do
    [ -f "$f" ] || continue
    write_header "$f"
    cat "$f" >> "$OUT"
    echo "" >> "$OUT"
done

# Phase 2 — Schema + Data
for f in \
    sql/global/02-schema-central.sql \
    sql/bucharest/01-schema-bucharest.sql \
    sql/cluj/01-schema-cluj.sql \
    sql/global/03-populate-central.sql \
    sql/bucharest/02-populate-bucharest.sql \
    sql/cluj/02-populate-cluj.sql
do
    [ -f "$f" ] || continue
    write_header "$f"
    cat "$f" >> "$OUT"
    echo "" >> "$OUT"
done

# Phase 3-7 — Distributed DB Objects
for f in \
    sql/global/04-transparency.sql \
    sql/global/05-constraints.sql \
    sql/global/06-optimization.sql \
    sql/global/07-cross-node-fk.sql \
    sql/global/08-replication.sql
do
    [ -f "$f" ] || continue
    write_header "$f"
    cat "$f" >> "$OUT"
    echo "" >> "$OUT"
done

# App source files
for f in \
    app/db.py \
    app/app.py
do
    [ -f "$f" ] || continue
    write_header "$f"
    cat "$f" >> "$OUT"
    echo "" >> "$OUT"
done

echo "Built: $ROOT/$OUT"
wc -l "$OUT"
