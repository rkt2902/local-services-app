#!/usr/bin/env bash
# Auditoria 2026-11-12: monta uma BD Postgres 16 LOCAL com todas as migrations
# (0001 em diante) e corre os cenários com asserções. Nunca aponta à BD viva.
#
# Requisitos: Postgres 16 local a correr, com os papéis authenticated, anon e
# service_role criados (ver README.md). Variáveis: PGHOST, PGPORT (por omissão
# /var/tmp e 5433), utilizador postgres.
#
# Uso:  bash run.sh            -> cria a BD "pj_audit", corre 10_flows.sql
#       bash run.sh keep       -> não apaga a BD no fim (para investigar)
set -u
H=$(cd "$(dirname "$0")" && pwd)
MIG="$H/../../migrations"
export PGHOST=${PGHOST:-/var/tmp} PGPORT=${PGPORT:-5433}
P="psql -U postgres -q -X"
DB=pj_audit

$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -v ON_ERROR_STOP=1 -f "$H/stubs.sql" >/dev/null || { echo "stubs falharam"; exit 1; }
fail=0
for f in $(ls "$MIG"/0*.sql | sort); do
  # pg_net não existe localmente; o stub net.http_post substitui-o.
  out=$(sed 's/^CREATE EXTENSION IF NOT EXISTS pg_net.*$//' "$f" | $P -d $DB -v ON_ERROR_STOP=1 2>&1 | grep -E "ERROR|FATAL")
  if [ -n "$out" ]; then echo "MIGRATION FALHOU: $(basename $f): $out"; fail=1; fi
done
[ $fail = 0 ] && echo "migrations: $(ls "$MIG"/0*.sql | wc -l) ficheiros aplicados sem erro"
$P -d $DB -v ON_ERROR_STOP=1 -f "$H/00_lib.sql" >/dev/null
$P -d $DB -t -A -f "$H/10_flows.sql" 2>&1 | grep -E "^(PASS|FAIL|TOTAL)|ERROR" 
[ "${1:-}" = keep ] || $P -d postgres -c "drop database $DB" >/dev/null
