-- ══════════════════════════════════════════════════════════════
-- 0084 — Consumo de combustível do Profissional
-- ══════════════════════════════════════════════════════════════
--
-- CRIADA, NÃO APLICADA. Aplicar à mão no SQL Editor do Supabase.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. fuel_types: os tipos de combustível que a app mostra (Gasóleo,
--      Gasolina, Óleo 2 tempos, Óleo de corrente). A lista vem daqui e
--      não fica fixa no código; para tirar um tipo, active = false.
--   2. worker_fuel_usage: litros por mês de cada tipo, por Profissional.
--      Opcional, pedido no passo 2 do registo e no Perfil. Serve para
--      estatística agregada (negociar com parceiros, cartão frota); não
--      aparece no perfil público.
--   3. get_my_fuel_usage e set_my_fuel_usage: a app lê e grava só as
--      suas linhas. set_* substitui tudo de uma vez (lista vazia limpa).
--
-- Regras de sempre: quem chama é auth.uid(); nenhuma RPC recebe
-- worker_id/client_id/user_id.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Tipos de combustível ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.fuel_types (
  id          text        PRIMARY KEY,
  name        text        NOT NULL,
  -- 'pump' (bomba) ou 'drop' (gota): o ícone do chip na app.
  icon        text        NOT NULL DEFAULT 'pump' CHECK (icon IN ('pump', 'drop')),
  sort_order  integer     NOT NULL DEFAULT 0,
  active      boolean     NOT NULL DEFAULT true
);

ALTER TABLE public.fuel_types ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fuel_types FROM anon, authenticated;
GRANT SELECT ON public.fuel_types TO authenticated;

DROP POLICY IF EXISTS "Tipos de combustível: leitura" ON public.fuel_types;
CREATE POLICY "Tipos de combustível: leitura"
  ON public.fuel_types FOR SELECT TO authenticated
  USING (active);

-- Os dois óleos estão por confirmar com o Henrique (25/11/2026).
INSERT INTO public.fuel_types (id, name, icon, sort_order) VALUES
  ('diesel',     'Gasóleo',          'pump', 1),
  ('petrol',     'Gasolina',         'pump', 2),
  ('oil_2t',     'Óleo 2 tempos',    'drop', 3),
  ('chain_oil',  'Óleo de corrente', 'drop', 4)
ON CONFLICT (id) DO NOTHING;


-- ── 2. Consumo por Profissional ─────────────────────────────────

CREATE TABLE IF NOT EXISTS public.worker_fuel_usage (
  worker_id         uuid          NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  fuel_type_id      text          NOT NULL REFERENCES public.fuel_types(id),
  liters_per_month  numeric(7,1)  NOT NULL CHECK (liters_per_month > 0 AND liters_per_month <= 10000),
  updated_at        timestamptz   NOT NULL DEFAULT now(),
  PRIMARY KEY (worker_id, fuel_type_id)
);

-- Sem acesso direto: só pelas RPCs abaixo (e pelo painel de admin).
ALTER TABLE public.worker_fuel_usage ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.worker_fuel_usage FROM anon, authenticated;


