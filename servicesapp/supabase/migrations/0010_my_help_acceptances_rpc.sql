-- ==============================================================
-- supabase/migrations/0010_my_help_acceptances_rpc.sql
-- New RPC: get_my_help_acceptances()
--
-- Returns all help_acceptances for the calling worker (auth.uid()),
-- joined with the service type name, principal worker's display name,
-- and the job's current status.  Used by the "As minhas candidaturas"
-- tab on the worker help-requests discovery screen.
--
-- Approach rationale (mirrors 0006/HelpRequestSummary):
--   Client-side PostgREST embedded joins were considered but ruled out.
--   The join path job_proposals.worker_id → worker_profiles.profile_id →
--   profiles.id is a two-hop FK that PostgREST resolves via the intermediate
--   worker_profiles table, making the embedded select syntax fragile when
--   the schema evolves.  SECURITY DEFINER RPCs are the established pattern
--   for joined reads in this project.
-- ==============================================================

CREATE FUNCTION get_my_help_acceptances()
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  service_type_name text,
  principal_name    text,
  job_status        text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    ha.id,
    ha.help_request_id,
    ha.status,
    ha.agreed_rate,
    ha.brought_equipment,
    ha.created_at,
    st.name       AS service_type_name,
    p.full_name   AS principal_name,
    jr.status     AS job_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER BY ha.created_at DESC;
$$;
