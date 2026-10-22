# supabase/migrations

## Active migrations

| File | Description |
|------|-------------|
| `0001_consolidated_baseline.sql` | Complete live DB state as of 2026-07-09. Apply to a fresh Supabase project to reproduce the schema exactly. |

## Archive

`archive/` contains the original 31 incremental migrations (0001_baseline … 0032_audit_fixes). They are kept for historical reference and git blame context. **Do not apply them** — `0001_consolidated_baseline.sql` supersedes them.

## How to apply

1. Create a fresh Supabase project.
2. Enable the `pg_cron` extension (Database → Extensions → pg_cron).
3. Create storage buckets `avatars` and `job-photos` (Storage → New Bucket, set Public).
4. Run `0001_consolidated_baseline.sql` via the Supabase SQL Editor.
5. Verify: `SELECT COUNT(*) FROM service_types;` should return 3 rows.
6. After applying, reload the PostgREST schema cache:
   `NOTIFY pgrst, 'reload schema';`

## Live DB delta

**UPDATE 2026-09-09:** `archive/0032_audit_fixes.sql` has been applied to the
live DB, confirmed by the user. The live DB now has the post-0032 FK targets
for `job_proposals.worker_id` and `help_acceptances.worker_id` (pointing to
`profiles(id)`), matching `0001_consolidated_baseline.sql`. Migrations
0033–0037 (worker public card, helper discovery payment/message, unified
worker job board RPC, profiles cascade + confirm backfill, worker fleet
cards) have also been applied — see each file's own header.

No known delta between the live DB and `0001_consolidated_baseline.sql` as
of 2026-09-09.

**UPDATE 2026-10-16:** confirmado via dump real da BD viva (`supabase db
dump`, projeto `twpflvcoyeiysnychkom`) que `0038_ratings_mine_received_given.sql`,
`0039_help_request_principal_avatar.sql` e `0040_cross_party_identity_rpcs.sql`
**estão todas aplicadas** — as 7 funções que introduzem
(`get_my_ratings_received`, `get_my_ratings_given`, `get_help_requests_in_radius`
no shape pós-0039, `get_open_job_client_identity`, `get_pending_proposals_for_job`,
`get_candidates_for_help_request`, `get_ratings_with_rater_identity`) existem
todas na BD viva com a assinatura esperada. As 37 funções, 14 tabelas e 3 views
da BD viva coincidem exatamente com a soma de `0001_consolidated_baseline.sql` +
0033–0040, sem funções/tabelas extra nem em falta.

**Drift encontrado (cosmético, não aplicado por nenhuma migration deste repo):**
o trigger em `job_requests` chama-se `on_job_created` na BD viva, mas
`0001_consolidated_baseline.sql` define-o como `trigger_notify_workers_new_job`
(mesma função `notify_workers_new_job()`, mesmo comportamento). Foi provavelmente
renomeado manualmente no Supabase Studio em algum momento. Não requer migration
nova — é só nome, sem impacto funcional — mas ficou registado para não
confundir quem for ler o nome do trigger na dashboard.

**APLICADA — `0041_push_notifications.sql`** — aplicada a 2026-10-16.
Tabela `device_tokens`, RPCs `register_device_token`/`unregister_device_token`
e trigger em `notifications` que chama a Edge Function `send-push`. Antes de
aplicar: ativar `pg_net` e criar os segredos no Vault — passos completos em
`docs/push_notifications.md`.

**APLICADA — `0042_security_hardening.sql`** — aplicada a 2026-10-16. Corrige as
falhas do review de 2026-10-16: `cancel_job` e `reject_proposal` sem
autorização, `create_user_profile` aberta a anon (apagada), escritas diretas
que saltavam as RPCs (`job_proposals` INSERT/UPDATE, `job_requests` UPDATE,
`ratings` INSERT, `help_acceptances` UPDATE), WITH CHECK apertado em
`job_requests`, `help_requests`, `help_acceptances` e `worker_fleet_cards`,
limites nos buckets, REVOKE de anon nas funções, `acos` partido em
`get_jobs_in_radius`, limpeza de notificações e 7 índices. Não muda nenhuma
assinatura de RPC, pode ser aplicada antes ou depois da app nova. Pode ser
aplicada antes da 0041 (o REVOKE do trigger de push é condicional).
Verificação no fim do próprio ficheiro.

**APLICADA — `0043_job_location_privacy.sql`** — aplicada a 2026-10-16. Aplicar
DEPOIS da 0042 e junto com a app nova (que lê o detalhe do pedido pela RPC
`get_job_by_id`). Até haver proposta aceite, o jardineiro vê só a localidade
(`job_requests.location_area`, coluna nova) e coordenadas arredondadas a ~1 km.
A morada exata fica para o cliente, o worker aceite e os ajudantes aceites.
Os workers deixam de ler `job_requests` diretamente (exceto o aceite).

**APLICADA — `0044_rpc_identity_and_policy_perf.sql`** — aplicada (confirmado pelo Henrique a 2026-10-17).
Aplicar junto com a app nova: `create_proposal`, `get_jobs_in_radius` e
`sync_worker_service_types` deixam de receber `p_worker_id` (DROP das versões
antigas), por isso a app antiga deixa de conseguir enviar propostas, ver
oportunidades e guardar serviços. Também troca `auth.uid()` por
`(SELECT auth.uid())` nas policies do public (exceto `job_requests`, que daria
recursão), pré-filtra o raio por uma caixa de lat/lng com um índice parcial, e
no fim verifica que nenhuma policy ficou com recursão; se ficar, falha inteira
e não aplica nada.

