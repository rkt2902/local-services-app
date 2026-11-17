-- ══════════════════════════════════════════════════════════════
-- 0081 — Painel de admin, fase 3: funil, exportar CSV, avisos a grupos
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (17/11/2026, Henrique).
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. admin_funnel(p_days): três funis do período (clientes que se
--      registaram, pedidos criados, jardineiros que se registaram), com o
--      tempo mediano até à primeira proposta.
--   2. admin_export_rows(p_kind, p_days): linhas para CSV de pedidos,
--      clientes ou jardineiros. Sem telefone, email nem morada exata
--      (minimização de dados: o CSV sai do painel). Fica registado.
--   3. Avisos a grupos: admin_notice_audience conta quem recebe,
--      admin_send_notice envia (tipo 'admin_notice', com push) só se a
--      contagem ainda for a mesma que o admin viu; admin_list_notices dá o
--      histórico (tabela admin_notices).
--
-- Regras de sempre: cada admin_* chama assert_verified_admin(); quem
-- chama é auth.uid(); contas eliminadas, suspensas e de admin ficam de
-- fora dos números e dos avisos.
-- ══════════════════════════════════════════════════════════════


-- ── 0. Quem conta ───────────────────────────────────────────────

-- Pessoas reais e ativas: nem eliminadas, nem suspensas, nem admin.
CREATE OR REPLACE FUNCTION public.admin_counts_person(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM profiles p WHERE p.id = p_uid AND p.deleted_at IS NULL)
     AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p_uid)
     AND NOT EXISTS (SELECT 1 FROM account_status s
                     WHERE s.profile_id = p_uid AND s.suspended_at IS NOT NULL);
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_counts_person(uuid) FROM PUBLIC, anon, authenticated;

-- Início do período: NULL ou 0 = desde sempre.
CREATE OR REPLACE FUNCTION public.admin_period_start(p_days integer)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $function$
  SELECT CASE WHEN COALESCE(p_days, 0) <= 0 THEN '-infinity'::timestamptz
              ELSE now() - make_interval(days => LEAST(p_days, 3650)) END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_period_start(integer) FROM PUBLIC, anon, authenticated;


