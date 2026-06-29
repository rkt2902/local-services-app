-- ==============================================================
-- supabase/migrations/0025_cancel_job_client_reopen_choice.sql
--
-- T5 fix (2026-06-29): cancel_job auto-reopen was triggered for the
-- CLIENT without asking them, even though "find a replacement worker"
-- is a worker-cancellation concern.
--
-- Confirmed via direct SQL inspection (0013 body):
--   - Worker path: auto-reopens and excludes the cancelling worker.
--   - Client path: auto-reopens (BUG), does NOT exclude anyone (correct).
--
-- Fix: add p_client_wants_reopen boolean DEFAULT NULL.
--   - Worker call sites don't pass this param → NULL → worker branch
--     ignores it entirely (worker path unchanged).
--   - Client call sites pass true/false from the new dialog.
--     Only creates the reopened job when p_client_wants_reopen = true.
--     NEVER excludes any worker from the client path — exclusion is a
--     worker accountability measure, not applicable here.
--
-- Overload note: adding a 4th parameter creates a new signature.
-- The old cancel_job(uuid, text, text) is explicitly dropped first so
-- exactly ONE overload exists after this migration.
-- Dart call sites that omit p_client_wants_reopen work via DEFAULT NULL.
-- ==============================================================

DROP FUNCTION IF EXISTS cancel_job(uuid, text, text);

CREATE OR REPLACE FUNCTION cancel_job(
  p_job_id              uuid,
  p_reason              text,
  p_reason_detail       text    DEFAULT NULL,
  p_client_wants_reopen boolean DEFAULT NULL
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

  -- 24h rule: confirmed jobs with a fixed date cannot be cancelled within 24h.
  -- Applies to both client and worker. Flexible-date jobs (confirmed_date IS
  -- NULL) skip this check, matching propose_reschedule's existing behaviour.
  IF v_job.status = 'confirmed'
     AND v_job.confirmed_date IS NOT NULL
     AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
    RAISE EXCEPTION 'O cancelamento requer pelo menos 24h de antecedência.';
  END IF;

  IF v_is_worker THEN
    v_other_user_id := v_job.client_id;
  ELSE
    SELECT worker_id INTO v_other_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  END IF;

  -- Reopen eligibility:
  --   Worker: auto-reopens always if within the 2-strike limit (unchanged).
  --   Client: only reopens when the client explicitly requests it
  --           (p_client_wants_reopen = true) AND within the 1-reopen limit.
  --           p_client_wants_reopen IS NULL (worker call site) → false for
  --           the client branch, so the worker path is never affected.
  IF v_job.status = 'confirmed' THEN
    IF v_is_worker THEN
      IF v_job.reopen_count_worker < 2 THEN
        v_can_reopen := true;
      END IF;
    ELSE
      IF p_client_wants_reopen = true AND v_job.reopen_count_client < 1 THEN
        v_can_reopen := true;
      END IF;
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
    -- Worker path: exclude the cancelling worker from the reopened job so
    --             the same worker cannot re-apply (2-strike accountability).
    -- Client path: never exclude anyone — the client's cancellation is not
    --              a negative signal about the worker, only about the client's
    --              need. The reopened job should be open to all workers.
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

    -- Notify client only when the WORKER triggered the reopen (auto-reopen).
    -- When the CLIENT triggers the reopen (explicit choice), they already know.
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