**APLICADA — `0045_service_catalog.sql`** — aplicada (confirmado a 2026-10-17). Aplicar ANTES
da app nova (a app nova lê `service_categories.sort_order`). Junta as
categorias Agricultura e Floresta, 33 tipos de serviço no total, e as colunas
`service_types.icon` e `sort_order`. Os 3 tipos que já existiam mantêm o id e
o nome. Um ícone novo na BD tem de ser acrescentado ao mapa de
`lib/core/widgets/service_icon.dart`, senão aparece o ícone genérico.

**APLICADA — `0046_job_day_rules.sql`** — aplicada (confirmado a 2026-10-17). Aplicar DEPOIS
da 0044 (redefine `get_jobs_in_radius` de 3 parâmetros). Concluir só a partir
do dia, foto de conclusão, expiração de pedidos com data passada, lembretes
(cron novo `job-reminders`). Compatível com a app antiga (`p_photo_path` tem
DEFAULT).

**Regra a partir da 0042:** cada função nova faz
`REVOKE EXECUTE ... FROM PUBLIC, anon` e `GRANT EXECUTE ... TO authenticated`
(o Postgres dá EXECUTE a PUBLIC por defeito).

**Nota sobre a baseline:** `0001_consolidated_baseline.sql` não corre de uma
vez num projeto vazio: 4 policies (linhas 384, 444, 572 e 587) usam funções
helper que só são criadas mais abaixo, na secção 7. Num projeto novo, correr
o ficheiro, e depois correr de novo só essas 4 policies.

## Sources used for consolidation

- `supabase/snapshot_tables.csv` — sections 1–6 (columns, constraints,
  indexes, RLS policies, functions, views), taken 2026-07-09.
- `archive/0001_baseline.sql` — service_categories, job_photos, functions
  not in snapshot query (reject_proposal, withdraw_proposal,
  confirm_job_completion, worker_has_proposal_for_job, notify_workers_new_job),
  storage bucket creation, seed data.
- `archive/0032_audit_fixes.sql` — corrected FK targets, auth-checked RPCs
  (accept_proposal, create_proposal, sync_worker_service_types), role-change
  trigger, missing indexes, profiles SELECT policies.

**Note:** `snapshot_a.csv` and `snapshot_b.csv` do not exist in this repo.
All snapshot data came from a single `snapshot_tables.csv` file.

**`0048_worker_helper_flow_fixes.sql`: criada, NÃO aplicada** (aplicar depois da
0047). Correções aos fluxos dos ajudantes, avisos novos e histórico na aba Trabalhos.
Ver o cabeçalho do ficheiro.

**`0052_job_start_flow.sql`: criada, NÃO aplicada** (aplicar depois da 0049 e da 0051).
"Iniciar trabalho" (`start_job`, a partir de 1h antes da hora), fotos de antes e depois
(`before_photo_paths`/`after_photo_paths`, até 3), `started_at`, `mark_job_done` com
`p_photo_paths text[]` e a exigir início, confirmação automática em 48h com lembrete às
24h (cron de hora a hora), aviso novo `job_started`.

**`0053_worker_jobs_board_cards.sql`: criada, NÃO aplicada** (aplicar depois da 0048 e
da 0052). `get_worker_job_board` passa a devolver o serviço, a localidade, quando foi
iniciado e marcado como feito, quem cancelou (dois booleanos) e a data da última
alteração, para os cartões de "Os meus trabalhos" (design A2).

**`0057_direct_requests.sql`: criada, NÃO aplicada** (aplicar depois da 0056). Pedido
direto "Pedir de novo ao mesmo jardineiro" (design A5): colunas `direct_*` em
`job_requests`, reserva de 24h só para o jardineiro escolhido, recusa, "Mostrar já a
todos", cron `expire-direct-job-requests` de 5 em 5 minutos, avisos `direct_job_request` e
`direct_request_released`, e as RPCs de leitura do cartão, de "Os teus jardineiros" e do
histórico do jardineiro. Pode correr-se mais do que uma vez. **Próxima migration: `0058`.**

**`0051_worker_showcase.sql`: criada, NÃO aplicada** (aplicar depois da 0049).
Destaques (`highlights text[]`) e redes sociais (`social_links jsonb`) em
`worker_profiles`, com CHECK na BD (só `https://`), e as duas colunas no fim de
`worker_public_card`. A 0050 ficou reservada para outra thread.

**`0049_pending_decisions.sql`: criada, NÃO aplicada** (aplicar depois da 0048).
Eliminar conta, editar pedido, gestão da equipa, avisos com o trabalho e a data, avisos
aos ajudantes, remarcar trabalho atrasado, fecho ao fim de 14 dias sem escolha, report
trava a confirmação automática, avaliação do cliente deixa de ser copiada para os
ajudantes. **Próxima migration: `0050`.**

**`0047_candidate_message.sql`: criada, NÃO aplicada.** Aplicar no SQL Editor (pode
ser antes ou depois da app nova). Todas as anteriores estão aplicadas na BD viva
(2026-10-17). **Próxima migration: `0048`.**
