-- ==============================================================
-- supabase/migrations/0027_doc_audit_fixes.sql
-- Batch of 5 confirmed-missing items from the 2026-06-30
-- verification pass. All confirmed against live DB before writing:
--   P-FA5: live query SELECT indexname FROM pg_indexes WHERE ... → 0 rows
--   P-FA6: live query SELECT column_default FROM information_schema.columns → 'accepted'
--   P-FA1: pg_get_functiondef shows function exists in live DB but absent
--          from all 26 migrations; policy also absent from all migrations.
--   P-67-2: worker_repository.dart still has two-call _syncServiceTypes
--   M5:    grep of all migrations confirmed no broad client SELECT policy
--
-- NOTE: get_jobs_in_radius old 3-arg overload was ALREADY cleaned in
-- migration 0011 (DROP FUNCTION IF EXISTS get_jobs_in_radius(numeric,
-- numeric, integer)) — confirmed present in 0011; no action needed here.
--
-- IMPORTANT: written but NOT applied to the live DB.
-- Apply manually via the Supabase SQL Editor.
-- ==============================================================


-- ── 1a. P-FA1 — client_has_confirmed_job_with_worker + RLS policy ─────────────
--
-- Function confirmed present in live DB (pg_get_functiondef 2026-06-26)
-- with body covering confirmed + awaiting_confirmation + completed.
-- Absent from all 26 previous migrations — BD not reproducible without it.
--
-- worker_profiles PK is `profile_id` (confirmed: 0001_baseline.sql line 35).
-- Policy uses profile_id to identify the worker being viewed.

CREATE OR REPLACE FUNCTION client_has_confirmed_job_with_worker(p_worker_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   job_requests  jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.client_id  = auth.uid()
      AND  jp.worker_id  = p_worker_id
      AND  jr.status IN ('confirmed', 'awaiting_confirmation', 'completed')
  );
$$;

DROP POLICY IF EXISTS "Cliente ve perfil de worker com job confirmado" ON worker_profiles;

CREATE POLICY "Cliente ve perfil de worker com job confirmado"
  ON worker_profiles FOR SELECT TO authenticated
  USING (client_has_confirmed_job_with_worker(profile_id));


-- ── 1b. P-67-2 — atomic worker_service_types sync RPC ────────────────────────
--
-- worker_repository.dart's _syncServiceTypes does DELETE + INSERT as two
-- separate PostgREST calls without a transaction. If INSERT fails after
-- DELETE succeeds, worker ends up with ZERO service types permanently.
-- PostgREST REST API does not support multi-statement transactions;
-- the only correct fix is a SECURITY DEFINER RPC.
--
-- Dart side: replace _syncServiceTypes with a single rpc() call to this
-- function (see worker_repository.dart change in same commit).

CREATE OR REPLACE FUNCTION sync_worker_service_types(
  p_worker_id        uuid,
  p_service_type_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM worker_service_types WHERE worker_id = p_worker_id;
  IF array_length(p_service_type_ids, 1) IS NOT NULL
     AND array_length(p_service_type_ids, 1) > 0 THEN
    INSERT INTO worker_service_types (worker_id, service_type_id)
    SELECT p_worker_id, unnest(p_service_type_ids);
  END IF;
END;
$$;


-- ── 1c. P-FA5 — missing indexes on help_requests and help_acceptances ─────────
--
-- Live query (2026-06-30) confirmed zero rows for all three index names
-- in pg_indexes WHERE tablename IN ('help_requests','help_acceptances').
-- help_acceptances.worker_id is most urgent: evaluated by RLS on every
-- query to the table, not just explicit app queries.
-- Notification index added here alongside the help table indexes since
-- it targets the same pattern (filter + sort together for ordered lists).

CREATE INDEX IF NOT EXISTS idx_help_requests_job_id
  ON help_requests (job_id);

CREATE INDEX IF NOT EXISTS idx_help_requests_proposal_id
  ON help_requests (proposal_id);

CREATE INDEX IF NOT EXISTS idx_help_acceptances_worker_id
  ON help_acceptances (worker_id);

-- M3 Fases 4-5 — notifications ordered query index (batched here with P-FA5
-- as it is the same type of fix: missing index confirmed absent from all
-- previous migrations).
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_id, created_at DESC);


-- ── 1d. P-FA6 — help_acceptances.status DEFAULT 'accepted' → 'pending' ────────
--
-- Live query (2026-06-30): SELECT column_default FROM information_schema.columns
-- WHERE table_name='help_acceptances' AND column_name='status' → 'accepted'::text
-- This was set interactively on the live DB before migrations tracked defaults.
-- The RLS INSERT WITH CHECK (status = 'pending') blocks any INSERT that omits
-- status (gets default 'accepted'), silently returning count=0 with no error.

ALTER TABLE help_acceptances ALTER COLUMN status SET DEFAULT 'pending';


-- ── 1e. M5 — broader client SELECT policy for help_requests ──────────────────
--
-- Migration 0003 created "Cliente vê help requests pendentes de aprovação"
-- (only covers pending_approval rows). Any future "ver equipa" screen would
-- silently return empty. Migration 0026 added the worker-principal policy;
-- this completes the client side.
--
-- The flow of approve_help_request (RPC) already validates client ownership,
-- so widening the SELECT policy does not change RPC behaviour.

DROP POLICY IF EXISTS "Cliente vê help requests pendentes de aprovação" ON help_requests;

CREATE POLICY "Cliente vê help requests dos seus jobs"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id        = help_requests.job_id
        AND  client_id = auth.uid()
    )
  );
6