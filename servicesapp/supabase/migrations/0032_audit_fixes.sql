-- ==============================================================
-- supabase/migrations/0032_audit_fixes.sql
-- Security and correctness fixes from the 2026-07-09 audit.
--
-- Priority 1 — CRITICAL: Fix broken FK constraints.
--   job_proposals_worker_id_fkey and help_acceptances_worker_id_fkey
--   currently point to worker_profiles(profile_id). Migration 0031
--   was a no-op because both constraints already existed (pointing to
--   the wrong table) and the DO $$...IF NOT EXISTS check found them.
--   Fix: DROP both constraints and re-add pointing to profiles(id).
--
-- Priority 2 — CRITICAL: Add auth.uid() guards to three RPCs.
--   accept_proposal, create_proposal, sync_worker_service_types all
--   accepted caller-supplied identity without verification, allowing
--   any authenticated user to act on behalf of another.
--
-- Priority 3 — HIGH: Prevent profiles.role escalation.
--   The UPDATE policy had no WITH_CHECK. A user could PATCH their own
--   profile with {"role":"worker"} and the DB would accept it. Fixed
--   via a BEFORE UPDATE trigger (WITH CHECK cannot reference OLD.role).
--
-- Priority 4 — MEDIUM: Six indexes from 0001_baseline missing from DB.
--   CREATE TABLE IF NOT EXISTS silently skips the table body when the
--   table already exists, including all inline CREATE INDEX statements.
--
-- Priority 5 — LOW: Capture live DB profiles SELECT policies.
--   Three granular SELECT policies replaced the broad USING(true) policy
--   from 0001_baseline via interactive SQL Editor sessions. Absent from
--   all previous migrations — DB not reproducible without them.
--
-- NOT APPLIED — apply manually via Supabase SQL Editor.
-- ==============================================================


-- ══════════════════════════════════════════════════════════════
-- PRIORITY 1 — Fix broken FK constraints
-- ══════════════════════════════════════════════════════════════
--
-- Root cause: migration 0031 used IF NOT EXISTS checks, but both
-- constraints already existed pointing to worker_profiles(profile_id),
-- so the check found them and skipped the ADD CONSTRAINT — a silent no-op.
--
-- All existing rows are data-consistent: job_proposals.worker_id and
-- help_acceptances.worker_id are worker UUIDs which equal profiles.id
-- (they are the same values via the worker_profiles.profile_id chain).
-- The ADD CONSTRAINT will succeed without any data migration.
--
-- CASCADE semantics after the change:
--   Deleting a profile cascades directly to job_proposals and
--   help_acceptances (new direct FK), and also to worker_profiles
--   (existing FK). The end result — deleting a user removes all their
--   proposals and acceptances — is unchanged.
--
-- PostgREST impact: after applying this migration, notify PostgREST to
-- reload its schema cache so the new FK relationships are discoverable:
--   NOTIFY pgrst, 'reload schema';
-- or trigger a schema reload from the Supabase dashboard.
-- The Dart embed-join hints in proposal_repository.dart and
-- help_request_repository.dart already use the correct FK names and will
-- work immediately once the schema cache is refreshed.

ALTER TABLE job_proposals
  DROP CONSTRAINT IF EXISTS job_proposals_worker_id_fkey;

ALTER TABLE job_proposals
  ADD CONSTRAINT job_proposals_worker_id_fkey
  FOREIGN KEY (worker_id)
  REFERENCES profiles(id)
  ON DELETE CASCADE;

ALTER TABLE help_acceptances
  DROP CONSTRAINT IF EXISTS help_acceptances_worker_id_fkey;

ALTER TABLE help_acceptances
  ADD CONSTRAINT help_acceptances_worker_id_fkey
  FOREIGN KEY (worker_id)
  REFERENCES profiles(id)
  ON DELETE CASCADE;


-- ══════════════════════════════════════════════════════════════
-- PRIORITY 2 — Auth checks in SECURITY DEFINER RPCs
-- ══════════════════════════════════════════════════════════════
--
-- All three functions are SECURITY DEFINER — they bypass RLS entirely.
-- Without an explicit auth.uid() check inside the function body, any
-- authenticated user could call them with an arbitrary UUID as the
-- identity parameter and the DB would accept the action.


-- ── 2a. accept_proposal ─────────────────────────────────────────────
--
-- Vulnerability: any authenticated user who knows a proposal UUID and
-- its job UUID could call accept_proposal(p_proposal_id, p_job_id) and
-- accept a proposal on behalf of the real client, confirming the job,
-- notifying the worker, and auto-creating a help_request.
--
-- Fix: add an auth.uid() = client_id check at the top of the function,
-- before acquiring the FOR UPDATE lock on job_proposals.
-- Using the snapshot body from 2026-07-09 as the base.

CREATE OR REPLACE FUNCTION public.accept_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id          uuid;
  v_scheduled_date     date;
  v_scheduled_time     time;
  v_scheduled_flexible boolean;
  v_people_needed      int;
  v_equipment_required boolean;
