-- ══════════════════════════════════════════════════════════════
-- 0044 — RPCs sem id do utilizador vindo da app + performance das policies
-- ══════════════════════════════════════════════════════════════
--
-- Pontos que ficaram de fora do review de 2026-10-16 (ver
-- /mnt/project-files/projardim/review/2026-10-16-review-codigo.md):
--
-- 1. create_proposal, get_jobs_in_radius e sync_worker_service_types
--    deixam de receber p_worker_id. A identidade vem só de auth.uid()
--    (regra do projeto). As versões antigas são apagadas com DROP
--    explícito porque a assinatura muda.
-- 2. P4: nas policies do schema public, auth.uid() passa a
--    (SELECT auth.uid()), para o Postgres o avaliar uma vez por query em
--    vez de uma vez por linha.
-- 3. P4: get_jobs_in_radius e get_help_requests_in_radius pré-filtram por
--    uma caixa de lat/lng antes do cálculo de distância, com um índice
--    parcial sobre os pedidos abertos.
--
-- APLICAR JUNTO COM A APP NOVA: a app antiga envia p_worker_id e deixa
-- de conseguir enviar propostas, ver oportunidades e guardar serviços.
-- Pode ser aplicada várias vezes sem erro.
-- ══════════════════════════════════════════════════════════════


-- ── 1. create_proposal sem p_worker_id ──────────────────────────

DROP FUNCTION IF EXISTS public.create_proposal(
  uuid, uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean
);

CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_hourly_rate                numeric,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job         job_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM worker_profiles WHERE profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Só jardineiros podem enviar propostas.';
  END IF;

  IF p_hourly_rate IS NULL OR p_hourly_rate <= 0 THEN
    RAISE EXCEPTION 'O preço por hora tem de ser maior que zero.';
  END IF;

  IF p_people_needed IS NULL OR p_people_needed < 1 THEN
    RAISE EXCEPTION 'Número de pessoas inválido.';
  END IF;

  SELECT * INTO v_job
  FROM   job_requests
  WHERE  id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;
  IF v_job.client_id = auth.uid() THEN
    RAISE EXCEPTION 'Não podes enviar proposta para o teu próprio pedido.';
  END IF;
  IF auth.uid() = ANY(v_job.excluded_worker_ids) THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    status
  ) VALUES (
    p_job_id, auth.uid(), p_hourly_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
    'pending'
  )
  RETURNING id INTO v_proposal_id;

  UPDATE job_requests
  SET proposal_count = proposal_count + 1,
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'proposal_received',
    'Nova proposta recebida',
    'Um jardineiro enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$function$;


-- ── 2. sync_worker_service_types sem p_worker_id ────────────────

DROP FUNCTION IF EXISTS public.sync_worker_service_types(uuid, uuid[]);

CREATE OR REPLACE FUNCTION public.sync_worker_service_types(
  p_service_type_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM worker_profiles WHERE profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  DELETE FROM worker_service_types WHERE worker_id = auth.uid();
  IF COALESCE(array_length(p_service_type_ids, 1), 0) > 0 THEN
    INSERT INTO worker_service_types (worker_id, service_type_id)
    SELECT DISTINCT auth.uid(), unnest(p_service_type_ids);
  END IF;
END;
$function$;


-- ── 3. get_jobs_in_radius sem p_worker_id, com caixa de lat/lng ──
-- Igual à 0043 (devolve a versão mascarada). A caixa deixa o índice
-- parcial cortar os pedidos longe antes do cálculo de distância.

DROP FUNCTION IF EXISTS public.get_jobs_in_radius(numeric, numeric, integer, uuid);

CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(
  worker_lat  numeric,
  worker_lng  numeric,
  radius_km   integer
)
RETURNS SETOF job_requests
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH box AS (
    SELECT LEAST(GREATEST(radius_km, 1), 50)::double precision AS r,
           worker_lat::double precision AS lat,
           worker_lng::double precision AS lng
  )
  SELECT mask_job_location(jr)
  FROM   box b
  JOIN   public.job_requests jr
    ON   jr.status = 'open'
   AND   jr.location_lat BETWEEN b.lat - b.r / 111.0 AND b.lat + b.r / 111.0
   AND   jr.location_lng BETWEEN b.lng - b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
                             AND b.lng + b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((jr.location_lat::double precision - b.lat) / 2)), 2)
      + cos(radians(b.lat))
        * cos(radians(jr.location_lat::double precision))
        * power(sin(radians((jr.location_lng::double precision - b.lng) / 2)), 2)
    ))) AS distance_km
  ) d
  WHERE  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  d.distance_km <= b.r
  ORDER BY d.distance_km ASC;
$function$;


-- ── 4. get_help_requests_in_radius com a mesma caixa ────────────
-- Assinatura e resultado iguais à 0043.

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
      ))) AS distance_km,
      LEAST(GREATEST(radius_km, 1), 50)::double precision AS r
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    WHERE  hr.status = 'open'
      AND  jr.status NOT IN ('cancelled', 'completed')
      AND  jr.location_lat BETWEEN worker_lat - 50 / 111.0 AND worker_lat + 50 / 111.0
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid()
      )
  ) t
  WHERE t.distance_km <= t.r
  ORDER BY t.distance_km ASC;
$function$;


-- ── 5. Índice parcial para a caixa de lat/lng ───────────────────

