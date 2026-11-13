-- 0077_help_request_slots_filled.sql
-- APLICADA na BD viva (13/11/2026, confirmado pelo Henrique).
--
-- Testes Android de 13/11, F11: o Descobrir do ajudante mostrava "2 vagas"
-- com uma já preenchida, porque `get_help_requests_in_radius` só devolvia
-- `slots_needed`. Passa a devolver também `slots_filled` (candidaturas
-- aceites) e a app mostra as vagas que faltam.
--
-- O RETURNS TABLE muda de forma: DROP explícito antes de recriar. O corpo é
-- o da 0074, sem outras mudanças. A app aceita a resposta antiga (sem a
-- coluna nova, conta 0 preenchidas), por isso a ordem app/migration é livre.
-- Pode correr duas vezes.

DROP FUNCTION IF EXISTS public.get_help_requests_in_radius(double precision, double precision, integer);

CREATE FUNCTION public.get_help_requests_in_radius(worker_lat double precision, worker_lng double precision, radius_km integer)
 RETURNS TABLE(id uuid, job_id uuid, proposal_id uuid, slots_needed integer, status text, equipment_required boolean, created_post_confirmation boolean, created_at timestamp with time zone, location_lat double precision, location_lng double precision, service_type_id uuid, principal_name text, principal_avatar_url text, payment_per_helper numeric, confirmed_date date, confirmed_time time without time zone, slots_filled integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 0077: + slots_filled (ajudantes já aceites).
  -- 0074: centro e raio do perfil gravado do jardineiro, não dos parâmetros.
  WITH me AS (
    SELECT wp.base_lat::double precision AS lat,
           wp.base_lng::double precision AS lng,
           wp.radius_km                  AS rk
    FROM   public.worker_profiles wp
    JOIN   public.profiles pr ON pr.id = wp.profile_id
                             AND pr.role = 'worker' AND pr.deleted_at IS NULL
    WHERE  wp.profile_id = auth.uid()
  )
  SELECT id, job_id, proposal_id, slots_needed, status, equipment_required,
         created_post_confirmation, created_at,
         round(location_lat::numeric, 2)::double precision,
         round(location_lng::numeric, 2)::double precision,
         service_type_id, principal_name, principal_avatar_url,
         payment_per_helper, confirmed_date, confirmed_time, slots_filled
  FROM (
    SELECT
      hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
      hr.equipment_required, hr.created_post_confirmation, hr.created_at,
      round(jr.location_lat::numeric, 2)::double precision AS location_lat,
      round(jr.location_lng::numeric, 2)::double precision AS location_lng,
      jr.service_type_id, p.full_name AS principal_name,
      p.avatar_url AS principal_avatar_url,
      CASE WHEN hr.equipment_required THEN jp.hourly_rate
           ELSE jp.hourly_rate * 0.7
      END AS payment_per_helper,
      jr.confirmed_date, jr.confirmed_time,
      (SELECT count(*)::integer FROM help_acceptances ha2
        WHERE ha2.help_request_id = hr.id
          AND ha2.status = 'accepted') AS slots_filled,
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((round(jr.location_lat::numeric, 2)::double precision - me.lat) / 2)), 2)
        + cos(radians(me.lat))
          * cos(radians(round(jr.location_lat::numeric, 2)::double precision))
          * power(sin(radians((round(jr.location_lng::numeric, 2)::double precision - me.lng) / 2)), 2)
      ))) AS distance_km,
      LEAST(GREATEST(me.rk, 1), 50)::double precision AS r
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    CROSS JOIN me
    WHERE  hr.status = 'open'
      AND  jr.status = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
      AND  jr.started_at IS NULL
      AND  jr.location_lat BETWEEN me.lat - 51 / 111.0 AND me.lat + 51 / 111.0
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id
          AND ha.worker_id = auth.uid()
          AND ha.status IN ('pending', 'accepted')
      )
  ) t
  WHERE t.distance_km <= t.r
  ORDER BY t.distance_km ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
