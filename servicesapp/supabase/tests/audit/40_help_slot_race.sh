#!/usr/bin/env bash
# Auditoria 2026-11-13: última vaga de ajudante disputada em paralelo (RACE-06)
# e aceitar enquanto se mudam as vagas (RACE-07). Usa a BD pj_audit deixada por
# `bash run.sh keep`. Só para a BD local de teste. Nunca correr na BD viva.
set -u
export PGHOST=${PGHOST:-/var/tmp} PGPORT=${PGPORT:-5433}
P="psql -U postgres -X -q -t -A -d pj_audit"
C=00000000-0000-0000-0000-0000000000c2; W1=00000000-0000-0000-0000-0000000000a1
W2=00000000-0000-0000-0000-0000000000a2; W3=00000000-0000-0000-0000-0000000000a3; WAD=00000000-0000-0000-0000-0000000000ad
# W1 passa a Pro para as propostas de teste não baterem no limite do Grátis.
$P -c "insert into worker_plans(worker_id,tier) values('$W1','pro') on conflict (worker_id) do update set tier='pro', ends_at=null" >/dev/null
ST=$($P -c "select id from service_types order by sort_order limit 1"); TMP=$(mktemp -d)
as() { printf "begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','%s',true);\n%s\ncommit;\n" "$1" "$2"; }
report() { if [ "$2" = "$3" ]; then echo "PASS | $1 | esperado=$3 obtido=$2"; else echo "FAIL | $1 | esperado=$3 obtido=$2"; fi; }
setup() { # cria trabalho confirmado de W1 com pedido de ajuda aberto (1 vaga) e 2 candidaturas
  $P -c "update job_requests set created_at = created_at - interval '3 hours' where client_id='$C'" >/dev/null
  J=$($P -c "insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,preferred_date)
      values('$C','$ST','Rua Equipa',38.72,-9.14,'equipa','open','fixed',today_pt()+5) returning id" | head -1)
  PR=$(as $W1 "select create_proposal('$J', 15, 2, 4, 2, null, today_pt()+5, '09:00');" | $P 2>&1 | grep -E "^[0-9a-f-]{36}$" | grep -v "^00000000-0000" | tail -1)
  as $C "select accept_proposal('$PR','$J');" | $P >/dev/null 2>&1
  HR=$($P -c "select id from help_requests where job_id='$J'" | head -1)
  if [ -z "$HR" ]; then HR=$($P -c "insert into help_requests(job_id,proposal_id,slots_needed,status,created_post_confirmation) values('$J','$PR',1,'open',true) returning id" | head -1); fi
  $P -c "update help_requests set status='open', slots_needed=1 where id='$HR'" >/dev/null
  A2=$(as $W2 "select apply_to_help_request('$HR', false, null);" | $P 2>&1 | grep -E "^[0-9a-f-]{36}$" | grep -v "^00000000-0000" | tail -1)
  A3=$(as $W3 "select apply_to_help_request('$HR', false, null);" | $P 2>&1 | grep -E "^[0-9a-f-]{36}$" | grep -v "^00000000-0000" | tail -1)
  [ -z "$A3" ] && A3=$(as $WAD "select apply_to_help_request('$HR', false, null);" | $P 2>&1 | grep -E "^[0-9a-f-]{36}$" | grep -v "^00000000-0000" | tail -1)
}
setup
echo "setup: job=$J hr=$HR a2=$A2 a3=$A3"
(as $W1 "select accept_help_candidate('$A2', 20); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $W1 "select accept_help_candidate('$A3', 20);" | $P > $TMP/b.log 2>&1) &
wait
N=$($P -c "select count(*) from help_acceptances where help_request_id='$HR' and status='accepted'")
S=$($P -c "select status from help_requests where id='$HR'")
report "RACE-06 dois candidatos aceites em paralelo para a última vaga: só um entra" "$N/$S" "1/filled"
echo "      sessão B: $(grep -m1 ERROR $TMP/b.log)"
setup
echo "setup: job=$J hr=$HR a2=$A2 a3=$A3"
(as $W1 "select accept_help_candidate('$A2', 20); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $W1 "select update_help_request_slots('$HR', 2);" | $P > $TMP/b.log 2>&1) &
wait
N=$($P -c "select count(*) from help_acceptances where help_request_id='$HR' and status='accepted'")
S=$($P -c "select status||'/'||slots_needed from help_requests where id='$HR'")
echo "INFO | RACE-07 aceitar e aumentar vagas ao mesmo tempo: aceites=$N pedido=$S | B: $(grep -m1 ERROR $TMP/b.log)"
