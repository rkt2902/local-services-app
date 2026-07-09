-- ==============================================================
-- supabase/migrations/0007_fase9_review_fixes.sql
-- Fixes from the Fase 9 code review (2026-06-24).
--
-- C2.2 — cancel_job now cascades to help_requests/help_acceptances
-- C2.3 — get_help_requests_in_radius excludes cancelled/completed jobs
-- C3.1 — drop "Worker aceita ajudar" (redundant permissive INSERT)
-- C3.3 — "Worker principal cria help requests" restricted to accepted proposals
-- C3.4 — "Worker cancela ajuda" restricted to withdrawal (status='cancelled')
-- C5.2 — CHECK constraint on agreed_rate for accepted rows
-- C7.4 — get_help_requests_in_radius excludes principal's own help_requests
--
-- Order: 1a → 1b → 1c → 1d → 1e → 1f
-- ==============================================================


-- ─── 1a. cancel_job — cascade to help_requests / help_acceptances ─────────────
--
-- Full body reproduced verbatim from 0001_baseline.sql.  Only addition:
-- two UPDATE statements after the proposal rejection, before notifications,
-- that cancel open help_requests and reject pending help_acceptances when
-- the parent job is cancelled.
--
-- Signature unchanged: cancel_job(uuid, text, text DEFAULT NULL) RETURNS uuid

CREATE OR REPLACE FUNCTION cancel_job(
  p_job_id        uuid,
  p_reason        text,
  p_reason_detail text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job           job_requests%ROWTYPE;
  v_caller_id     uuid    := auth.uid();
  v_is_worker     boolean;
  v_other_user_id uuid;
  v_can_reopen    boolean := false;
  v_new_excluded  uuid[];
  v_new_job_id    uuid    := NULL;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed') THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser cancelado no estado atual.';
  END IF;

  v_is_worker := (v_job.client_id <> v_caller_id);

  IF v_is_worker THEN
    v_other_user_id := v_job.client_id;
  ELSE
    SELECT worker_id INTO v_other_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  END IF;

  IF v_job.status = 'confirmed' THEN
    IF (NOT v_is_worker) AND v_job.reopen_count_client < 1 THEN
      v_can_reopen := true;
    ELSIF v_is_worker AND v_job.reopen_count_worker < 2 THEN
      v_can_reopen := true;
    END IF;
  END IF;

  UPDATE job_requests
  SET status               = 'cancelled',
      cancelled_by         = v_caller_id,
      cancel_reason        = p_reason,
      cancel_reason_detail = p_reason_detail,
      cancelled_worker_id  = CASE WHEN v_is_worker THEN v_caller_id ELSE NULL END,
      updated_at           = now()
  WHERE id = p_job_id;

  UPDATE job_proposals
  SET status = 'rejected', updated_at = now()
  WHERE job_id = p_job_id AND status = 'pending';

  -- C2.2: cascade cancellation to helper team data so orphaned rows cannot
  -- resurface in the discovery screen or lobby after the job is gone.
  UPDATE help_requests
  SET    status = 'cancelled'
  WHERE  job_id = p_job_id
    AND  status <> 'cancelled';

  UPDATE help_acceptances
  SET    status = 'rejected'
  WHERE  help_request_id IN (
           SELECT id FROM help_requests WHERE job_id = p_job_id
         )
    AND  status = 'pending';

  IF v_other_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_other_user_id,
      'job_cancelled',
      'Pedido cancelado',
      'Um pedido foi cancelado.',
      p_job_id,
      'job_request'
    );
  END IF;

  IF v_can_reopen THEN
    v_new_excluded := v_job.excluded_worker_ids;
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id,       service_type_id,   address_text,
      location_lat,    location_lng,
      date_mode,       preferred_date,    availability_text,
      urgency,         size_estimate,     description,
      status,          reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id,      v_job.service_type_id, v_job.address_text,
      v_job.location_lat,   v_job.location_lng,
      v_job.date_mode,      v_job.preferred_date,  v_job.availability_text,
      v_job.urgency,        v_job.size_estimate,   v_job.description,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded,
      now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        v_job.client_id,
        'job_reopened',
        'Pedido reaberto',
        'O pedido foi reaberto automaticamente.',
        v_new_job_id,
        'job_request'
      );
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$$;


-- ─── 1b. get_help_requests_in_radius — two additional WHERE filters ────────────
--
-- (1) Exclude help_requests whose parent job is cancelled or completed — prevents
--     orphaned rows (C2.2 cascade covers future cancels; this covers any historic
--     gaps and the completed case, which cancel_job never touches).
--
-- (2) Exclude help_requests where the calling worker IS the principal — a principal
--     worker should not be able to apply to their own help_request (C7.4).
--
-- Return type is identical to 0006; CREATE OR REPLACE is safe (no DROP needed).
-- STABLE is correct: auth.uid() is stable within a transaction.

