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

**PENDENTE — `0041_push_notifications.sql`** — NÃO aplicada ainda.
Tabela `device_tokens`, RPCs `register_device_token`/`unregister_device_token`
e trigger em `notifications` que chama a Edge Function `send-push`. Antes de
aplicar: ativar `pg_net` e criar os segredos no Vault — passos completos em
`docs/push_notifications.md`.

**PENDENTE — `0042_security_hardening.sql`** — NÃO aplicada ainda. Corrige as
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

**PENDENTE — `0043_job_location_privacy.sql`** — NÃO aplicada ainda. Aplicar
DEPOIS da 0042 e junto com a app nova (que lê o detalhe do pedido pela RPC
`get_job_by_id`). Até haver proposta aceite, o jardineiro vê só a localidade
(`job_requests.location_area`, coluna nova) e coordenadas arredondadas a ~1 km.
A morada exata fica para o cliente, o worker aceite e os ajudantes aceites.
Os workers deixam de ler `job_requests` diretamente (exceto o aceite).

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
