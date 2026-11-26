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
- `50_admin_support.sql` (13/11, 0078): painel de suporte. Volta a correr a 0078 para provar o preenchimento dos pedidos antigos, eventos novos (cliente, sistema), e cada RPC nova recusada sem sessão, a utilizador normal e a admin sem segundo fator (51 asserções). Corre depois do `10_flows.sql`.
- `60_admin_resolve.sql` (16/11, 0079): painel de suporte, fase B. Casos com prazos em dias úteis, reportes, cancelar/reabrir/corrigir estado pelo suporte, ocultar e repor avaliações e fotos, notas internas e registo. Cada RPC nova recusada sem sessão, a utilizador normal e a admin sem segundo fator; cada ação com motivo, nota, registo e aviso (132 asserções). Corre depois do `10_flows.sql`.
- `70_admin_accounts.sql` (16/11, 0080): painel de suporte, fase C. Suspender e reativar (pedidos abertos fecham, propostas saem, trabalhos aceites ficam), conta suspensa não age mas pode eliminar-se, encerramento com aviso de 30 dias e cron, exportar dados, eliminar a pedido com a lista de ficheiros, fotos de perfil e portefólio, reenviar código, mapa. Cada RPC nova recusada sem sessão, a utilizador normal e a admin sem segundo fator (109 asserções). Corre depois do `10_flows.sql`. O `T-SUP-42` do 50 passa a abrir exceção para `admin_export_user_data` (a Agenda vai na exportação).
- `80_admin_growth.sql` (16/11, 0081): painel, fase 3. Funil (por diferenças, antes e depois de criar contas), exportar CSV sem telefone, email nem morada, avisos a grupos (contagem, filtros por plano, serviço e localidade, contagem que mudou, repetido em 24 h, suspensos de fora), histórico e registo. Cada RPC nova recusada sem sessão, a utilizador normal e a admin sem segundo fator (48 asserções). Corre depois do `10_flows.sql`. No fim volta a correr a 0081 e depois a 0082 (a 0081 tira a versão do `admin_send_notice` da 0082).
- `90_admin_partners_zones.sql` (16/11, 0082): cartões frota no painel (só o mais recente, aprovar, recusar com motivo, retirar, aviso e mensagem ao jardineiro, conta suspensa não pede), parceiros (validação de todos os campos, jardineiros e pedidos perto, apagar devolve a foto, `get_partners` por plano: o Pro+ vê os códigos, o Grátis vê só o que há, anónimo e cliente recusados; policies e limites do bucket `partner-images`; distância à base, uso contado uma vez por hora e só de jardineiros, alertas de validade, avisos de parceiro e os lidos no histórico) e zonas do mapa (pedidos sem resposta, mediana da 1.ª proposta, quem cobre, suspensos e gasolineiras acabadas de fora), com contas nos Açores. Cada RPC nova recusada sem sessão, a utilizador normal e a admin sem segundo fator (90 asserções). Corre depois do `10_flows.sql`.
- 17/11 (0083): os cenários que voltam a correr a sua migration (50, 60, 70, 80, 90) correm a `0083` logo a seguir, como na ordem real; sem isso voltavam os textos antigos. As frases esperadas passaram ao tratamento formal e a "profissional".
- `95_fuel_usage.sql` (26/11, 0084): consumo de combustível (gravar, ler, recusas por tipo repetido, inexistente, desativado e litros fora do intervalo, cliente e anónimo recusados) e `admin_partner_stats` (registados, ativos, Pro, respostas, litros por tipo e por distrito, trabalhos por mês, suspensos de fora, recusas sem segundo fator) (35 asserções). Corre depois do `10_flows.sql`.
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
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 50_admin_support.sql  # depois de um run.sh keep novo
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 60_admin_resolve.sql  # idem
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 70_admin_accounts.sql  # idem
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 80_admin_growth.sql  # idem
psql -h /var/tmp -p 5433 -U postgres -d pj_audit -f 90_admin_partners_zones.sql  # idem
```

No `10_flows.sql` e no `20_concurrency.sh`, cada asserção descreve o comportamento **certo**. Com a 0074 passam todas (162/162 e RACE-01 a RACE-04); qualquer `FAIL` é uma regressão.

O `30_findings.sql` era a reprodução dos bugs; depois da 0074 passou a verificar as correções (19 asserções, todas `PASS`).
