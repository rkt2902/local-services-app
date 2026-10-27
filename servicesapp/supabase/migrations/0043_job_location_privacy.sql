-- ============================================================
-- 0043_job_location_privacy.sql
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0042.
--
-- Contexto: decisão do Henrique a 2026-10-16 (review de segurança, S10):
-- até haver proposta aceite, o jardineiro vê só a zona aproximada do
-- pedido, não a morada exata. Antes, qualquer conta com login lia a
-- morada, as coordenadas exatas e a descrição de todos os pedidos abertos
-- do país (policy "Worker vê jobs abertos").
--
-- Quem vê a morada exata e as coordenadas exatas:
--   - o cliente dono do pedido;
--   - o jardineiro da proposta aceite;
--   - os ajudantes aceites desse trabalho.
-- Todos os outros (oportunidade aberta, proposta pendente, candidato a
-- ajudante) recebem `address_text` = localidade (`location_area`) e
-- coordenadas arredondadas a 2 casas decimais (cerca de 1 km).
--
-- Como:
--   1) coluna nova `job_requests.location_area` (localidade, preenchida
--      pela app a partir do reverse geocoding; backfill a partir do último
--      segmento de `address_text`).
--   2) os workers deixam de ler `job_requests` diretamente por RLS, exceto
--      o worker aceite e os ajudantes aceites. O resto passa por RPCs
--      SECURITY DEFINER que devolvem a versão mascarada:
--      `get_job_by_id` (novo, usado pela app em vez do SELECT direto),
--      `get_jobs_in_radius`, `get_worker_job_board`,
--      `get_my_help_acceptances`, `get_help_requests_in_radius`.
--   3) fotos do pedido: visíveis ao cliente, a quem pode ver a oportunidade
--      e agora também ao worker aceite (antes a policy só deixava ver
--      fotos de pedidos `open`, por isso o worker perdia-as depois de
--      confirmado).
--
-- ATENÇÃO: aplicar junto com a versão da app que usa `get_job_by_id`.
-- Uma app antiga, depois desta migration, deixa de conseguir abrir o
-- detalhe de uma oportunidade (o SELECT direto passa a não devolver nada).
--
-- É idempotente.
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- 1. location_area
-- ══════════════════════════════════════════════════════════════

ALTER TABLE job_requests ADD COLUMN IF NOT EXISTS location_area text;

-- A app escreve address_text como "rua, número, código postal, localidade"
-- (GeocodingService). Para os pedidos antigos, a localidade é o último
-- segmento depois da última vírgula.
UPDATE job_requests
SET    location_area = NULLIF(btrim(regexp_replace(address_text, '^.*,', '')), '')
WHERE  location_area IS NULL
  AND  address_text LIKE '%,%';


-- ══════════════════════════════════════════════════════════════
-- 2. Helpers
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.job_area_label(p_location_area text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(NULLIF(btrim(p_location_area), ''), 'Zona aproximada');
$function$;

-- Versão mascarada de uma linha de job_requests (mesmo tipo, só mudam a
-- morada e as coordenadas). jsonb_populate_record mantém todas as outras
-- colunas, seja qual for a ordem/número de colunas da tabela viva.
CREATE OR REPLACE FUNCTION public.mask_job_location(p_job job_requests)
RETURNS job_requests
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT jsonb_populate_record(
    p_job,
    jsonb_build_object(
      'address_text', job_area_label(p_job.location_area),
      'location_lat', round(p_job.location_lat, 2),
      'location_lng', round(p_job.location_lng, 2)
    )
  );
$function$;

-- Cliente, worker aceite ou ajudante aceite deste pedido.
CREATE OR REPLACE FUNCTION public.can_see_exact_job_location(p_job_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   job_requests jr
    LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.id = p_job_id
      AND (
        jr.client_id = auth.uid()
        OR jp.worker_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM   help_requests    hr
          JOIN   help_acceptances ha ON ha.help_request_id = hr.id
          WHERE  hr.job_id    = jr.id
            AND  hr.proposal_id = jr.accepted_proposal_id
            AND  ha.worker_id = auth.uid()
            AND  ha.status    = 'accepted'
        )
      )
  );
$function$;

-- Pode ver a versão mascarada: oportunidade aberta (qualquer worker), ou
-- já tem uma proposta ou uma candidatura de ajudante neste pedido.
CREATE OR REPLACE FUNCTION public.can_see_job_summary(p_job_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM job_requests jr
    WHERE  jr.id = p_job_id
      AND (
        (jr.status = 'open'
          AND EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
          AND NOT (auth.uid() = ANY(jr.excluded_worker_ids)))
        OR EXISTS (
          SELECT 1 FROM job_proposals jp
          WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM   help_requests    hr
          JOIN   help_acceptances ha ON ha.help_request_id = hr.id
          WHERE  hr.job_id = jr.id AND ha.worker_id = auth.uid()
        )
      )
  );
