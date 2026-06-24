-- ==============================================================
-- supabase/migrations/0009_help_cancellation_handling.sql
-- Three gaps in Fase 9 cancellation handling (designed 2026-06-24):
--
-- 1. cancel_job: notify accepted helpers when their job is cancelled
--    (new notification type: help_job_cancelled).
--
-- 2. withdraw_help_acceptance: new RPC allowing an accepted helper to
--    withdraw from a job.  If the help_request was 'filled', reverts
--    it to 'open' and notifies rejected candidates that a slot is
--    available again (help_request_reopened).  Always notifies the
--    principal worker that a helper withdrew (help_withdrew).
--
-- 3. Three new notification type strings used above are declared in
--    notification_types.dart — no schema change needed for them.
-- ==============================================================


-- ─── 1. cancel_job — notify accepted helpers ─────────────────────────────────
--
-- Full body reproduced from 0007 (current live version).  Only addition:
-- an INSERT INTO notifications SELECT that fires right after the 0007 cascade
-- UPDATEs, notifying every accepted helper for this job.
-- Accepted rows are not changed by the cascade (which only rejects pending),
-- so the WHERE ha.status = 'accepted' filter is still accurate at this point.
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

  -- C2.2 (from 0007): cascade cancellation to helper team data.
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

  -- Notify accepted helpers that the job they were helping on is cancelled.
  -- Runs after the cascade above (which only rejects pending), so
  -- ha.status = 'accepted' still correctly identifies impacted helpers.
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id,
         'help_job_cancelled',
         'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado.',
         p_job_id,
         'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id = p_job_id
    AND  ha.status = 'accepted';

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


-- ─── 2. withdraw_help_acceptance ─────────────────────────────────────────────
--
-- Called by an accepted helper to withdraw from a job.
--
-- Preconditions:
--   - Caller must be the worker_id on the help_acceptance.
--   - Current status must be 'accepted' (use rejectHelpCandidate for pending;
--     nothing to do for already-cancelled or rejected rows).
--
-- Effects:
--   1. Sets help_acceptances.status → 'cancelled'.
--   2. If the parent help_request was 'filled', reverts it to 'open' (slot
--      freed).  If already 'open' (slot was not the last one), no change
--      needed.
--   3. If the help_request was reverted to 'open', notifies all candidates
--      with status = 'rejected' for that help_request so they can re-apply
--      (type: help_request_reopened, related_id = help_request_id).
--   4. Notifies the principal worker that a helper withdrew
--      (type: help_withdrew, related_id = help_request_id).
--
-- Race condition note: two helpers withdrawing simultaneously each lock their
-- own help_acceptance row (FOR UPDATE OF ha) but not the help_requests row.
-- Both may set help_requests.status = 'open' (idempotent) and both may send
-- reopen notifications to rejected candidates (duplicate notifications —
-- acceptable for MVP given extremely low likelihood of simultaneous withdrawal).

CREATE OR REPLACE FUNCTION withdraw_help_acceptance(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id           uuid;
  v_help_request_id     uuid;
  v_help_request_status text;
  v_principal_worker_id uuid;
  v_current_status      text;
BEGIN
  SELECT ha.worker_id,
         ha.help_request_id,
         ha.status,
         hr.status,
         jp.worker_id
  INTO   v_worker_id,
         v_help_request_id,
         v_current_status,
         v_help_request_status,
         v_principal_worker_id
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;

  IF v_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Só podes retirar a tua própria candidatura.';
  END IF;

  IF v_current_status <> 'accepted' THEN
    RAISE EXCEPTION
      'Só podes retirar uma candidatura aceite (estado atual: %).', v_current_status;
  END IF;

  -- Withdraw the acceptance
  UPDATE help_acceptances
  SET    status = 'cancelled'
  WHERE  id = p_help_acceptance_id;

  -- If this withdrawal frees the last required slot, reopen the help_request
  IF v_help_request_status = 'filled' THEN
    UPDATE help_requests
    SET    status = 'open'
    WHERE  id = v_help_request_id;

    -- Notify all rejected candidates that the slot is available again
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id,
           'help_request_reopened',
           'Vaga disponível novamente',
           'Uma vaga para ajudante voltou a ficar disponível.',
           v_help_request_id,
           'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id
      AND  ha.status          = 'rejected';
  END IF;

  -- Notify the principal worker that a helper withdrew
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_principal_worker_id,
    'help_withdrew',
    'Ajudante desistiu',
    'Um ajudante retirou a sua aceitação.',
    v_help_request_id,
    'help_request'
  );
END;
$$;
