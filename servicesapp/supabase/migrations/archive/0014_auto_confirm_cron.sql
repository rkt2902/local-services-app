-- ==============================================================
-- supabase/migrations/0014_auto_confirm_cron.sql
-- Auto-confirm jobs stuck in awaiting_confirmation for 3+ days.
--
-- Decision (2026-06-25): protects workers from clients who never
-- confirm completion.  Scheduled via pg_cron (extension manually
-- activated on this project 2026-06-25).
--
-- Pattern: SECURITY DEFINER batch function, no auth.uid() check —
-- the function acts as the system, not as a user.  Same pattern as
-- other internal batch operations (separate from the public
-- confirm_job_completion RPC, which remains unchanged).
--
-- Window proxy: awaiting_confirmation is a terminal write-state with
-- no further UPDATE until confirmation, so updated_at is a safe
-- proxy for "time entered awaiting_confirmation".
--
-- NOTE: the cron.schedule() call at the bottom registers a job in
-- cron.job — this is different from regular DDL.  After applying,
-- verify via:
--   SELECT * FROM cron.job WHERE jobname = 'auto-confirm-completed-jobs';
-- ==============================================================

CREATE OR REPLACE FUNCTION auto_confirm_completed_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  END LOOP;
END;
$$;

-- Register the cron job (runs every 3 hours).
-- Requires pg_cron extension to be enabled (confirmed 2026-06-25).
-- Idempotent: cron.schedule upserts by jobname — safe to re-run.
SELECT cron.schedule(
  'auto-confirm-completed-jobs',
  '0 */3 * * *',
  'SELECT auto_confirm_completed_jobs()'
);