$function$;


-- ══════════════════════════════════════════════════════════════
-- 3. RLS de job_requests
-- ══════════════════════════════════════════════════════════════

-- Lia a morada exata de todos os pedidos abertos.
DROP POLICY IF EXISTS "Worker vê jobs abertos" ON job_requests;

-- Bastava ter uma proposta (mesmo pendente) para ler a morada exata.
DROP POLICY IF EXISTS "Worker ve jobs onde tem proposta" ON job_requests;

-- Fica: o cliente (policy já existente) e quem pode ver a morada exata.
-- Usa o helper SECURITY DEFINER para não haver recursão entre as policies
-- de job_requests e de job_proposals.
DROP POLICY IF EXISTS "Participante aceite vê o job" ON job_requests;
CREATE POLICY "Participante aceite vê o job"
  ON job_requests FOR SELECT TO authenticated
  USING (can_see_exact_job_location(id));


-- ══════════════════════════════════════════════════════════════
-- 4. Fotos do pedido
-- ══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Ver fotos de jobs proprios ou abertos" ON job_photos;
DROP POLICY IF EXISTS "Ver fotos do job"                       ON job_photos;
CREATE POLICY "Ver fotos do job"
  ON job_photos FOR SELECT TO authenticated
  USING (
    can_see_exact_job_location(job_id)
    OR can_see_job_summary(job_id)
  );


-- ══════════════════════════════════════════════════════════════
-- 5. get_job_by_id — substitui o SELECT direto da app
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_job_by_id(p_job_id uuid)
RETURNS SETOF job_requests
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
           WHEN can_see_exact_job_location(jr.id) THEN jr
           ELSE mask_job_location(jr)
         END
  FROM   job_requests jr
  WHERE  jr.id = p_job_id
    AND  (can_see_exact_job_location(jr.id) OR can_see_job_summary(jr.id));
$function$;


-- ══════════════════════════════════════════════════════════════
-- 6. RPCs existentes passam a mascarar (mesmas assinaturas)
-- ══════════════════════════════════════════════════════════════

-- ── 6.1 get_jobs_in_radius (igual à 0042, devolve a versão mascarada;
-- a distância continua calculada com as coordenadas exatas)

CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(
  worker_lat  numeric,
  worker_lng  numeric,
  radius_km   integer,
  p_worker_id uuid DEFAULT NULL
)
RETURNS SETOF job_requests
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT mask_job_location(jr)
  FROM   public.job_requests jr
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((jr.location_lat::double precision - worker_lat::double precision) / 2)), 2)
      + cos(radians(worker_lat::double precision))
        * cos(radians(jr.location_lat::double precision))
        * power(sin(radians((jr.location_lng::double precision - worker_lng::double precision) / 2)), 2)
    ))) AS distance_km
  ) d
  WHERE  jr.status = 'open'
    AND  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  d.distance_km <= LEAST(GREATEST(radius_km, 1), 50)
  ORDER BY d.distance_km ASC;
$function$;

-- ── 6.2 get_worker_job_board (igual à 0035; morada exata só quando a
-- proposta ou a candidatura está aceite)

