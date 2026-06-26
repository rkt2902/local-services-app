-- ==============================================================
-- supabase/migrations/0020_no_response_cron_and_client_notify.sql
--
-- P-8-1: implements the open→no_response transition that was never
--   built.  Adds auto_expire_jobs() (FOR UPDATE SKIP LOCKED, same
--   pattern as auto_confirm_completed_jobs) + a pg_cron job at the
--   same 3-hour cadence.
--
-- P-10-3: fixes auto_confirm_completed_jobs() to also notify the
--   client.  The original function only inserted a notification for
--   the worker (v_worker_id).  v_job.client_id is already available
--   in the v_job rowtype — no new variable needed.
--
-- THIS FILE IS NOT APPLIED — apply manually via Supabase SQL Editor.
-- After applying, verify both cron jobs are active:
--   SELECT jobname, schedule, active FROM cron.job
--   WHERE jobname IN ('auto-expire-jobs', 'auto-confirm-completed-jobs');
-- ==============================================================


-- ─── P-8-1: auto_expire_jobs ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.auto_expire_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status       = 'open'
      AND  expires_at   < now()
      AND  proposal_count = 0
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status     = 'no_response',
           updated_at = now()
    WHERE  id = v_job.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_job.client_id,
      'job_no_response',
      'Sem resposta',
      'O teu pedido não recebeu propostas em 48h.',
      v_job.id,
      'job_request'
    );
  END LOOP;
END;
$function$;

SELECT cron.schedule(
  'auto-expire-jobs',
  '0 */3 * * *',
  'SELECT auto_expire_jobs()'
);


-- ─── P-10-3: auto_confirm_completed_jobs — add client notification ───
--
-- Full body reproduced from 0014 (current live version).
-- Only change: second notification INSERT for v_job.client_id after
-- the existing worker INSERT.

CREATE OR REPLACE FUNCTION public.auto_confirm_completed_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status     = 'awaiting_confirmation'
      AND  updated_at < NOW() - INTERVAL '3 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status     = 'completed',
           updated_at = now()
    WHERE  id = v_job.id;

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals
    WHERE  id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        v_worker_id,
        'job_completed',
        'Trabalho confirmado automaticamente',
        'Passaram 3 dias sem confirmação. O trabalho foi confirmado automaticamente.',
        v_job.id,
        'job_request'
      );
    END IF;

    -- P-10-3 fix: notify the client too.
    -- Body is distinct from the worker's to make clear who initiated.
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_job.client_id,
      'job_completed',
      'Trabalho confirmado automaticamente',
      'Passaram 3 dias sem resposta. O trabalho foi confirmado automaticamente.',
      v_job.id,
      'job_request'
    );
  END LOOP;
END;
$function$;
