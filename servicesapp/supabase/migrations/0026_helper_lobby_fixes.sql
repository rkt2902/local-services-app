-- ==============================================================
-- supabase/migrations/0026_helper_lobby_fixes.sql
-- 3 confirmed bugs in the helper-request area (2026-06-29).
--
-- 1+2. Add missing SELECT policy for the principal worker on
--      help_requests (documented gap C3.2 in database_schema.md).
--      Absence caused two distinct failures:
--      (a) createHelpRequest() threw a Dart exception: the INSERT
--          itself succeeds (WITH CHECK passes for accepted proposals)
--          but the chained .select('id').single() (RETURNING) is
--          blocked by the missing SELECT policy — the row IS written
--          to the DB, Dart sees an empty-result exception.
--      (b) WorkerHelpRequestsLobbyScreen showed "Nenhuma vaga":
--          fetchHelpRequestsForJob() is a direct PostgREST SELECT
--          on help_requests; without a SELECT policy the principal
--          always gets 0 rows even when rows exist.
--
-- 3. Add NOT EXISTS exclusion to get_help_requests_in_radius so a
--    worker who already has a help_acceptance row (any status) on a
--    help_request no longer sees that request in the discovery list.
--    Listed as improvement A2 (Fase 9 audit, improvements.md) since
--    the original Fase 9 session — never implemented in any
--    subsequent migration, not a regression.
--
-- IMPORTANT: written but NOT applied to the live DB.
-- Apply manually via the Supabase SQL Editor.
-- ==============================================================


-- ── 1+2. Missing SELECT policy: principal worker on help_requests ─────────────
--
-- Pre-flight note: existing SELECT policies on this table are:
--   "Cliente vê help requests pendentes de aprovação" (0003)
--     → client-only, pending_approval status only
--   "Worker candidato vê help requests onde se candidatou" (0012)
--     → candidate workers with a help_acceptance row
-- Neither covers the principal. No duplicate risk.

CREATE POLICY "Worker principal vê os seus help requests"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE job_proposals.id        = help_requests.proposal_id
        AND job_proposals.worker_id = auth.uid()
    )
  );


-- ── 3. get_help_requests_in_radius — add NOT EXISTS exclusion ─────────────────
--
-- Only change vs. migration 0007: the NOT EXISTS clause in the WHERE block.
-- All other parts (signature, RETURNS TABLE shape, SELECT list, JOINs, distance
-- formula, ORDER BY) are reproduced verbatim from 0007 to avoid unintended drift.

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
    AND NOT EXISTS (
      SELECT 1 FROM help_acceptances ha
      WHERE ha.help_request_id = hr.id
        AND ha.worker_id       = auth.uid()
    )
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
