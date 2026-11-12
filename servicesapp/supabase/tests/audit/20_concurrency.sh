#!/usr/bin/env bash
# Auditoria 2026-11-12: corridas entre duas sessões ao mesmo tempo (duplo toque,
# dois aparelhos). Usa a BD pj_audit deixada por `bash run.sh keep`.
# Só para a BD local de teste. Nunca correr na BD viva.
set -u
export PGHOST=${PGHOST:-/var/tmp} PGPORT=${PGPORT:-5433}
P="psql -U postgres -X -q -t -A -d pj_audit"
C1=00000000-0000-0000-0000-0000000000c2   # cliente com conta ativa (C1 foi eliminada no 10_flows)
W1=00000000-0000-0000-0000-0000000000a1
W2=00000000-0000-0000-0000-0000000000a2
ST=$($P -c "select id from service_types order by sort_order limit 1")
TMP=$(mktemp -d)

as() { # as <uid> <sql>  -> corre numa transação com o papel authenticated
  printf "begin;\nset local role authenticated;\nselect set_config('request.jwt.claim.sub','%s',true);\n%s\ncommit;\n" "$1" "$2"
}
new_job() {
  $P -c "update job_requests set created_at = created_at - interval '2 hours' where client_id='$C1'" >/dev/null
  $P -c "insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
         values('$C1','$ST','Rua Corrida',38.72,-9.14,'teste de corrida','open','flexible') returning id" | head -1
}
proposal() { # proposal <job> <worker>
  as "$2" "select create_proposal('$1', 15, 1, 2, 1, null, null, null, true);" | $P 2>&1 | grep -E '^[0-9a-f-]{36}$' | tail -1
}
report() { if [ "$2" = "$3" ]; then echo "PASS | $1 | esperado=$3 obtido=$2"; else echo "FAIL | $1 | esperado=$3 obtido=$2"; fi; }

# --- RACE-01: a cliente toca em "Aceitar" em duas propostas ao mesmo tempo
J=$(new_job); PA=$(proposal $J $W1); PB=$(proposal $J $W2)
(as $C1 "select accept_proposal('$PA','$J'); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $C1 "select accept_proposal('$PB','$J');" | $P > $TMP/b.log 2>&1) &
wait
N=$($P -c "select count(*) from job_proposals where job_id='$J' and status='accepted'")
report "RACE-01 duas aceitações em paralelo: só uma proposta fica aceite" "$N" "1"
echo "      sessão B: $(grep -m1 ERROR $TMP/b.log)"

# --- RACE-02: o jardineiro retira a proposta enquanto a cliente a aceita
J=$(new_job); PA=$(proposal $J $W1)
(as $C1 "select accept_proposal('$PA','$J'); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $W1 "select withdraw_proposal('$PA','$J');" | $P > $TMP/b.log 2>&1) &
wait
S=$($P -c "select jr.status || '/' || jp.status from job_requests jr join job_proposals jp on jp.job_id = jr.id where jr.id='$J'")
report "RACE-02 aceitar e retirar ao mesmo tempo: estado coerente" "$S" "confirmed/accepted"
echo "      sessão B: $(grep -m1 ERROR $TMP/b.log)"

# --- RACE-03: duas fotos enviadas ao mesmo tempo quando já há 1 (máximo 2)
J=$(new_job)
$P -c "insert into job_photos(job_id, storage_path) values('$J','$C1/1.jpg')" >/dev/null
(as $C1 "insert into job_photos(job_id, storage_path) values('$J','$C1/2.jpg'); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $C1 "insert into job_photos(job_id, storage_path) values('$J','$C1/3.jpg');" | $P > $TMP/b.log 2>&1) &
wait
N=$($P -c "select count(*) from job_photos where job_id='$J'")
report "RACE-03 fotos em paralelo respeitam o máximo de 2" "$N" "2"

# --- RACE-04: duas propostas do mesmo jardineiro ao mesmo tempo (duplo envio)
J=$(new_job)
(as $W1 "select create_proposal('$J', 15, 1, 2, 1, null, null, null, true); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $W1 "select create_proposal('$J', 15, 1, 2, 1, null, null, null, true);" | $P > $TMP/b.log 2>&1) &
wait
N=$($P -c "select count(*) from job_proposals where job_id='$J' and worker_id='$W1'")
report "RACE-04 duplo envio de proposta cria só uma" "$N" "1"
echo "      sessão B: $(grep -m1 ERROR $TMP/b.log)"

# --- RACE-05: cliente cancela enquanto aceita (dois aparelhos)
J=$(new_job); PA=$(proposal $J $W1)
(as $C1 "select accept_proposal('$PA','$J'); select pg_sleep(1.5);" | $P > $TMP/a.log 2>&1) &
sleep 0.4
(as $C1 "select cancel_job('$J','other');" | $P > $TMP/b.log 2>&1) &
wait
S=$($P -c "select status from job_requests where id='$J'")
P_S=$($P -c "select status from job_proposals where id='$PA'")
echo "INFO | RACE-05 aceitar e depois cancelar em paralelo: pedido=$S proposta=$P_S (o cancelamento espera pela aceitação e decide sobre o estado final)"
rm -rf $TMP
