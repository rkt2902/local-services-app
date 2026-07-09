-- ==============================================================
-- supabase/migrations/0005_proposal_helpers_estimate.sql
-- Extends job_proposals with helpers_equipment_required and
-- updates create_proposal + accept_proposal accordingly.
-- See decisions_log.md 2026-06-24.
-- ==============================================================

-- ─── 1. Drop confirmed-obsolete create_proposal overloads ────
-- These pre-date the estimated_hours_min/max split (2026-06-11)
-- and people_needed (2026-06-08). Exact signatures from live DB.

DROP FUNCTION IF EXISTS create_proposal(uuid, uuid, numeric, numeric, integer, text);
DROP FUNCTION IF EXISTS create_proposal(uuid, uuid, numeric, numeric, numeric, integer, text);

-- ─── 2. New column on job_proposals ──────────────────────────

ALTER TABLE job_proposals
  ADD COLUMN helpers_equipment_required boolean NOT NULL DEFAULT false;

-- ─── 3. CREATE OR REPLACE create_proposal ────────────────────
-- Adds p_helpers_equipment_required (DEFAULT false) as an 11th
-- parameter.  All other logic is unchanged from the baseline.

CREATE OR REPLACE FUNCTION create_proposal(
  p_job_id                     uuid,
  p_worker_id                  uuid,
  p_hourly_rate                numeric,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              int      DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proposal_id uuid;
  v_job_status  text;
  v_client_id   uuid;
BEGIN
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
$$;

-- ─── 4. CREATE OR REPLACE accept_proposal ────────────────────
-- Adds auto-creation of help_request when people_needed > 1.
-- The initial SELECT is extended to also fetch people_needed and
-- helpers_equipment_required. All other logic is unchanged.

CREATE OR REPLACE FUNCTION accept_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id          uuid;
  v_scheduled_date     date;
  v_scheduled_time     time;
  v_scheduled_flexible boolean;
  v_people_needed      int;
  v_equipment_required boolean;
BEGIN
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
$$;
