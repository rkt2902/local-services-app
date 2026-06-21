
-- ==============================================================
-- supabase/migrations/0004_help_acceptance_pending_status.sql
-- Adds 'pending' and 'rejected' to help_acceptance_status;
-- adds RLS policies for INSERT/SELECT on help_acceptances;
-- updates accept_help_candidate to guard on pending status;
-- adds reject_help_candidate RPC.
-- See decisions_log.md 2026-06-21.
-- ==============================================================

-- PRE-FLIGHT GUARD: abort if help_acceptances has any rows.
DO $$
DECLARE
  v_count bigint;
BEGIN
  SELECT COUNT(*) INTO v_count FROM help_acceptances;
  IF v_count > 0 THEN
    RAISE EXCEPTION
      'Pre-flight failed: help_acceptances has % row(s). '
      'Inspect and truncate or migrate the data first.',
      v_count;
  END IF;
END;
$$;

-- ─── CHECK constraint ─────────────────────────────────────────
-- Drop the existing status CHECK (auto-named by Postgres) and
-- replace with one that adds 'pending' and 'rejected'.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT conname
    FROM   pg_constraint
    WHERE  conrelid = 'help_acceptances'::regclass
      AND  contype  = 'c'
      AND  pg_get_constraintdef(oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE help_acceptances DROP CONSTRAINT %I', r.conname);
  END LOOP;
END;
$$;

ALTER TABLE help_acceptances
  ADD CONSTRAINT help_acceptances_status_check
    CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled'));

-- ─── RLS: help_acceptances ────────────────────────────────────

-- Candidate workers can INSERT their own application.
-- Enforces worker_id = caller and status must start as 'pending'.
CREATE POLICY "Worker candidata-se a help_request"
  ON help_acceptances FOR INSERT TO authenticated
  WITH CHECK (worker_id = auth.uid() AND status = 'pending');

-- Each worker sees their own candidatures (for their status view).
CREATE POLICY "Worker vê as suas candidaturas"
  ON help_acceptances FOR SELECT TO authenticated
  USING (worker_id = auth.uid());

-- Principal worker sees all candidates for their help_requests
-- (lobby view). Reuses the SECURITY DEFINER helper from 0003.
CREATE POLICY "Worker principal vê candidatos"
  ON help_acceptances FOR SELECT TO authenticated
  USING (is_principal_worker_for_help_request(help_request_id));

-- ─── accept_help_candidate (updated) ─────────────────────────
-- Now verifies current status = 'pending' before accepting,
-- preventing double-acceptance of an already-accepted row.

CREATE OR REPLACE FUNCTION accept_help_candidate(
  p_help_acceptance_id uuid,
  p_agreed_rate        numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_slots_needed        int;
  v_accepted_count      int;
  v_current_status      text;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id,
         hr.slots_needed, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id,
         v_slots_needed, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;

  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode aceitar candidatos.';
  END IF;

  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION
      'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances
  SET    status = 'accepted', agreed_rate = p_agreed_rate
  WHERE  id = p_help_acceptance_id;

  SELECT COUNT(*) INTO v_accepted_count
  FROM   help_acceptances
  WHERE  help_request_id = v_help_request_id
    AND  status = 'accepted';

  IF v_accepted_count >= v_slots_needed THEN
    UPDATE help_requests SET status = 'filled' WHERE id = v_help_request_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_helper_worker_id,
    'help_accepted',
    'Candidatura aceite!',
    'Foste selecionado para fazer parte da equipa.',
    v_help_request_id,
    'help_request'
  );
END;
$$;

-- ─── reject_help_candidate ────────────────────────────────────
-- Called by the principal worker.  Sets status → 'rejected' and
-- notifies the candidate.  Only acts on 'pending' candidatures.

CREATE OR REPLACE FUNCTION reject_help_candidate(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_current_status      text;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;

  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode rejeitar candidatos.';
  END IF;

  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION
      'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances
  SET    status = 'rejected'
  WHERE  id = p_help_acceptance_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_helper_worker_id,
    'help_rejected',
    'Candidatura não selecionada',
    'O worker principal não selecionou a tua candidatura.',
    v_help_request_id,
    'help_request'
  );
END;
$$;