CREATE OR REPLACE FUNCTION public.get_worker_job_board(
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
  total_count          bigint
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
      jr.updated_at            AS job_updated_at,
      CASE
        WHEN jp.status = 'pending' THEN 'pending'
        WHEN jp.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN jp.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE NULL
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
      jr.updated_at            AS job_updated_at,
      CASE
        WHEN ha.status = 'pending' THEN 'pending'
        WHEN ha.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN ha.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE NULL
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
    status, created_at,
    COUNT(*) OVER ()::bigint AS total_count
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

-- ── 6.3 get_my_help_acceptances (igual ao baseline; morada, coordenadas
-- e telefone do principal só com a candidatura aceite)

CREATE OR REPLACE FUNCTION public.get_my_help_acceptances()
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  service_type_name text,
  principal_name    text,
  job_status        text,
  job_id            uuid,
  principal_worker_id uuid,
  confirmed_date    date,
  confirmed_time    time,
  address_text      text,
  location_lat      numeric,
  location_lng      numeric,
  principal_phone   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.status, ha.agreed_rate, ha.brought_equipment, ha.created_at,
    st.name         AS service_type_name,
    p.full_name     AS principal_name,
    jr.status       AS job_status,
    jr.id           AS job_id,
    jp.worker_id    AS principal_worker_id,
    jr.confirmed_date, jr.confirmed_time,
    CASE WHEN ha.status = 'accepted' THEN jr.address_text
         ELSE job_area_label(jr.location_area) END,
    CASE WHEN ha.status = 'accepted' THEN jr.location_lat
         ELSE round(jr.location_lat, 2) END,
    CASE WHEN ha.status = 'accepted' THEN jr.location_lng
         ELSE round(jr.location_lng, 2) END,
    CASE WHEN ha.status = 'accepted' THEN p.phone ELSE NULL END AS principal_phone
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER  BY ha.created_at DESC;
$function$;

-- ── 6.4 get_help_requests_in_radius (igual à 0042; coordenadas
-- arredondadas, distância calculada com as exatas)

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
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
  principal_name            text,
  principal_avatar_url      text,
  payment_per_helper        numeric,
  confirmed_date            date,
  confirmed_time            time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT id, job_id, proposal_id, slots_needed, status, equipment_required,
         created_post_confirmation, created_at,
         round(location_lat::numeric, 2)::double precision,
         round(location_lng::numeric, 2)::double precision,
         service_type_id, principal_name, principal_avatar_url,
         payment_per_helper, confirmed_date, confirmed_time
  FROM (
    SELECT
      hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
      hr.equipment_required, hr.created_post_confirmation, hr.created_at,
      jr.location_lat::double precision AS location_lat,
      jr.location_lng::double precision AS location_lng,
      jr.service_type_id, p.full_name AS principal_name,
      p.avatar_url AS principal_avatar_url,
      CASE WHEN hr.equipment_required THEN jp.hourly_rate
           ELSE jp.hourly_rate * 0.7
      END AS payment_per_helper,
      jr.confirmed_date, jr.confirmed_time,
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))) AS distance_km
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    WHERE  hr.status = 'open'
      AND  jr.status NOT IN ('cancelled', 'completed')
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid()
      )
  ) t
  WHERE t.distance_km <= LEAST(GREATEST(radius_km, 1), 50)
  ORDER BY t.distance_km ASC;
$function$;

-- ── 6.5 cancel_job (igual à 0042; o pedido reaberto copia location_area)

CREATE OR REPLACE FUNCTION public.cancel_job(
  p_job_id              uuid,
  p_reason              text,
  p_reason_detail       text    DEFAULT NULL,
  p_client_wants_reopen boolean DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job           job_requests%ROWTYPE;
  v_caller_id     uuid    := auth.uid();
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
  v_can_reopen    boolean := false;
  v_new_excluded  uuid[];
  v_new_job_id    uuid    := NULL;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed') THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser cancelado no estado atual.';
  END IF;

  v_is_client := (v_job.client_id = v_caller_id);
  v_is_worker := v_job.status = 'confirmed' AND EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  id = v_job.accepted_proposal_id AND worker_id = v_caller_id
  );

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente ou o jardineiro do trabalho podem cancelar.';
  END IF;

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

  UPDATE help_requests
  SET    status = 'cancelled'
  WHERE  job_id = p_job_id AND status <> 'cancelled';

  UPDATE help_acceptances
  SET    status = 'rejected'
  WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = p_job_id)
    AND  status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado.',
         p_job_id, 'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id = p_job_id AND ha.status = 'accepted';

  IF v_other_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_other_user_id, 'job_cancelled', 'Pedido cancelado',
      'Um pedido foi cancelado.', p_job_id, 'job_request');
  END IF;

  IF v_can_reopen THEN
    v_new_excluded := v_job.excluded_worker_ids;
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id, service_type_id, address_text,
      location_lat, location_lng,
      date_mode, preferred_date, availability_text,
      urgency, size_estimate, description, location_area,
      status, reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id, v_job.service_type_id, v_job.address_text,
      v_job.location_lat, v_job.location_lng,
      v_job.date_mode, v_job.preferred_date, v_job.availability_text,
      v_job.urgency, v_job.size_estimate, v_job.description, v_job.location_area,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded, now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto',
        'O pedido foi reaberto automaticamente.', v_new_job_id, 'job_request');
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$function$;


-- ══════════════════════════════════════════════════════════════
-- 7. Permissões (regra da 0042)
-- ══════════════════════════════════════════════════════════════

DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.job_area_label(text)',
    'public.mask_job_location(job_requests)',
    'public.can_see_exact_job_location(uuid)',
    'public.can_see_job_summary(uuid)',
    'public.get_job_by_id(uuid)',
    'public.get_jobs_in_radius(numeric,numeric,integer,uuid)',
    'public.get_worker_job_board(text,integer,integer)',
    'public.get_my_help_acceptances()',
    'public.get_help_requests_in_radius(double precision,double precision,integer)',
    'public.cancel_job(uuid,text,text,boolean)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select policyname from pg_policies where tablename = 'job_requests' and cmd = 'SELECT';
--   -- esperado: "Client vê os seus jobs" e "Participante aceite vê o job"
-- select count(*) filter (where location_area is null) as sem_zona, count(*) from job_requests;