CREATE OR REPLACE FUNCTION get_help_requests_in_radius(
  worker_lat  double precision,
  worker_lng  double precision,
  radius_km   integer
)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  proposal_id               uuid,
  slots_needed              integer,
  status                    text,
  equipment_required        boolean,
  created_post_confirmation boolean,
  created_at                timestamptz,
  location_lat              double precision,
  location_lng              double precision,
  service_type_id           uuid,
  principal_name            text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    hr.id,
    hr.job_id,
    hr.proposal_id,
    hr.slots_needed,
    hr.status,
    hr.equipment_required,
    hr.created_post_confirmation,
    hr.created_at,
    jr.location_lat::double precision,
    jr.location_lng::double precision,
    jr.service_type_id,
    p.full_name AS principal_name
  FROM   help_requests  hr
  JOIN   job_requests   jr ON jr.id = hr.job_id
  JOIN   job_proposals  jp ON jp.id = hr.proposal_id
  JOIN   profiles        p ON p.id  = jp.worker_id
  WHERE  hr.status = 'open'
    AND  jr.status NOT IN ('cancelled', 'completed')
    AND  jp.worker_id <> auth.uid()
    AND (
      2 * 6371 * asin(sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))
    ) <= radius_km
  ORDER BY
    power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
    + cos(radians(worker_lat))
      * cos(radians(jr.location_lat::double precision))
      * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
    ASC;
$$;


-- ─── 1c. C3.1 — drop redundant permissive INSERT policy on help_acceptances ────
--
-- The 0001 baseline "Worker aceita ajudar" allows INSERT for any worker_id =
-- auth.uid() regardless of status.  PostgreSQL ORs permissive policies, so it
-- has always overridden "Worker candidata-se a help_request" (0004) which
-- restricts to status = 'pending'.  Dropping the baseline policy restores the
-- intended guard.  Policy "Worker candidata-se a help_request" remains.

DROP POLICY IF EXISTS "Worker aceita ajudar" ON help_acceptances;


-- ─── 1d. C3.3 — restrict help_requests INSERT to accepted proposals only ────────
--
-- The baseline policy allowed direct INSERT for any worker with a proposal in
-- ANY status (pending, rejected, superseded).  This let a worker create
-- help_requests without going through the accept_proposal RPC, bypassing slot
-- counting and notifications.  Restricted to status = 'accepted'.

DROP POLICY IF EXISTS "Worker principal cria help requests" ON help_requests;

CREATE POLICY "Worker principal cria help requests"
  ON help_requests FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE id        = help_requests.proposal_id
        AND worker_id = auth.uid()
        AND status    = 'accepted'
    )
  );


-- ─── 1e. C3.4 — restrict candidate self-UPDATE to withdrawal only ────────────────
--
-- The baseline UPDATE policy (USING auth.uid() = worker_id, no WITH CHECK)
-- allowed a candidate to UPDATE any column — including status, agreed_rate,
-- and brought_equipment — to any value on their own help_acceptance rows.
-- Restricted to only allow transitioning their own row TO status = 'cancelled'
-- (the withdrawal case).  All other status transitions (pending→accepted,
-- pending→rejected) go through the SECURITY DEFINER RPCs and are unaffected.

DROP POLICY IF EXISTS "Worker cancela ajuda" ON help_acceptances;

CREATE POLICY "Worker cancela ajuda"
  ON help_acceptances FOR UPDATE TO authenticated
  USING  (auth.uid() = worker_id)
  WITH CHECK (auth.uid() = worker_id AND status = 'cancelled');


-- ─── 1f. C5.2 — agreed_rate > 0 for accepted rows ───────────────────────────────
--
-- IMPORTANT: applyToHelpRequest (Dart) intentionally inserts agreed_rate = 0 as
-- a placeholder for pending candidatures; the real value is set by
-- accept_help_candidate RPC.  A bare CHECK (agreed_rate > 0) would therefore
-- break every candidate application INSERT.
--
-- The correct guard is conditional: if the row is accepted, the rate must be
-- positive.  Pending/rejected/cancelled rows may carry the placeholder value 0.
--
-- Pre-flight: abort if any ACCEPTED row already carries a non-positive rate.
-- (Pending rows with agreed_rate = 0 are expected and are not inspected here.)

DO $$
DECLARE
  v_count bigint;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM   help_acceptances
  WHERE  status = 'accepted'
    AND  agreed_rate <= 0;

  IF v_count > 0 THEN
    RAISE EXCEPTION
      'Pre-flight failed: % accepted help_acceptances row(s) have agreed_rate <= 0. '
      'Inspect with: '
      'SELECT id, help_request_id, worker_id, agreed_rate, status '
      'FROM help_acceptances WHERE status = ''accepted'' AND agreed_rate <= 0; '
      'Fix or delete those rows, then re-run this migration.',
      v_count;
  END IF;
END;
$$;

ALTER TABLE help_acceptances
  ADD CONSTRAINT check_agreed_rate
    CHECK (status <> 'accepted' OR agreed_rate > 0);
