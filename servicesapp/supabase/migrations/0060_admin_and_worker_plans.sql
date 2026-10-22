-- ══════════════════════════════════════════════════════════════
-- 0060 — Painel de administração (/admin) e planos dos jardineiros
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da
-- 0058_proposal_pricing_and_work_days.sql e da
-- 0059_card_direct_requests_and_tracking.sql (as duas do PR das propostas e
-- do cartão). Usa pricing_mode, total_price e job_work_days da 0058; também
-- started_at da 0052 e deleted_at da 0049.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. admin_users: quem é administrador. Só se escreve pelo SQL Editor
--      (ver SETUP.md, passo "Painel de administração"). Sem policies: a
--      app nunca lê nem escreve a tabela diretamente.
--   2. admin_actions: registo de cada mudança feita no painel.
--   3. worker_plans: plano de cada jardineiro (free, pro, pro_plus), com
--      validade, data da verificação de documentos e notas do contrato.
--      O papel (`profiles.role`) não muda: continua `worker`. Sem
--      policies: o jardineiro lê o seu plano por get_my_plan(), sem as
--      notas internas.
--   4. job_proposals.accepted_at, preenchido por trigger quando a
--      proposta passa a `accepted` (backfill com updated_at).
--   5. Limite do plano Grátis: 5 trabalhos aceites por mês (hora de
--      Lisboa). Ao chegar aos 5, o jardineiro sem Pro/Pro+ ativo não pode
--      enviar propostas novas até ao mês seguinte. Trigger BEFORE INSERT
--      em job_proposals, por isso vale para qualquer versão de
--      create_proposal. Propostas que já estavam pendentes podem ainda
--      ser aceites (o limite é suave, de propósito: falhar a aceitação do
--      cliente seria pior).
--   6. RPCs do painel, todas `admin_*`. Cada uma exige que auth.uid()
--      esteja em admin_users E que a sessão tenha o segundo fator (aal2,
--      app autenticadora). Sem isso, erro "Sem acesso.".
--
-- Sobre a regra "RPCs nunca recebem worker_id da app": a regra é sobre a
-- identidade de quem chama, que continua a ser sempre auth.uid(). As RPCs
-- admin_get_worker/admin_set_worker_plan recebem o id do jardineiro ALVO,
-- e só respondem a um administrador verificado (admin_users + aal2).
-- ══════════════════════════════════════════════════════════════


