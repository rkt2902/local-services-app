-- ══════════════════════════════════════════════════════════════
-- 0056 — Total estimado com a equipa no quadro do jardineiro
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0053
-- (redefine get_worker_job_board a partir da versão da 0053). Pode
-- correr-se mais do que uma vez sem erro.
--
-- get_worker_job_board passa a devolver também people_needed e
-- helpers_equipment_required da proposta, para "Os meus trabalhos" mostrar
-- o mesmo total estimado (equipa incluída) que os outros ecrãs. Nas linhas
-- de ajudante vêm 1 e false: o ajudante vê o seu próprio valor acordado.
--
-- RETURNS TABLE muda de forma: DROP explícito antes de recriar.
-- ══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_worker_job_board(text, integer, integer);

CREATE FUNCTION public.get_worker_job_board(
  p_tab       text,
  p_page      integer DEFAULT 0,
  p_page_size integer DEFAULT 20
)
RETURNS TABLE(
  entry_id             uuid,
  role                 text,
  job_id               uuid,
  service_type_name    text,
  person_name          text,
  address_text         text,
  preferred_date       date,
  confirmed_date       date,
  confirmed_time       time,
  confirmed_flexible   boolean,
  hourly_rate          numeric,
  estimated_hours_min  numeric,
  estimated_hours_max  numeric,
  agreed_rate          numeric,
  status               text,
  created_at           timestamptz,
  job_status           text,
  total_count          bigint,
  service_type_id      uuid,
  location_area        text,
  marked_done_at       timestamptz,
  cancel_reason        text,
  cancelled_by_client  boolean,
  cancelled_by_me      boolean,
  job_updated_at       timestamptz,
  started_at           timestamptz,
  people_needed        integer,
  helpers_equipment_required boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH combined AS (
    -- Fonte A: papel de responsável (job_proposals)
    SELECT
      jp.id                    AS entry_id,
      'responsible'::text      AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      cp.full_name             AS person_name,
      CASE WHEN jp.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      jr.preferred_date        AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      jp.hourly_rate           AS hourly_rate,
      jp.estimated_hours_min   AS estimated_hours_min,
      jp.estimated_hours_max   AS estimated_hours_max,
      NULL::numeric            AS agreed_rate,
      jp.status                AS status,
      jp.created_at            AS created_at,
      jr.status                AS job_status,
      GREATEST(jr.updated_at, jp.updated_at) AS job_updated_at,
      jr.service_type_id       AS service_type_id,
      public.job_area_label(jr.location_area) AS location_area,
      jr.marked_done_at        AS marked_done_at,
      jr.cancel_reason         AS cancel_reason,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = jr.client_id) AS cancelled_by_client,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = auth.uid())   AS cancelled_by_me,
      jr.started_at            AS started_at,
      jp.people_needed         AS people_needed,
      jp.helpers_equipment_required AS helpers_equipment_required,
      CASE
        WHEN jp.status = 'pending' AND jr.status = 'open' THEN 'pending'
        WHEN jp.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN jp.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'completed'
      END AS bucket
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    JOIN   service_types st ON st.id = jr.service_type_id
    JOIN   profiles      cp ON cp.id = jr.client_id
    WHERE  jp.worker_id = auth.uid()

    UNION ALL

    -- Fonte B: papel de ajudante (help_acceptances)
    SELECT
      ha.id                    AS entry_id,
      'helper'::text           AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      pp.full_name             AS person_name,
      CASE WHEN ha.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      NULL::date               AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      NULL::numeric            AS hourly_rate,
      NULL::numeric            AS estimated_hours_min,
      NULL::numeric            AS estimated_hours_max,
      ha.agreed_rate           AS agreed_rate,
      ha.status                AS status,
      ha.created_at            AS created_at,
      jr.status                AS job_status,
      jr.updated_at            AS job_updated_at,
      jr.service_type_id       AS service_type_id,
      public.job_area_label(jr.location_area) AS location_area,
      jr.marked_done_at        AS marked_done_at,
      jr.cancel_reason         AS cancel_reason,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = jr.client_id) AS cancelled_by_client,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = auth.uid())   AS cancelled_by_me,
      jr.started_at            AS started_at,
      1                        AS people_needed,
      false                    AS helpers_equipment_required,
      CASE
        WHEN ha.status = 'pending' THEN 'pending'
        WHEN ha.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN ha.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'completed'
      END AS bucket
    FROM   help_acceptances ha
    JOIN   help_requests hr  ON hr.id = ha.help_request_id
    JOIN   job_requests  jr  ON jr.id = hr.job_id
    JOIN   service_types st  ON st.id = jr.service_type_id
    JOIN   job_proposals jpp ON jpp.id = hr.proposal_id
    JOIN   profiles      pp  ON pp.id  = jpp.worker_id
    WHERE  ha.worker_id = auth.uid()
  )
  SELECT
    entry_id, role, job_id, service_type_name, person_name, address_text,
    preferred_date, confirmed_date, confirmed_time, confirmed_flexible,
    hourly_rate, estimated_hours_min, estimated_hours_max, agreed_rate,
    status, created_at, job_status,
    COUNT(*) OVER ()::bigint AS total_count,
    service_type_id, location_area, marked_done_at, cancel_reason,
    cancelled_by_client, cancelled_by_me, job_updated_at, started_at,
    people_needed, helpers_equipment_required
  FROM combined
  WHERE bucket = p_tab
  ORDER BY
    CASE WHEN p_tab = 'scheduled' THEN confirmed_date END ASC NULLS LAST,
    CASE WHEN p_tab = 'scheduled' THEN confirmed_time END ASC NULLS LAST,
    CASE WHEN p_tab = 'completed' THEN job_updated_at END DESC NULLS LAST,
    CASE WHEN p_tab = 'pending'   THEN created_at     END DESC NULLS LAST,
    entry_id
  LIMIT p_page_size OFFSET (p_page * p_page_size);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) TO authenticated, service_role;


NOTIFY pgrst, 'reload schema';
