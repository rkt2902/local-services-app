# Testes da BD da auditoria (12/11/2026)

Montam uma BD Postgres 16 **local** com todas as migrations e correm os fluxos da app com RLS ligada, como a app faria (papel `authenticated` ou `anon`, `auth.uid()` de cada pessoa). Nunca apontar isto à BD viva: os scripts criam e apagam bases de dados.

Resultados e explicação em `docs/systematic-debugging-audit/` (03, 04 e 07).

## Ficheiros

- `stubs.sql`: o mínimo de `auth`, `storage`, `cron`, `vault` e `net` que o Supabase dá e o Postgres simples não tem.
- `00_lib.sql`: asserções (`audit.ok`, `audit.err`, `audit.eq`, `audit.val`) e `t_as(uid)` / `t_aal2(uid)` para mudar de pessoa.
- `10_flows.sql`: 162 asserções, um bloco por fluxo (T-PROF, T-JOB, T-DISC, T-PROP, T-HELP, T-RESCH, T-EXEC, T-RATE, T-CANC, T-EDIT, T-PLAN, T-ADM, T-NOTIF, T-PUSH, T-AG, T-FLEET, T-CARD, T-STOR, T-CRON, T-DEL).
- `30_findings.sql`: regressão dos bugs corrigidos na 0074 (F-002, F-003, F-004, F-006, F-007, F-008). Corre depois do `10_flows.sql`.
- `20_concurrency.sh`: duas sessões ao mesmo tempo (RACE-01 a RACE-05).
- `40_help_slot_race.sh` (13/11): última vaga de ajudante disputada por dois candidatos (RACE-06) e aceitar enquanto se mudam as vagas (RACE-07). Corre depois do `10_flows.sql`.
- `run.sh`: monta a BD `pj_audit` e corre o `10_flows.sql`.

## Como correr

```bash
# uma vez: Postgres 16 local na porta 5433, socket em /var/tmp, com os papéis do Supabase
initdb -D /var/tmp/pgdata -U postgres -A trust
pg_ctl -D /var/tmp/pgdata -o "-p 5433 -k /var/tmp -c listen_addresses=" start
psql -h /var/tmp -p 5433 -U postgres -c "create role authenticated nologin" \
  -c "create role anon nologin" -c "create role service_role nologin" \
  -c "grant authenticated, anon, service_role to postgres"

cd servicesapp/supabase/tests/audit
bash run.sh keep                                            # migrations + 10_flows
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 30_findings.sql
bash 20_concurrency.sh
bash 40_help_slot_race.sh
```

No `10_flows.sql` e no `20_concurrency.sh`, cada asserção descreve o comportamento **certo**. Com a 0074 passam todas (162/162 e RACE-01 a RACE-04); qualquer `FAIL` é uma regressão.

O `30_findings.sql` era a reprodução dos bugs; depois da 0074 passou a verificar as correções (19 asserções, todas `PASS`).