-- ── 1. Funil ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_funnel(integer);
CREATE FUNCTION public.admin_funnel(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_from    timestamptz := public.admin_period_start(p_days);
  v_clients jsonb;
  v_jobs    jsonb;
  v_workers jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  -- Clientes que se registaram no período: até onde chegaram (em qualquer
  -- altura, não só no período).
  WITH c AS (
    SELECT p.id FROM profiles p
    WHERE p.role = 'client' AND p.created_at >= v_from AND public.admin_counts_person(p.id)
  )
  SELECT jsonb_build_object(
    'signed_up',    count(*),
    'posted',       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr WHERE jr.client_id = c.id)),
    'got_proposal', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr JOIN job_proposals jp ON jp.job_id = jr.id
                                                   WHERE jr.client_id = c.id)),
    'hired',        count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr
                                                   WHERE jr.client_id = c.id AND jr.accepted_proposal_id IS NOT NULL)),
    'completed',    count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr
                                                   WHERE jr.client_id = c.id AND jr.status = 'completed')),
    'rated',        count(*) FILTER (WHERE EXISTS (SELECT 1 FROM ratings r WHERE r.rater_id = c.id)))
  INTO v_clients FROM c;

  -- Pedidos criados no período (de clientes reais).
  WITH j AS (
    SELECT jr.* FROM job_requests jr
    WHERE jr.created_at >= v_from AND public.admin_counts_person(jr.client_id)
  ), firsts AS (
    SELECT j.id, min(jp.created_at) - j.created_at AS wait
    FROM j JOIN job_proposals jp ON jp.job_id = j.id
    GROUP BY j.id, j.created_at
  )
  SELECT jsonb_build_object(
    'created',       (SELECT count(*) FROM j),
    'with_proposal', (SELECT count(*) FROM firsts),
    'accepted',      (SELECT count(*) FROM j WHERE accepted_proposal_id IS NOT NULL),
    'completed',     (SELECT count(*) FROM j WHERE status = 'completed'),
    'rated',         (SELECT count(*) FROM j WHERE EXISTS (SELECT 1 FROM ratings r
                                                           WHERE r.job_id = j.id AND r.rater_id = j.client_id)),
    'open',          (SELECT count(*) FROM j WHERE status = 'open'),
    'no_response',   (SELECT count(*) FROM j WHERE status = 'no_response'),
    'cancelled',     (SELECT count(*) FROM j WHERE status = 'cancelled'),
    'median_hours_to_first_proposal',
      (SELECT round((extract(epoch FROM percentile_cont(0.5) WITHIN GROUP (ORDER BY wait)) / 3600)::numeric, 1)
       FROM firsts))
  INTO v_jobs;

  -- Jardineiros que se registaram no período.
  WITH w AS (
    SELECT p.id FROM profiles p
    WHERE p.role = 'worker' AND p.created_at >= v_from AND public.admin_counts_person(p.id)
  )
  SELECT jsonb_build_object(
    'signed_up',     count(*),
    'profile_ready', count(*) FILTER (WHERE EXISTS (SELECT 1 FROM worker_profiles wp
                                                    WHERE wp.profile_id = w.id
                                                      AND NOT (wp.base_lat = 0 AND wp.base_lng = 0))),
    'proposed',      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_proposals jp WHERE jp.worker_id = w.id)),
    'hired',         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr JOIN job_proposals jp
                                                      ON jp.id = jr.accepted_proposal_id WHERE jp.worker_id = w.id)),
    'completed',     count(*) FILTER (WHERE EXISTS (SELECT 1 FROM job_requests jr JOIN job_proposals jp
                                                      ON jp.id = jr.accepted_proposal_id
                                                    WHERE jp.worker_id = w.id AND jr.status = 'completed')),
    'paid_plan',     count(*) FILTER (WHERE public.worker_active_tier(w.id) <> 'free'))
  INTO v_workers FROM w;

  PERFORM public.admin_log('view_funnel', NULL, jsonb_build_object('days', p_days));
  RETURN jsonb_build_object('days', p_days, 'clients', v_clients, 'jobs', v_jobs, 'workers', v_workers);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_funnel(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_funnel(integer) TO authenticated, service_role;


-- ── 2. Exportar CSV ─────────────────────────────────────────────
-- Devolve {columns: [...], rows: [[...], ...]}; a app escreve o CSV.
-- Até 10 000 linhas, as mais recentes primeiro.

DROP FUNCTION IF EXISTS public.admin_export_rows(text, integer);
CREATE FUNCTION public.admin_export_rows(p_kind text, p_days integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_from    timestamptz := public.admin_period_start(p_days);
  v_columns jsonb;
  v_rows    jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_kind = 'jobs' THEN
    v_columns := '["id","criado","estado","servico","localidade","data","propostas","jardineiro","motivo_cancelamento","pedido_direto"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.created_at, x.status, x.service, x.area, x.when_text, x.proposal_count,
             x.worker, x.cancel_reason, x.direct) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT jr.id, jr.created_at, jr.status, st.name AS service, jr.location_area AS area,
             COALESCE(jr.confirmed_date::text, jr.preferred_date::text, jr.date_mode) AS when_text,
             jr.proposal_count, wp.full_name AS worker, jr.cancel_reason,
             (jr.direct_worker_id IS NOT NULL OR jr.direct_card_worker_id IS NOT NULL) AS direct
      FROM job_requests jr
      LEFT JOIN service_types st ON st.id = jr.service_type_id
      LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
      LEFT JOIN profiles wp ON wp.id = jp.worker_id
      WHERE jr.created_at >= v_from
      ORDER BY jr.created_at DESC
      LIMIT 10000
    ) x;

  ELSIF p_kind = 'clients' THEN
    v_columns := '["id","nome","registo","pedidos","concluidos","cancelados","ultimo_pedido","estado"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.full_name, x.created_at, x.jobs, x.completed, x.cancelled, x.last_job, x.state)
             ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT p.id, p.full_name, p.created_at,
             count(jr.id) AS jobs,
             count(jr.id) FILTER (WHERE jr.status = 'completed') AS completed,
             count(jr.id) FILTER (WHERE jr.status = 'cancelled') AS cancelled,
             max(jr.created_at) AS last_job,
             CASE WHEN p.deleted_at IS NOT NULL THEN 'eliminada'
                  WHEN s.suspended_at IS NOT NULL THEN 'suspensa'
                  ELSE 'ativa' END AS state
      FROM profiles p
      LEFT JOIN job_requests jr ON jr.client_id = p.id
      LEFT JOIN account_status s ON s.profile_id = p.id
      WHERE p.role = 'client' AND p.created_at >= v_from
        AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)
      GROUP BY p.id, s.suspended_at
      ORDER BY p.created_at DESC
      LIMIT 10000
    ) x;

  ELSIF p_kind = 'workers' THEN
    v_columns := '["id","nome","registo","localidade","raio_km","plano","servicos","propostas","aceites","concluidos","media","avaliacoes","estado"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.full_name, x.created_at, x.location_name, x.radius_km, x.tier, x.services,
             x.proposals, x.accepted, x.completed, x.avg_rating, x.ratings, x.state)
             ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT p.id, p.full_name, p.created_at, wp.location_name, wp.radius_km,
             public.worker_active_tier(p.id) AS tier,
             (SELECT count(*) FROM worker_service_types wst WHERE wst.worker_id = p.id) AS services,
             (SELECT count(*) FROM job_proposals jp WHERE jp.worker_id = p.id) AS proposals,
             (SELECT count(*) FROM job_requests jr JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
              WHERE jp.worker_id = p.id) AS accepted,
             (SELECT count(*) FROM job_requests jr JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
              WHERE jp.worker_id = p.id AND jr.status = 'completed') AS completed,
             (SELECT round(avg(stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = p.id) AS avg_rating,
             (SELECT count(*) FROM ratings r WHERE r.ratee_id = p.id) AS ratings,
             CASE WHEN p.deleted_at IS NOT NULL THEN 'eliminada'
                  WHEN EXISTS (SELECT 1 FROM account_status s
                               WHERE s.profile_id = p.id AND s.suspended_at IS NOT NULL) THEN 'suspensa'
                  ELSE 'ativa' END AS state
      FROM profiles p
      LEFT JOIN worker_profiles wp ON wp.profile_id = p.id
      WHERE p.role = 'worker' AND p.created_at >= v_from
        AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)
      ORDER BY p.created_at DESC
      LIMIT 10000
    ) x;

  ELSE
    RAISE EXCEPTION 'Tipo de exportação inválido.';
  END IF;

  PERFORM public.admin_log('export_csv', NULL, jsonb_build_object(
    'kind', p_kind, 'days', p_days, 'rows', jsonb_array_length(v_rows)));
  RETURN jsonb_build_object('columns', v_columns, 'rows', v_rows);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_export_rows(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_export_rows(text, integer) TO authenticated, service_role;


-- ── 3. Avisos a grupos ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_notices (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text        NOT NULL,
  body            text        NOT NULL,
  audience        jsonb       NOT NULL,
  recipients      integer     NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS admin_notices_created_idx ON public.admin_notices (created_at DESC);
ALTER TABLE public.admin_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_notices FROM anon, authenticated;

-- Quem recebe um aviso. p_role 'worker' ou 'client'. Só para jardineiros:
-- p_tiers (free/pro/pro_plus; NULL = todos) e p_service_type_id. p_area
-- (texto) procura na localidade do jardineiro ou, nos clientes, na
-- localidade de algum pedido deles.
CREATE OR REPLACE FUNCTION public.admin_notice_recipients(
  p_role            text,
  p_tiers           text[],
  p_service_type_id uuid,
  p_area            text
)
RETURNS TABLE(user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id
  FROM profiles p
  WHERE p.role = p_role
    AND public.admin_counts_person(p.id)
    AND (p_role <> 'worker' OR EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = p.id))
    AND (p_tiers IS NULL OR cardinality(p_tiers) = 0 OR p_role <> 'worker'
         OR public.worker_active_tier(p.id) = ANY (p_tiers))
    AND (p_service_type_id IS NULL OR p_role <> 'worker'
         OR EXISTS (SELECT 1 FROM worker_service_types wst
                    WHERE wst.worker_id = p.id AND wst.service_type_id = p_service_type_id))
    AND (NULLIF(btrim(COALESCE(p_area, '')), '') IS NULL
         OR (p_role = 'worker' AND EXISTS (
               SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = p.id
                 AND wp.location_name ILIKE '%' || btrim(p_area) || '%'))
         OR (p_role = 'client' AND EXISTS (
               SELECT 1 FROM job_requests jr WHERE jr.client_id = p.id
                 AND jr.location_area ILIKE '%' || btrim(p_area) || '%')));
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_notice_recipients(text, text[], uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_check_notice_audience(p_role text, p_tiers text[])
RETURNS void
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('worker', 'client') THEN
    RAISE EXCEPTION 'Escolhe para quem é o aviso: jardineiros ou clientes.';
  END IF;
  IF p_tiers IS NOT NULL AND NOT (p_tiers <@ ARRAY['free', 'pro', 'pro_plus']) THEN
    RAISE EXCEPTION 'Plano inválido.';
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_check_notice_audience(text, text[]) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.admin_notice_audience(text, text[], uuid, text);
CREATE FUNCTION public.admin_notice_audience(
  p_role            text,
  p_tiers           text[] DEFAULT NULL,
  p_service_type_id uuid   DEFAULT NULL,
  p_area            text   DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_check_notice_audience(p_role, p_tiers);
  SELECT count(*) INTO v_n
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area);
  RETURN v_n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_notice_audience(text, text[], uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_notice_audience(text, text[], uuid, text) TO authenticated, service_role;

-- Envia. p_expected: o número que o admin viu ao contar; se mudou entretanto,
-- recusa (conta outra vez antes de enviar). Recusa o mesmo texto duas
-- vezes em 24 h.
DROP FUNCTION IF EXISTS public.admin_send_notice(text, text, text, text[], uuid, text, integer);
-- A 0082 acrescenta p_partner_id. Se esta migration voltar a correr
-- depois da 0082, tira essa versão (para não haver duas) e é preciso
-- correr a 0082 outra vez.
DROP FUNCTION IF EXISTS public.admin_send_notice(text, text, text, text[], uuid, text, integer, uuid);
CREATE FUNCTION public.admin_send_notice(
  p_title           text,
  p_body            text,
  p_role            text,
  p_tiers           text[],
  p_service_type_id uuid,
  p_area            text,
  p_expected        integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_title    text := btrim(COALESCE(p_title, ''));
  v_body     text := btrim(COALESCE(p_body, ''));
  v_n        integer;
  v_id       uuid;
  v_audience jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_check_notice_audience(p_role, p_tiers);
  IF length(v_title) < 3 OR length(v_title) > 80 THEN
    RAISE EXCEPTION 'O título tem de ter entre 3 e 80 carateres.';
  END IF;
  IF length(v_body) < 10 OR length(v_body) > 500 THEN
    RAISE EXCEPTION 'O texto tem de ter entre 10 e 500 carateres.';
  END IF;
  IF EXISTS (SELECT 1 FROM admin_notices
             WHERE title = v_title AND body = v_body AND created_at > now() - interval '24 hours') THEN
    RAISE EXCEPTION 'Este aviso já foi enviado nas últimas 24 horas.';
  END IF;

  SELECT count(*) INTO v_n
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area);
  IF v_n = 0 THEN
    RAISE EXCEPTION 'Ninguém corresponde a estes filtros.';
  END IF;
  IF p_expected IS DISTINCT FROM v_n THEN
    RAISE EXCEPTION 'O número de destinatários mudou (agora %). Conta outra vez antes de enviar.', v_n;
  END IF;

  v_audience := jsonb_strip_nulls(jsonb_build_object(
    'role', p_role, 'tiers', to_jsonb(NULLIF(p_tiers, '{}')),
    'service_type_id', p_service_type_id, 'area', NULLIF(btrim(COALESCE(p_area, '')), '')));
  INSERT INTO admin_notices (title, body, audience, recipients, created_by)
  VALUES (v_title, v_body, v_audience, v_n, auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT r.user_id, 'admin_notice', v_title, v_body, v_id, 'admin_notice'
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area) r;

  PERFORM public.admin_log('send_notice', v_id, v_audience || jsonb_build_object(
    'title', v_title, 'recipients', v_n));
  RETURN v_n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_send_notice(text, text, text, text[], uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_notice(text, text, text, text[], uuid, text, integer) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_list_notices(integer, integer);
CREATE FUNCTION public.admin_list_notices(p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
RETURNS TABLE(
  id          uuid,
  title       text,
  body        text,
  audience    jsonb,
  recipients  integer,
  read_count  integer,
  created_at  timestamptz,
  admin_email text,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT n.id, n.title, n.body, n.audience, n.recipients,
         (SELECT count(*)::integer FROM notifications x
          WHERE x.related_id = n.id AND x.type = 'admin_notice' AND x.read),
         n.created_at, u.email::text, count(*) OVER ()
  FROM admin_notices n
  LEFT JOIN auth.users u ON u.id = n.created_by
  ORDER BY n.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_notices(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_notices(integer, integer) TO authenticated, service_role;