-- ── 3. RPCs da app ──────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_my_fuel_usage();
CREATE FUNCTION public.get_my_fuel_usage()
RETURNS TABLE(fuel_type_id text, liters_per_month numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT u.fuel_type_id, u.liters_per_month
  FROM worker_fuel_usage u
  JOIN fuel_types t ON t.id = u.fuel_type_id
  WHERE u.worker_id = auth.uid()
  ORDER BY t.sort_order;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_fuel_usage() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_fuel_usage() TO authenticated, service_role;


-- p_items: [{"fuel_type_id": "diesel", "liters_per_month": 60}, ...]
DROP FUNCTION IF EXISTS public.set_my_fuel_usage(jsonb);
CREATE FUNCTION public.set_my_fuel_usage(p_items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND role = 'worker') THEN
    RAISE EXCEPTION 'not_a_worker' USING ERRCODE = '42501';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'invalid_items' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 10 THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;

  DELETE FROM worker_fuel_usage WHERE worker_id = v_uid;

  -- Um tipo repetido ou inexistente, ou litros fora do intervalo, falham
  -- pela chave primária, pela FK ou pelo CHECK, e nada fica gravado.
  INSERT INTO worker_fuel_usage (worker_id, fuel_type_id, liters_per_month)
  SELECT v_uid,
         i->>'fuel_type_id',
         round((i->>'liters_per_month')::numeric, 1)
  FROM jsonb_array_elements(p_items) AS i;

  IF EXISTS (
    SELECT 1 FROM worker_fuel_usage u
    JOIN fuel_types t ON t.id = u.fuel_type_id
    WHERE u.worker_id = v_uid AND NOT t.active
  ) THEN
    RAISE EXCEPTION 'inactive_fuel_type' USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_my_fuel_usage(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_fuel_usage(jsonb) TO authenticated, service_role;


-- ── 4. Painel de admin: estatísticas para parceiros ─────────────
--
-- Distrito aproximado: a capital de distrito mais próxima da base do
-- Profissional (não há distrito gravado no perfil). Perto das fronteiras
-- entre distritos pode falhar; serve para estatística, não para moradas.

CREATE OR REPLACE FUNCTION public.approx_district(p_lat double precision, p_lng double precision)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_lat IS NULL OR p_lng IS NULL OR (p_lat = 0 AND p_lng = 0) THEN NULL
    WHEN p_lng < -20 THEN 'Açores'
    WHEN p_lat < 34  THEN 'Madeira'
    ELSE (
      SELECT d.name
      FROM (VALUES
        ('Aveiro', 40.6405, -8.6538), ('Beja', 38.0151, -7.8632),
        ('Braga', 41.5454, -8.4265), ('Bragança', 41.8061, -6.7567),
        ('Castelo Branco', 39.8222, -7.4909), ('Coimbra', 40.2033, -8.4103),
        ('Évora', 38.5714, -7.9135), ('Faro', 37.0194, -7.9322),
        ('Guarda', 40.5373, -7.2676), ('Leiria', 39.7436, -8.8071),
        ('Lisboa', 38.7223, -9.1393), ('Portalegre', 39.2967, -7.4285),
        ('Porto', 41.1579, -8.6291), ('Santarém', 39.2369, -8.6850),
        ('Setúbal', 38.5244, -8.8882), ('Viana do Castelo', 41.6932, -8.8329),
        ('Vila Real', 41.3006, -7.7441), ('Viseu', 40.6566, -7.9125)
      ) AS d(name, lat, lng)
      ORDER BY power(d.lat - p_lat, 2) + power((d.lng - p_lng) * cos(radians(p_lat)), 2)
      LIMIT 1)
  END;
$function$;
REVOKE EXECUTE ON FUNCTION public.approx_district(double precision, double precision) FROM PUBLIC, anon, authenticated;


-- Devolve jsonb:
--   workers:   registered, active_30d, pro, pro_plus
--   survey:    answered (Profissionais com pelo menos uma linha)
--   fuel:      [{id, name, workers, liters}]  (soma dos litros/mês declarados)
--   districts: [{district, registered, active_30d, answered,
--                liters: {fuel_type_id: litros}}]
--   completed: [{month: 'AAAA-MM', category, count}] nos últimos p_months
--
-- "Registado" = Profissional com perfil feito (base definida), real
-- (admin_counts_person). "Ativo" = enviou uma proposta ou iniciou ou
-- concluiu um trabalho nos últimos 30 dias.
DROP FUNCTION IF EXISTS public.admin_partner_stats(integer);
CREATE FUNCTION public.admin_partner_stats(p_months integer DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_months    integer := GREATEST(1, LEAST(COALESCE(p_months, 6), 24));
  v_from      timestamptz;
  v_workers   jsonb;
  v_survey    jsonb;
  v_fuel      jsonb;
  v_districts jsonb;
  v_completed jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  v_from := date_trunc('month', now()) - make_interval(months => v_months - 1);

  CREATE TEMP TABLE IF NOT EXISTS _ps_workers (
    id uuid PRIMARY KEY, district text, active boolean, tier text, answered boolean
  ) ON COMMIT DROP;
  TRUNCATE _ps_workers;

  INSERT INTO _ps_workers
  SELECT wp.profile_id,
         public.approx_district(wp.base_lat::double precision, wp.base_lng::double precision),
         EXISTS (SELECT 1 FROM job_proposals jp
                 WHERE jp.worker_id = wp.profile_id AND jp.created_at >= now() - interval '30 days')
         OR EXISTS (SELECT 1 FROM job_requests jr JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
                    WHERE jp.worker_id = wp.profile_id
                      AND (jr.started_at >= now() - interval '30 days'
                           OR jr.marked_done_at >= now() - interval '30 days')),
         public.worker_active_tier(wp.profile_id),
         EXISTS (SELECT 1 FROM worker_fuel_usage u WHERE u.worker_id = wp.profile_id)
  FROM worker_profiles wp
  JOIN profiles p ON p.id = wp.profile_id AND p.role = 'worker'
  WHERE NOT (wp.base_lat = 0 AND wp.base_lng = 0)
    AND public.admin_counts_person(wp.profile_id);

  SELECT jsonb_build_object(
    'registered', count(*),
    'active_30d', count(*) FILTER (WHERE active),
    'pro',        count(*) FILTER (WHERE tier = 'pro'),
    'pro_plus',   count(*) FILTER (WHERE tier = 'pro_plus'))
  INTO v_workers FROM _ps_workers;

  SELECT jsonb_build_object('answered', count(*) FILTER (WHERE answered))
  INTO v_survey FROM _ps_workers;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', t.id, 'name', t.name,
           'workers', (SELECT count(*) FROM worker_fuel_usage u JOIN _ps_workers w ON w.id = u.worker_id
                       WHERE u.fuel_type_id = t.id),
           'liters',  (SELECT COALESCE(sum(u.liters_per_month), 0) FROM worker_fuel_usage u
                       JOIN _ps_workers w ON w.id = u.worker_id WHERE u.fuel_type_id = t.id))
         ORDER BY t.sort_order), '[]'::jsonb)
  INTO v_fuel FROM fuel_types t;

  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'registered')::int DESC, x->>'district'), '[]'::jsonb)
  INTO v_districts
  FROM (
    SELECT jsonb_build_object(
             'district',   w.district,
             'registered', count(*),
             'active_30d', count(*) FILTER (WHERE w.active),
             'answered',   count(*) FILTER (WHERE w.answered),
             'liters', COALESCE((
               SELECT jsonb_object_agg(s.fuel_type_id, s.total)
               FROM (SELECT u.fuel_type_id, sum(u.liters_per_month) AS total
                     FROM worker_fuel_usage u JOIN _ps_workers w2 ON w2.id = u.worker_id
                     WHERE w2.district = w.district
                     GROUP BY u.fuel_type_id) s), '{}'::jsonb)) AS x
    FROM _ps_workers w
    WHERE w.district IS NOT NULL
    GROUP BY w.district
  ) d;

  -- Trabalhos concluídos por mês (data em que o Profissional deu como
  -- feito; trabalhos antigos sem essa data usam a última alteração).
  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', m.month, 'category', m.category, 'count', m.n)
                            ORDER BY m.month, m.category), '[]'::jsonb)
  INTO v_completed
  FROM (
    SELECT to_char(COALESCE(jr.marked_done_at, jr.updated_at), 'YYYY-MM') AS month,
           c.name AS category, count(*) AS n
    FROM job_requests jr
    JOIN service_types st ON st.id = jr.service_type_id
    JOIN service_categories c ON c.id = st.category_id
    WHERE jr.status = 'completed'
      AND COALESCE(jr.marked_done_at, jr.updated_at) >= v_from
      AND public.admin_counts_person(jr.client_id)
    GROUP BY 1, 2
  ) m;

  PERFORM public.admin_log('view_partner_stats', NULL, jsonb_build_object('months', v_months));
  RETURN jsonb_build_object(
    'months', v_months,
    'workers', v_workers,
    'survey', v_survey,
    'fuel', v_fuel,
    'districts', v_districts,
    'completed', v_completed);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_partner_stats(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_partner_stats(integer) TO authenticated, service_role;
