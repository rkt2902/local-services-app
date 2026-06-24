-- Migration 0006: Extend get_help_requests_in_radius to return job context.
--
-- The original function returns SETOF help_requests (bare table rows).  The
-- candidate-worker discovery screen additionally needs the job's geographic
-- location (for client-side distance calculation), service_type_id (for the
-- card header), and the principal worker's display name.
--
-- The RPC already joins job_requests for the Haversine filter, so adding
-- location / service_type_id is free.  principal_name requires two extra joins
-- (job_proposals → profiles).
--
-- PostgreSQL does NOT allow CREATE OR REPLACE to change a function's return
-- type, so we must DROP first.
--
-- Dart impact: HelpRequest.fromJson ignores unknown JSON keys, so existing
-- callers of the old RPC (fetchHelpRequestsInRadius) are unaffected.
-- The new HelpRequestSummary.fromJson reads the extra columns.

DROP FUNCTION IF EXISTS get_help_requests_in_radius(double precision, double precision, integer);

CREATE FUNCTION get_help_requests_in_radius(
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
