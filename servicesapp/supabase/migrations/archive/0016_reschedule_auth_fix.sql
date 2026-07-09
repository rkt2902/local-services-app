-- ==============================================================
-- supabase/migrations/0016_reschedule_auth_fix.sql
--
-- Two confirmed security gaps fixed (verified via live DB snapshot
-- schema_snapshot_2026-06-26.csv, not inferred from migration files):
--
-- FIX 1 (P-8-4) — reject_reschedule missing party authorization
--   The live body only checked that the caller is not the proposer
--   (reschedule_proposed_by = v_user_id) but never verified the caller
--   is the client or the accepted worker of the job.  Anyone authenticated
--   who knew the job_id and was not the proposer could reject a pending
--   reschedule on any job.
--
--   propose_reschedule and accept_reschedule were already fixed
--   interactively in the live DB (confirmed via snapshot); their pattern
--   (v_is_client / v_is_worker / if not (v_is_client or v_is_worker))
--   is copied here verbatim.
--
-- FIX 2 (P-FA4) — job_proposals UPDATE missing WITH CHECK
--   The "Worker atualiza as suas propostas" policy had USING
--   (auth.uid() = worker_id) but no WITH CHECK clause, which meant a
--   worker could SET any column to any value via the REST API (bypassing
--   RPCs).  The fix adds WITH CHECK restricting direct updates to only
--   the 'superseded' status transition, matching what withdraw_proposal
--   does.  All other mutations (accepted/rejected) go through SECURITY
--   DEFINER RPCs that bypass RLS anyway and are unaffected.
-- ==============================================================

-- ── FIX 1: reject_reschedule — add party authorization check ─────────
CREATE OR REPLACE FUNCTION public.reject_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_job public.job_requests;
  v_is_client boolean;
  v_is_worker boolean;
  v_proposer_id uuid;
begin
  select * into v_job from public.job_requests where id = p_job_id;
  if v_job is null or v_job.reschedule_status != 'pending' then
    raise exception 'Sem remarcação pendente';
  end if;

  v_is_client := (v_job.client_id = v_user_id);
  select exists(
    select 1 from public.job_proposals
    where id = v_job.accepted_proposal_id and worker_id = v_user_id
  ) into v_is_worker;

  if v_job.reschedule_proposed_by = v_user_id then
    raise exception 'Não pode recusar a sua própria remarcação';
  end if;

  if not (v_is_client or v_is_worker) then
    raise exception 'Não autorizado';
  end if;

  v_proposer_id := v_job.reschedule_proposed_by;

  update public.job_requests
    set reschedule_proposed_date     = null,
        reschedule_proposed_time     = null,
        reschedule_proposed_flexible = null,
        reschedule_proposed_by       = null,
        reschedule_status            = 'rejected',
        updated_at                   = now()
    where id = p_job_id;

  insert into public.notifications (user_id, type, title, body, related_id, related_type)
  values (v_proposer_id, 'reschedule_rejected', 'Remarcação recusada',
    'A nova data foi recusada. Mantém-se a data original.',
    p_job_id, 'job_request');
end;
$function$;


-- ── FIX 2: job_proposals UPDATE — add WITH CHECK ─────────────────────
DROP POLICY IF EXISTS "Worker atualiza as suas propostas" ON job_proposals;

CREATE POLICY "Worker atualiza as suas propostas"
  ON job_proposals
  FOR UPDATE
  TO authenticated
  USING     (auth.uid() = worker_id)
  WITH CHECK (auth.uid() = worker_id AND status = 'superseded');
