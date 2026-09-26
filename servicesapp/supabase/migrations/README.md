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

**PENDENTE — `0038_ratings_mine_received_given.sql`** — NÃO aplicada ainda.
Adiciona `get_my_ratings_received()`/`get_my_ratings_given()` (RPCs
SECURITY DEFINER, sem parâmetro de identidade) para o ecrã "As minhas
avaliações". Aplicar manualmente via SQL Editor antes de usar
`my_ratings_screen.dart`.

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