-- ── 1. Tabelas ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.admin_actions (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id   uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  action     text        NOT NULL,
  target_id  uuid,
  details    jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS admin_actions_target_idx
  ON public.admin_actions (target_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.worker_plans (
  worker_id   uuid        PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  tier        text        NOT NULL DEFAULT 'free',
  starts_at   date        NOT NULL DEFAULT CURRENT_DATE,
  ends_at     date,
  verified_at date,
  notes       text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.worker_plans DROP CONSTRAINT IF EXISTS worker_plans_tier_check;
ALTER TABLE public.worker_plans ADD CONSTRAINT worker_plans_tier_check
  CHECK (tier IN ('free', 'pro', 'pro_plus'));
ALTER TABLE public.worker_plans DROP CONSTRAINT IF EXISTS worker_plans_dates_check;
ALTER TABLE public.worker_plans ADD CONSTRAINT worker_plans_dates_check
  CHECK (ends_at IS NULL OR ends_at >= starts_at);
ALTER TABLE public.worker_plans ENABLE ROW LEVEL SECURITY;

-- Sem policies nas três tabelas: só funções SECURITY DEFINER lhes mexem.
REVOKE ALL ON public.admin_users, public.admin_actions, public.worker_plans
  FROM anon, authenticated;


-- ── 2. accepted_at nas propostas ────────────────────────────────

ALTER TABLE public.job_proposals
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

UPDATE public.job_proposals
SET    accepted_at = updated_at
WHERE  status = 'accepted' AND accepted_at IS NULL;

CREATE INDEX IF NOT EXISTS job_proposals_worker_accepted_idx
  ON public.job_proposals (worker_id, accepted_at)
  WHERE status = 'accepted';

CREATE OR REPLACE FUNCTION public.set_proposal_accepted_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN
    NEW.accepted_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_set_proposal_accepted_at ON public.job_proposals;
CREATE TRIGGER trg_set_proposal_accepted_at
  BEFORE UPDATE OF status ON public.job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.set_proposal_accepted_at();


-- ── 3. Helpers de plano ─────────────────────────────────────────

-- Limite mensal do plano Grátis (trabalhos aceites). Mudar aqui chega.
CREATE OR REPLACE FUNCTION public.free_plan_monthly_job_limit()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$ SELECT 5 $function$;

-- Plano em vigor hoje: pro/pro_plus dentro da validade, senão free.
CREATE OR REPLACE FUNCTION public.worker_active_tier(p_worker uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE((
    SELECT wp.tier
    FROM   worker_plans wp
    WHERE  wp.worker_id = p_worker
      AND  wp.tier <> 'free'
      AND  wp.starts_at <= (now() AT TIME ZONE 'Europe/Lisbon')::date
      AND  (wp.ends_at IS NULL
            OR wp.ends_at >= (now() AT TIME ZONE 'Europe/Lisbon')::date)
  ), 'free')
$function$;

-- Trabalhos aceites no mês corrente (hora de Lisboa).
CREATE OR REPLACE FUNCTION public.worker_jobs_accepted_this_month(p_worker uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT count(*)::integer
  FROM   job_proposals jp
  WHERE  jp.worker_id = p_worker
    AND  jp.status = 'accepted'
    AND  jp.accepted_at >= (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')
                            AT TIME ZONE 'Europe/Lisbon')
$function$;

REVOKE EXECUTE ON FUNCTION public.worker_active_tier(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.worker_jobs_accepted_this_month(uuid) FROM PUBLIC, anon, authenticated;


-- ── 4. Limite do Grátis ao criar proposta ───────────────────────

CREATE OR REPLACE FUNCTION public.enforce_free_plan_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF public.worker_active_tier(NEW.worker_id) = 'free'
     AND public.worker_jobs_accepted_this_month(NEW.worker_id)
         >= public.free_plan_monthly_job_limit() THEN
    RAISE EXCEPTION 'Chegaste aos % trabalhos deste mês do plano Grátis. Podes voltar a enviar propostas no próximo mês.',
      public.free_plan_monthly_job_limit()
      USING ERRCODE = 'P0001', HINT = 'free_plan_limit';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enforce_free_plan_limit ON public.job_proposals;
CREATE TRIGGER trg_enforce_free_plan_limit
  BEFORE INSERT ON public.job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.enforce_free_plan_limit();


-- ── 5. O plano do próprio jardineiro ────────────────────────────

DROP FUNCTION IF EXISTS public.get_my_plan();
CREATE FUNCTION public.get_my_plan()
RETURNS TABLE (
  tier                 text,
  ends_at              date,
  verified             boolean,
  jobs_this_month      integer,
  monthly_job_limit    integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tier text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  v_tier := public.worker_active_tier(auth.uid());
  RETURN QUERY
  SELECT v_tier,
         CASE WHEN v_tier = 'free' THEN NULL ELSE wp.ends_at END,
         (v_tier <> 'free' AND wp.verified_at IS NOT NULL),
         public.worker_jobs_accepted_this_month(auth.uid()),
         CASE WHEN v_tier = 'free' THEN public.free_plan_monthly_job_limit() END
  FROM   (SELECT 1) AS one
  LEFT JOIN worker_plans wp ON wp.worker_id = auth.uid();
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_plan() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_plan() TO authenticated, service_role;


-- ── 6. Acesso de administrador ──────────────────────────────────

-- Administrador com segundo fator nesta sessão.
CREATE OR REPLACE FUNCTION public.is_verified_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
     AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'
$function$;
REVOKE EXECUTE ON FUNCTION public.is_verified_admin() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.assert_verified_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_verified_admin() THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = '42501';
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.assert_verified_admin() FROM PUBLIC, anon, authenticated;

-- Primeiro passo do ecrã /admin: esta conta é administradora? E a
-- sessão já tem o segundo fator? Não devolve mais nada.
DROP FUNCTION IF EXISTS public.admin_whoami();
CREATE FUNCTION public.admin_whoami()
RETURNS TABLE (is_admin boolean, has_mfa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()),
         COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_whoami() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_whoami() TO authenticated, service_role;


-- ── 7. Visão geral ──────────────────────────────────────────────
-- p_days: período em dias (7, 30...). NULL = desde sempre. Os números
-- de pedidos são dos pedidos CRIADOS no período (coorte).

DROP FUNCTION IF EXISTS public.admin_overview(integer);
CREATE FUNCTION public.admin_overview(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_since  timestamptz;
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  v_since := CASE WHEN p_days IS NULL THEN '-infinity'::timestamptz
                  ELSE now() - make_interval(days => GREATEST(p_days, 1)) END;

  WITH jobs AS (
    SELECT jr.*,
           (SELECT min(jp.created_at) FROM job_proposals jp
            WHERE jp.job_id = jr.id) AS first_proposal_at
    FROM   job_requests jr
    WHERE  jr.created_at >= v_since
  )
  SELECT jsonb_build_object(
    'clients_total',   (SELECT count(*) FROM profiles
                        WHERE role = 'client' AND deleted_at IS NULL),
    'workers_total',   (SELECT count(*) FROM profiles
                        WHERE role = 'worker' AND deleted_at IS NULL),
    'clients_new',     (SELECT count(*) FROM profiles
                        WHERE role = 'client' AND created_at >= v_since),
    'workers_new',     (SELECT count(*) FROM profiles
                        WHERE role = 'worker' AND created_at >= v_since),
    'jobs_published',  (SELECT count(*) FROM jobs),
    'jobs_with_proposal_24h',
                       (SELECT count(*) FROM jobs
                        WHERE first_proposal_at <= created_at + interval '24 hours'),
    'avg_hours_to_first_proposal',
                       (SELECT round((avg(extract(epoch FROM first_proposal_at - created_at))
                                      / 3600)::numeric, 1)
                        FROM jobs WHERE first_proposal_at IS NOT NULL),
    'jobs_accepted',   (SELECT count(*) FROM jobs
                        WHERE status IN ('confirmed', 'awaiting_confirmation', 'completed')),
    'jobs_completed',  (SELECT count(*) FROM jobs WHERE status = 'completed'),
    'jobs_cancelled',  (SELECT count(*) FROM jobs WHERE status = 'cancelled'),
    'jobs_no_response',(SELECT count(*) FROM jobs WHERE status = 'no_response'),
    'avg_rating',      (SELECT round(avg(r.stars)::numeric, 2)
                        FROM ratings r
                        JOIN profiles p ON p.id = r.ratee_id AND p.role = 'worker'
                        WHERE r.created_at >= v_since),
    'ratings_count',   (SELECT count(*)
                        FROM ratings r
                        JOIN profiles p ON p.id = r.ratee_id AND p.role = 'worker'
                        WHERE r.created_at >= v_since),
    'workers_pro',     (SELECT count(*) FROM profiles p
                        WHERE p.role = 'worker' AND p.deleted_at IS NULL
                          AND public.worker_active_tier(p.id) = 'pro'),
    'workers_pro_plus',(SELECT count(*) FROM profiles p
                        WHERE p.role = 'worker' AND p.deleted_at IS NULL
                          AND public.worker_active_tier(p.id) = 'pro_plus'),
    'alert_open_without_proposals_12h',
                       (SELECT count(*) FROM job_requests
                        WHERE status = 'open' AND proposal_count = 0
                          AND created_at < now() - interval '12 hours'),
    'alert_reports_7d',(SELECT count(*) FROM job_reports
                        WHERE created_at >= now() - interval '7 days'),
    'alert_fleet_cards_pending',
                       (SELECT count(*) FROM worker_fleet_cards WHERE status = 'pending'),
    'alert_plans_ending_7d',
                       (SELECT count(*) FROM worker_plans
                        WHERE tier <> 'free' AND ends_at IS NOT NULL
                          AND ends_at BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_overview(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_overview(integer) TO authenticated, service_role;


-- ── 8. Lista de jardineiros ─────────────────────────────────────
-- p_tier: NULL = todos; 'free' | 'pro' | 'pro_plus' = plano em vigor.

DROP FUNCTION IF EXISTS public.admin_list_workers(text, text, integer, integer);
CREATE FUNCTION public.admin_list_workers(
  p_search text    DEFAULT NULL,
  p_tier   text    DEFAULT NULL,
  p_limit  integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  worker_id       uuid,
  full_name       text,
  phone           text,
  avatar_url      text,
  location_name   text,
  tier            text,
  plan_ends_at    date,
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  jobs_completed  integer,
  avg_rating      numeric,
  rating_count    integer,
  total_count     integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
BEGIN
  PERFORM public.assert_verified_admin();

  RETURN QUERY
  WITH base AS (
    SELECT p.id, p.full_name, p.phone, p.avatar_url, p.created_at,
           wpr.location_name,
           public.worker_active_tier(p.id) AS tier,
           pl.ends_at,
           u.last_sign_in_at
    FROM   profiles p
    LEFT JOIN worker_profiles wpr ON wpr.profile_id = p.id
    LEFT JOIN worker_plans    pl  ON pl.worker_id  = p.id
    LEFT JOIN auth.users      u   ON u.id          = p.id
    WHERE  p.role = 'worker'
      AND  p.deleted_at IS NULL
      AND  (v_search IS NULL
            OR p.full_name ILIKE '%' || v_search || '%'
            OR COALESCE(p.phone, '') ILIKE '%' || v_search || '%'
            OR COALESCE(wpr.location_name, '') ILIKE '%' || v_search || '%')
  ), filtered AS (
    SELECT * FROM base WHERE p_tier IS NULL OR base.tier = p_tier
  )
  SELECT f.id, f.full_name, f.phone, f.avatar_url, f.location_name,
         f.tier,
         CASE WHEN f.tier = 'free' THEN NULL ELSE f.ends_at END,
         f.created_at, f.last_sign_in_at,
         (SELECT count(*)::integer
          FROM job_requests jr
          JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
          WHERE jp.worker_id = f.id AND jr.status = 'completed'),
         (SELECT round(avg(r.stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = f.id),
         (SELECT count(*)::integer FROM ratings r WHERE r.ratee_id = f.id),
         (count(*) OVER ())::integer
  FROM   filtered f
  ORDER  BY f.created_at DESC
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_workers(text, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_workers(text, text, integer, integer) TO authenticated, service_role;


-- ── 9. Ficha de um jardineiro ───────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_get_worker(uuid);
CREATE FUNCTION public.admin_get_worker(p_worker_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_worker_id AND role = 'worker') THEN
    RAISE EXCEPTION 'Jardineiro não encontrado.';
  END IF;

  WITH principal AS (
    -- Trabalhos em que foi o responsável (proposta aceite).
    SELECT jr.*, jp.hourly_rate, jp.estimated_hours_min, jp.estimated_hours_max,
           jp.accepted_at, jp.pricing_mode, jp.total_price
    FROM   job_requests jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jp.worker_id = p_worker_id
  ), completed AS (
    -- Horas: soma dos dias de trabalho (0058); trabalhos antigos sem dias
    -- registados usam o início e a conclusão.
    SELECT pr.*,
           COALESCE(
             (SELECT sum(extract(epoch FROM wd.ended_at - wd.started_at)) / 3600
              FROM job_work_days wd
              WHERE wd.job_id = pr.id AND wd.ended_at IS NOT NULL),
             CASE WHEN pr.started_at IS NOT NULL AND pr.marked_done_at IS NOT NULL
                       AND pr.marked_done_at > pr.started_at
                  THEN extract(epoch FROM pr.marked_done_at - pr.started_at) / 3600 END
           ) AS tracked_hours
    FROM   principal pr
    WHERE  status = 'completed'
  ), proposals AS (
    SELECT jp.*, jr.created_at AS job_created_at
    FROM   job_proposals jp
    JOIN   job_requests jr ON jr.id = jp.job_id
    WHERE  jp.worker_id = p_worker_id
  )
  SELECT jsonb_build_object(
    'worker_id',       p.id,
    'full_name',       p.full_name,
    'phone',           p.phone,
    'avatar_url',      p.avatar_url,
    'created_at',      p.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'location_name',   wpr.location_name,
    'radius_km',       wpr.radius_km,
    'services',        COALESCE((
                         SELECT jsonb_agg(st.name ORDER BY st.sort_order, st.name)
                         FROM worker_service_types wst
                         JOIN service_types st ON st.id = wst.service_type_id
                         WHERE wst.worker_id = p.id), '[]'::jsonb),
    'proposals_sent',  (SELECT count(*) FROM proposals),
    'proposals_accepted', (SELECT count(*) FROM proposals WHERE status = 'accepted'),
    'avg_response_hours', (SELECT round((avg(extract(epoch FROM created_at - job_created_at))
                                         / 3600)::numeric, 1) FROM proposals),
    'jobs_completed',  (SELECT count(*) FROM completed),
    'jobs_active',     (SELECT count(*) FROM principal
                        WHERE status IN ('confirmed', 'awaiting_confirmation')),
    'jobs_cancelled_by_worker',
                       (SELECT count(*) FROM job_requests jr
                        WHERE jr.cancelled_by = p_worker_id),
    'tracked_hours',   (SELECT round(COALESCE(sum(tracked_hours), 0)::numeric, 1) FROM completed),
    -- Valor fechado conta o total; por hora, as horas registadas (ou o
    -- meio da estimativa).
    'estimated_revenue', (SELECT round(COALESCE(sum(
                            CASE WHEN pricing_mode = 'fixed_total' THEN total_price
                                 ELSE hourly_rate * COALESCE(
                                   tracked_hours,
                                   (estimated_hours_min + COALESCE(estimated_hours_max, estimated_hours_min)) / 2,
                                   0)
                            END), 0)::numeric, 0)
                          FROM completed),
    'helper_jobs',     (SELECT count(*) FROM help_acceptances ha
                        WHERE ha.worker_id = p_worker_id AND ha.status = 'accepted'),
    'avg_rating',      (SELECT round(avg(r.stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = p.id),
    'rating_count',    (SELECT count(*) FROM ratings r WHERE r.ratee_id = p.id),
    'jobs_this_month', public.worker_jobs_accepted_this_month(p.id),
    'monthly_jobs',    COALESCE((
                         SELECT jsonb_agg(jsonb_build_object('month', m.month, 'count', m.cnt)
                                          ORDER BY m.month)
                         FROM (
                           SELECT to_char(gs, 'YYYY-MM') AS month,
                                  (SELECT count(*) FROM principal pr
                                   WHERE pr.accepted_at >= gs
                                     AND pr.accepted_at <  gs + interval '1 month') AS cnt
                           FROM generate_series(
                                  date_trunc('month', now()) - interval '5 months',
                                  date_trunc('month', now()),
                                  interval '1 month') AS gs
                         ) m), '[]'::jsonb),
    'plan',            jsonb_build_object(
                         'active_tier', public.worker_active_tier(p.id),
                         'tier',        pl.tier,
                         'starts_at',   pl.starts_at,
                         'ends_at',     pl.ends_at,
                         'verified_at', pl.verified_at,
                         'notes',       pl.notes,
                         'updated_at',  pl.updated_at),
    'plan_history',    COALESCE((
                         SELECT jsonb_agg(jsonb_build_object(
                                  'created_at', a.created_at,
                                  'details',    a.details) ORDER BY a.created_at DESC)
                         FROM (SELECT * FROM admin_actions
                               WHERE target_id = p.id AND action = 'set_worker_plan'
                               ORDER BY created_at DESC LIMIT 20) a), '[]'::jsonb)
  ) INTO v_result
  FROM   profiles p
  LEFT JOIN worker_profiles wpr ON wpr.profile_id = p.id
  LEFT JOIN worker_plans    pl  ON pl.worker_id  = p.id
  LEFT JOIN auth.users      u   ON u.id          = p.id
  WHERE  p.id = p_worker_id;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_worker(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_worker(uuid) TO authenticated, service_role;


-- ── 10. Atribuir plano ──────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_set_worker_plan(uuid, text, date, date, date, text);
CREATE FUNCTION public.admin_set_worker_plan(
  p_worker_id   uuid,
  p_tier        text,
  p_starts_at   date DEFAULT NULL,
  p_ends_at     date DEFAULT NULL,
  p_verified_at date DEFAULT NULL,
  p_notes       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_starts date := COALESCE(p_starts_at, (now() AT TIME ZONE 'Europe/Lisbon')::date);
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_tier NOT IN ('free', 'pro', 'pro_plus') THEN
    RAISE EXCEPTION 'Plano inválido.';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at < v_starts THEN
    RAISE EXCEPTION 'A data de fim tem de ser depois do início.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_worker_id AND role = 'worker') THEN
    RAISE EXCEPTION 'Jardineiro não encontrado.';
  END IF;

  INSERT INTO worker_plans AS wp
    (worker_id, tier, starts_at, ends_at, verified_at, notes, updated_at, updated_by)
  VALUES
    (p_worker_id, p_tier, v_starts, p_ends_at, p_verified_at,
     NULLIF(btrim(COALESCE(p_notes, '')), ''), now(), auth.uid())
  ON CONFLICT (worker_id) DO UPDATE
    SET tier        = EXCLUDED.tier,
        starts_at   = EXCLUDED.starts_at,
        ends_at     = EXCLUDED.ends_at,
        verified_at = EXCLUDED.verified_at,
        notes       = EXCLUDED.notes,
        updated_at  = now(),
        updated_by  = auth.uid();

  INSERT INTO admin_actions (admin_id, action, target_id, details)
  VALUES (auth.uid(), 'set_worker_plan', p_worker_id, jsonb_build_object(
    'tier', p_tier, 'starts_at', v_starts, 'ends_at', p_ends_at,
    'verified_at', p_verified_at));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_set_worker_plan(uuid, text, date, date, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_worker_plan(uuid, text, date, date, date, text) TO authenticated, service_role;