BEGIN
  -- AUTH CHECK: caller must be the client of this job.
  IF NOT EXISTS (
    SELECT 1 FROM job_requests
    WHERE  id = p_job_id AND client_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode aceitar propostas.';
  END IF;

  SELECT worker_id, scheduled_date, scheduled_time, scheduled_flexible,
         people_needed, helpers_equipment_required
  INTO   v_worker_id, v_scheduled_date, v_scheduled_time, v_scheduled_flexible,
         v_people_needed, v_equipment_required
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'accepted', updated_at = now()
  WHERE id = p_proposal_id;

  WITH rejected AS (
    UPDATE job_proposals
    SET status = 'rejected', updated_at = now()
    WHERE job_id = p_job_id
      AND id    <> p_proposal_id
      AND status = 'pending'
    RETURNING worker_id
  )
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    worker_id,
    'proposal_rejected',
    'Proposta não selecionada',
    'O cliente escolheu outra proposta.',
    p_job_id,
    'job_request'
  FROM rejected;

  UPDATE job_requests
  SET status               = 'confirmed',
      accepted_proposal_id = p_proposal_id,
      confirmed_date       = v_scheduled_date,
      confirmed_time       = v_scheduled_time,
      confirmed_flexible   = COALESCE(v_scheduled_flexible, false),
      proposal_count       = 0,
      updated_at           = now()
  WHERE id = p_job_id;

  IF v_people_needed > 1 THEN
    INSERT INTO help_requests (
      job_id, proposal_id, slots_needed,
      equipment_required, created_post_confirmation, status
    ) VALUES (
      p_job_id, p_proposal_id, v_people_needed - 1,
      COALESCE(v_equipment_required, false), false, 'open'
    );
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id,
    'proposal_accepted',
    'Proposta aceite!',
    'O cliente aceitou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$function$;


-- ── 2b. create_proposal ─────────────────────────────────────────────
--
-- Vulnerability: p_worker_id is caller-supplied with no verification.
-- Any authenticated user could call create_proposal with
-- p_worker_id = victim_uuid and submit a proposal on another worker's behalf.
--
-- Fix: add p_worker_id IS DISTINCT FROM auth.uid() check at entry.
-- IS DISTINCT FROM handles NULL safely (auth.uid() is always non-NULL
-- for authenticated callers, but IS DISTINCT FROM is more defensive).

CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_worker_id                  uuid,
  p_hourly_rate                numeric,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job_status  text;
  v_client_id   uuid;
BEGIN
  -- AUTH CHECK: worker can only create proposals as themselves.
  IF p_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  SELECT status, client_id
  INTO   v_job_status, v_client_id
  FROM   job_requests
  WHERE  id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job_status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE job_id = p_job_id AND worker_id = p_worker_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    status
  ) VALUES (
    p_job_id, p_worker_id, p_hourly_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
    'pending'
  )
  RETURNING id INTO v_proposal_id;

  UPDATE job_requests
  SET proposal_count = proposal_count + 1,
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_client_id,
    'proposal_received',
    'Nova proposta recebida',
    'Um jardineiro enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$function$;


-- ── 2c. sync_worker_service_types ──────────────────────────────────
--
-- Vulnerability: any authenticated user could call
-- rpc('sync_worker_service_types', {'p_worker_id': victim_uuid, 'p_service_type_ids': []})
-- and wipe another worker's service types entirely. The worker_service_types
-- RLS policy (ALL USING: auth.uid() = worker_id) is bypassed by SECURITY DEFINER.
--
-- Fix: add p_worker_id IS DISTINCT FROM auth.uid() check at entry.

