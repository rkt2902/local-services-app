-- ============================================================
-- 0022_helper_logistics.sql  — RC3 fix (Revisão conceptual 2026-06-27)
-- Exposes job logistics to accepted helpers via
-- get_my_help_acceptances(): confirmed_date, confirmed_time,
-- address_text, location_lat, location_lng, principal_phone.
-- Apply manually via Supabase SQL Editor.
-- Must DROP first: CREATE OR REPLACE cannot change the RETURNS TABLE
-- column set (same pattern as migration 0021).
-- ============================================================

DROP FUNCTION IF EXISTS get_my_help_acceptances();

CREATE FUNCTION get_my_help_acceptances()
RETURNS TABLE(
  id                  uuid,
  help_request_id     uuid,
  status              text,
  agreed_rate         numeric,
  brought_equipment   boolean,
  created_at          timestamptz,
  service_type_name   text,
  principal_name      text,
  job_status          text,
  job_id              uuid,
  principal_worker_id uuid,
  confirmed_date      date,
  confirmed_time      time,
  address_text        text,
  location_lat        numeric,
  location_lng        numeric,
  principal_phone     text
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
    st.name              AS service_type_name,
    p.full_name          AS principal_name,
    jr.status            AS job_status,
    jr.id                AS job_id,
    jp.worker_id         AS principal_worker_id,
    jr.confirmed_date    AS confirmed_date,
    jr.confirmed_time    AS confirmed_time,
    jr.address_text      AS address_text,
    jr.location_lat      AS location_lat,
    jr.location_lng      AS location_lng,
    p.phone              AS principal_phone
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER BY ha.created_at DESC;
$$;