CREATE INDEX IF NOT EXISTS idx_job_requests_open_location
  ON job_requests (location_lat, location_lng) WHERE status = 'open';


-- ── 6. P4: (SELECT auth.uid()) nas policies do schema public ────
-- Reescreve cada policy a partir do texto que está na BD (pg_policies),
-- por isso apanha exatamente as policies que existem, sem as recriar.
-- As que já usam (SELECT auth.uid()) ficam iguais.
--
-- job_requests fica de fora: a policy de INSERT consulta profiles, e uma
-- policy de profiles consulta job_requests. Com um (SELECT ...) nas
-- policies de SELECT de job_requests, o Postgres acusa recursão infinita
-- ao criar um pedido. A verificação no fim (secção 8) aborta a migration
-- inteira se aparecer outra recursão destas.

DO $$
DECLARE
  pol    record;
  v_qual text;
  v_chk  text;
  v_sql  text;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM   pg_policies
    WHERE  schemaname = 'public'
      AND  tablename <> 'job_requests'
      AND  (qual ~ 'auth\.uid\(\)' OR with_check ~ 'auth\.uid\(\)')
  LOOP
    v_qual := pol.qual;
    v_chk  := pol.with_check;

    IF v_qual IS NOT NULL THEN
      v_qual := replace(v_qual, '( SELECT auth.uid() AS uid)', '#UID#');
      v_qual := replace(v_qual, 'auth.uid()', '(SELECT auth.uid())');
      v_qual := replace(v_qual, '#UID#', '(SELECT auth.uid())');
    END IF;
    IF v_chk IS NOT NULL THEN
      v_chk := replace(v_chk, '( SELECT auth.uid() AS uid)', '#UID#');
      v_chk := replace(v_chk, 'auth.uid()', '(SELECT auth.uid())');
      v_chk := replace(v_chk, '#UID#', '(SELECT auth.uid())');
    END IF;

    v_sql := format('ALTER POLICY %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);
    IF v_qual IS NOT NULL THEN
      v_sql := v_sql || format(' USING (%s)', v_qual);
    END IF;
    IF v_chk IS NOT NULL THEN
      v_sql := v_sql || format(' WITH CHECK (%s)', v_chk);
    END IF;
    EXECUTE v_sql;
  END LOOP;
END;
$$;


-- ── 7. Permissões (regra desde a 0042) ──────────────────────────

REVOKE EXECUTE ON FUNCTION public.create_proposal(
  uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_proposal(
  uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean
) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.sync_worker_service_types(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_worker_service_types(uuid[]) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) TO authenticated, service_role;

-- ── 8. Verificação de recursão nas policies ─────────────────────
-- Faz EXPLAIN (não executa nada) de SELECT, INSERT, UPDATE e DELETE em
-- cada tabela e view do public como 'authenticated'. Se alguma der
-- "infinite recursion", a migration falha e nada fica aplicado.

DO $$
DECLARE
  r     record;
  v_col text;
  v_sql text;
  v_bad text := '';
BEGIN
  FOR r IN
    SELECT c.relname, c.relkind
    FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public' AND c.relkind IN ('r', 'v')
  LOOP
    SELECT attname INTO v_col
    FROM   pg_attribute
    WHERE  attrelid = format('public.%I', r.relname)::regclass
      AND  attnum > 0 AND NOT attisdropped
    ORDER  BY attnum LIMIT 1;

    FOREACH v_sql IN ARRAY CASE WHEN r.relkind = 'r' THEN ARRAY[
      format('SELECT * FROM public.%I', r.relname),
      format('INSERT INTO public.%I SELECT * FROM public.%I WHERE false RETURNING *', r.relname, r.relname),
      format('UPDATE public.%I SET %I = %I RETURNING *', r.relname, v_col, v_col),
      format('DELETE FROM public.%I RETURNING *', r.relname)
    ] ELSE ARRAY[format('SELECT * FROM public.%I', r.relname)] END
    LOOP
      BEGIN
        SET LOCAL ROLE authenticated;
        EXECUTE 'EXPLAIN ' || v_sql;
        RESET ROLE;
      EXCEPTION WHEN OTHERS THEN
        -- o subbloco desfaz o SET ROLE
        IF SQLERRM ILIKE '%infinite recursion%' THEN
          v_bad := v_bad || E'\n' || v_sql || ': ' || SQLERRM;
        END IF;
      END;
    END LOOP;
  END LOOP;

  IF v_bad <> '' THEN
    RAISE EXCEPTION 'Recursão nas policies, migration cancelada:%', v_bad;
  END IF;
END;
$$;


NOTIFY pgrst, 'reload schema';


-- ── Verificação (correr à parte depois de aplicar) ──────────────
-- 1. Nenhuma das 3 RPCs recebe p_worker_id (deve dar 0 linhas):
--   select proname, pg_get_function_identity_arguments(oid)
--   from pg_proc
--   where proname in ('create_proposal','get_jobs_in_radius','sync_worker_service_types')
--     and pg_get_function_identity_arguments(oid) like '%p_worker_id%';
-- 2. Policies do public com auth.uid() por linha (deve dar 2, as de
--    job_requests, que ficam de fora de propósito):
--   select count(*) from pg_policies
--   where schemaname = 'public'
--     and regexp_replace(coalesce(qual,'') || coalesce(with_check,''),
--                        '\( SELECT auth\.uid\(\) AS uid\)', '', 'g') ~ 'auth\.uid\(\)';