CREATE OR REPLACE FUNCTION public.sync_worker_service_types(
  p_worker_id        uuid,
  p_service_type_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- AUTH CHECK: workers can only sync their own service types.
  IF p_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  DELETE FROM worker_service_types WHERE worker_id = p_worker_id;
  IF array_length(p_service_type_ids, 1) IS NOT NULL
     AND array_length(p_service_type_ids, 1) > 0 THEN
    INSERT INTO worker_service_types (worker_id, service_type_id)
    SELECT p_worker_id, unnest(p_service_type_ids);
  END IF;
END;
$function$;


-- ══════════════════════════════════════════════════════════════
-- PRIORITY 3 — Prevent profiles.role escalation
-- ══════════════════════════════════════════════════════════════
--
-- Vulnerability: the UPDATE policy "Utilizador atualiza o seu perfil"
-- had USING (auth.uid() = id) but no WITH CHECK. A user could send
-- PATCH /profiles?id=eq.<uid> with body {"role":"worker"} and the DB
-- would accept it — no validation that role was unchanged.
--
-- WITH CHECK cannot reference OLD.role in PostgreSQL RLS expressions
-- (WITH CHECK evaluates only the NEW row). A BEFORE UPDATE trigger is
-- the correct fix because it has access to both OLD and NEW.
--
-- The trigger is the PRIMARY guard. The WITH CHECK on the policy is
-- updated to be explicit (matching USING) for consistency; it does not
-- add role-change protection on its own.

CREATE OR REPLACE FUNCTION public.prevent_profile_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'Não é permitido alterar o role do perfil.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_prevent_profile_role_change ON profiles;
CREATE TRIGGER tg_prevent_profile_role_change
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_profile_role_change();

-- Recreate UPDATE policy with explicit WITH CHECK.
-- Drops both possible names (live DB uses "atualiza", baseline used "atualiza o seu próprio").
DROP POLICY IF EXISTS "Utilizador atualiza o seu perfil"        ON profiles;
DROP POLICY IF EXISTS "Utilizador atualiza o seu próprio perfil" ON profiles;
CREATE POLICY "Utilizador atualiza o seu perfil"
  ON profiles FOR UPDATE TO authenticated
  USING     (auth.uid() = id)
  WITH CHECK (auth.uid() = id);


-- ══════════════════════════════════════════════════════════════
-- PRIORITY 4 — Six missing indexes from 0001_baseline
-- ══════════════════════════════════════════════════════════════
--
-- Root cause: the 0001_baseline CREATE INDEX statements were written
-- after the CREATE TABLE IF NOT EXISTS blocks and run as standalone
-- statements — they should have applied. However, the live DB snapshot
-- (2026-07-09) confirms all six are absent. Three others
-- (idx_help_requests_job_id, idx_help_acceptances_worker_id,
-- idx_notifications_user_created) were added in migration 0027.
--
-- idx_notifications_user_id: a prefix of idx_notifications_user_created
-- (user_id, created_at DESC). PostgreSQL can use the composite index
-- for user_id-only queries, but an explicit single-column index is
-- cheaper for equality scans on notifications.user_id alone.
-- idx_notifications_user_read: distinct from user_created; supports
-- "unread badge" queries (user_id + read = false) efficiently.

CREATE INDEX IF NOT EXISTS idx_job_requests_client_id
  ON job_requests (client_id);

CREATE INDEX IF NOT EXISTS idx_job_requests_status
  ON job_requests (status);

CREATE INDEX IF NOT EXISTS idx_job_proposals_worker_id
  ON job_proposals (worker_id);

CREATE INDEX IF NOT EXISTS idx_job_proposals_job_id
  ON job_proposals (job_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON notifications (user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_read
  ON notifications (user_id, read);


-- ══════════════════════════════════════════════════════════════
-- PRIORITY 5 — Capture live DB profiles SELECT policies
-- ══════════════════════════════════════════════════════════════
--
-- The live DB has three granular SELECT policies on the profiles table
-- that are absent from all previous migrations. They replaced the broad
-- "Perfis são legíveis por utilizadores autenticados" (USING: true)
-- policy from 0001_baseline, which was dropped interactively.
--
-- Without this capture, applying migrations 0001→0031 against a fresh
-- DB leaves the broad USING(true) policy in place — any authenticated
-- user can read any profile. The live DB is more restrictive.
--
-- "Utilizador vê o seu perfil": owner reads their own profile row.
-- "Worker ve perfil de cliente com job confirmado": worker reads a
--   client's profile when they have an accepted proposal for the job.
-- "Cliente ve perfil de worker com job confirmado": client reads a
--   worker's profile (identified by role = 'worker') when they have a
--   confirmed/completed job with that worker.
--
-- All three are idempotent (DROP IF EXISTS + CREATE).

-- Remove the old broad policy if it survived from 0001 (fresh-DB case).
DROP POLICY IF EXISTS "Perfis são legíveis por utilizadores autenticados" ON profiles;

-- Owner reads own profile.
DROP POLICY IF EXISTS "Utilizador vê o seu perfil" ON profiles;
CREATE POLICY "Utilizador vê o seu perfil"
  ON profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

-- Worker reads a client profile when they have an accepted proposal for the job.
DROP POLICY IF EXISTS "Worker ve perfil de cliente com job confirmado" ON profiles;
CREATE POLICY "Worker ve perfil de cliente com job confirmado"
  ON profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   job_proposals jp
      JOIN   job_requests  jr ON jr.id = jp.job_id
      WHERE  jp.worker_id  = auth.uid()
        AND  jr.client_id  = profiles.id
        AND  jp.status     = 'accepted'
    )
  );

-- Client reads a worker profile when they have a confirmed/completed job with them.
-- The role = 'worker' guard prevents this policy from opening client profiles
-- to other clients via the client_has_confirmed_job_with_worker function.
DROP POLICY IF EXISTS "Cliente ve perfil de worker com job confirmado" ON profiles;
CREATE POLICY "Cliente ve perfil de worker com job confirmado"
  ON profiles FOR SELECT TO authenticated
  USING (
    role = 'worker'
    AND client_has_confirmed_job_with_worker(id)
  );
