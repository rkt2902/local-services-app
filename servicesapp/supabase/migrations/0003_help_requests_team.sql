
-- ==============================================================
-- supabase/migrations/0003_help_requests_team.sql
-- Fase 9 data layer: expanded help_requests/help_acceptances
-- schema, three new RPCs, and two new RLS policies for the
-- team/helper feature.  See decisions_log.md 2026-06-19.
-- ==============================================================

-- PRE-FLIGHT GUARD: abort if either table has live rows.
-- The new NOT NULL columns carry DEFAULT values (0 / false), but
-- it is cheaper to detect data-in-use before the ALTER than to
-- roll back a backfill after the fact.
DO $$
DECLARE
  v_hr_count bigint;
  v_ha_count bigint;
BEGIN
  SELECT COUNT(*) INTO v_hr_count FROM help_requests;
  SELECT COUNT(*) INTO v_ha_count FROM help_acceptances;
  IF v_hr_count > 0 OR v_ha_count > 0 THEN
    RAISE EXCEPTION
      'Pre-flight failed: help_requests has % row(s), '
      'help_acceptances has % row(s). '
      'Inspect and truncate or migrate the data first.',
      v_hr_count, v_ha_count;
  END IF;
END;
$$;

-- ─── help_requests: new columns ──────────────────────────────

ALTER TABLE help_requests
  ADD COLUMN equipment_required        boolean NOT NULL DEFAULT false,
  ADD COLUMN created_post_confirmation boolean NOT NULL DEFAULT false;

-- Drop the unnamed status CHECK (auto-named by Postgres) and
-- replace with one that includes 'pending_approval'.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT conname
    FROM   pg_constraint
    WHERE  conrelid = 'help_requests'::regclass
      AND  contype  = 'c'
      AND  pg_get_constraintdef(oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE help_requests DROP CONSTRAINT %I', r.conname);
  END LOOP;
END;
$$;

ALTER TABLE help_requests
  ADD CONSTRAINT help_requests_status_check
    CHECK (status IN ('pending_approval', 'open', 'filled', 'cancelled'));

-- ─── help_acceptances: new columns ───────────────────────────

ALTER TABLE help_acceptances
  ADD COLUMN agreed_rate       numeric NOT NULL DEFAULT 0,
  ADD COLUMN brought_equipment boolean NOT NULL DEFAULT false;

-- ─── RLS helper function ──────────────────────────────────────
-- Returns true when auth.uid() is the principal worker for the
-- given help_request (i.e. owns the accepted proposal tied to
-- that request).  SECURITY DEFINER prevents infinite recursion
-- that would otherwise occur if the subquery triggered RLS on
-- help_requests/job_proposals while evaluating an
-- help_acceptances UPDATE policy.

CREATE OR REPLACE FUNCTION is_principal_worker_for_help_request(
  p_help_request_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.id            = p_help_request_id
      AND  jp.worker_id     = auth.uid()
  );
$$;

-- ─── RLS: help_requests ──────────────────────────────────────

-- Client can read pending_approval rows for their own jobs so
-- they can act on approve_help_request.
CREATE POLICY "Cliente vê help requests pendentes de aprovação"
  ON help_requests FOR SELECT TO authenticated
  USING (
    status = 'pending_approval'
    AND EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id = help_requests.job_id
        AND  client_id = auth.uid()
    )
  );

-- ─── RLS: help_acceptances ───────────────────────────────────

-- Principal worker can UPDATE any help_acceptance linked to
-- their own help_requests (lobby selection model).
CREATE POLICY "Worker principal decide candidatos"
  ON help_acceptances FOR UPDATE TO authenticated
  USING (is_principal_worker_for_help_request(help_request_id));

-- ─── get_help_requests_in_radius ─────────────────────────────
-- Returns open help_requests within radius_km of the worker's
-- position.  Mirrors get_jobs_in_radius (same Haversine formula,
-- SECURITY DEFINER, STABLE, LANGUAGE sql).
-- Location is inherited from the parent job via job_id —
-- help_requests has no own location columns.

CREATE OR REPLACE FUNCTION get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
)
RETURNS SETOF help_requests
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT hr.*
  FROM   help_requests hr
  JOIN   job_requests  jr ON jr.id = hr.job_id
  WHERE  hr.status = 'open'
    AND (
      2 * 6371 * asin(sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))
    ) <= radius_km
  ORDER BY hr.created_at DESC;
$$;

-- ─── approve_help_request ────────────────────────────────────
-- Called by the client.  Moves a pending_approval help_request
-- to open, making it visible to candidate workers.
-- Notifies the principal worker (proposal owner).

CREATE OR REPLACE FUNCTION approve_help_request(p_help_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status        text;
  v_job_client_id uuid;
  v_worker_id     uuid;
BEGIN
  SELECT hr.status, jr.client_id, jp.worker_id
  INTO   v_status, v_job_client_id, v_worker_id
  FROM   help_requests hr
  JOIN   job_requests  jr ON jr.id = hr.job_id
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  WHERE  hr.id = p_help_request_id
  FOR UPDATE OF hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'help_request não encontrado.';
  END IF;

  IF v_job_client_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o cliente do job pode aprovar este pedido de ajuda.';
  END IF;

  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION
      'help_request não está em pending_approval (estado atual: %).', v_status;
  END IF;

  UPDATE help_requests
  SET    status = 'open'
  WHERE  id = p_help_request_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id,
    'help_request_approved',
    'Pedido de equipa aprovado',
    'O cliente aprovou o pedido de ajudantes. Podes agora aceitar candidatos.',
    p_help_request_id,
    'help_request'
  );
END;
$$;

-- ─── accept_help_candidate ───────────────────────────────────
-- Called by the principal worker.  Sets agreed_rate + status on
-- one help_acceptance.  If slots_needed is now fully met across
-- all accepted candidates, marks the help_request as 'filled'.
-- Notifies the accepted helper worker.

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
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, hr.slots_needed
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id, v_slots_needed
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
