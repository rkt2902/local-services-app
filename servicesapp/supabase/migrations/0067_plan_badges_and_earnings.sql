-- ══════════════════════════════════════════════════════════════
-- 0067 — Selo do plano (Pro / Pro+) e painel de ganhos
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar via SQL Editor, DEPOIS da 0066. Usa
-- worker_active_tier (0060), job_work_days e pricing_mode (0058),
-- started_at (0052), marked_done_at (0046), deleted_at (0049) e a vista
-- worker_public_card da 0059. Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. worker_public_tier(uuid): o plano em vigor de um jardineiro, para
--      mostrar o selo. É informação pública (o selo aparece no cartão e
--      nas propostas), por isso pode ser lida por anon. Não expõe datas,
--      notas nem verificação.
--   2. worker_public_card: mesma vista da 0059 com a coluna plan_tier no
--      fim (CREATE OR REPLACE VIEW só aceita colunas novas no fim).
--   3. get_pending_proposals_for_job: mais a coluna worker_plan_tier no
--      fim. RETURNS TABLE muda de forma: DROP explícito antes de recriar.
--   4. get_my_earnings(p_from, p_to): os trabalhos feitos pelo próprio
--      (responsável ou ajudante) entre duas datas, com o necessário para a
--      app calcular o valor de cada um. Só no Pro e no Pro+ (decisão do
--      Henrique a 2026-10-28): no Grátis dá erro com HINT 'plan_required'.
--
-- Identidade sempre por auth.uid(); get_my_earnings não recebe ids de
-- utilizador. worker_public_tier recebe o id do jardineiro ALVO, como a
-- vista worker_public_card, e só devolve o nome do plano.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Plano público (selo) ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.worker_public_tier(p_worker_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.worker_active_tier(p_worker_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.worker_public_tier(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.worker_public_tier(uuid) TO anon, authenticated, service_role;


-- ── 2. Cartão público com o plano ───────────────────────────────

CREATE OR REPLACE VIEW public.worker_public_card AS
SELECT
  wp.profile_id AS worker_id,
  p.full_name,
  p.avatar_url,
  wp.bio,
  wp.location_name,
  COALESCE(
    array_agg(DISTINCT st.name) FILTER (WHERE st.name IS NOT NULL),
    ARRAY[]::text[]
  ) AS service_names,
  COALESCE(AVG(r.stars), 0)::numeric(3, 2) AS avg_rating,
  COUNT(DISTINCT r.id) AS rating_count,
  wp.highlights,
  wp.social_links,
  COALESCE(
    array_agg(DISTINCT st.id) FILTER (WHERE st.id IS NOT NULL),
    ARRAY[]::uuid[]
  ) AS service_type_ids,
  worker_can_use_public_card(wp.profile_id)         AS can_use_public_card,
  worker_can_receive_direct_requests(wp.profile_id) AS can_receive_direct_requests,
  lr.comment    AS latest_review_comment,
  lr.rater_name AS latest_review_author,
  lr.created_at AS latest_review_at,
  worker_public_tier(wp.profile_id) AS plan_tier
FROM worker_profiles wp
JOIN profiles p ON p.id = wp.profile_id
LEFT JOIN worker_service_types wst ON wst.worker_id = wp.profile_id
LEFT JOIN service_types st ON st.id = wst.service_type_id
LEFT JOIN ratings r ON r.ratee_id = wp.profile_id
LEFT JOIN LATERAL (
  SELECT r2.comment,
         NULLIF(btrim(split_part(rp.full_name, ' ', 1)), '') AS rater_name,
         r2.created_at
  FROM   ratings r2
  LEFT JOIN profiles rp ON rp.id = r2.rater_id
  WHERE  r2.ratee_id = wp.profile_id
    AND  r2.stars >= 4
    AND  NULLIF(btrim(r2.comment), '') IS NOT NULL
  ORDER BY r2.created_at DESC
  LIMIT 1
) lr ON true
WHERE p.deleted_at IS NULL
GROUP BY wp.profile_id, p.full_name, p.avatar_url, wp.bio, wp.location_name,
         wp.highlights, wp.social_links, lr.comment, lr.rater_name, lr.created_at;

GRANT SELECT ON public.worker_public_card TO anon, authenticated;


-- ── 3. Propostas pendentes com o plano de quem propôs ───────────
-- Igual à 0058, mais worker_plan_tier no fim.

DROP FUNCTION IF EXISTS public.get_pending_proposals_for_job(uuid);

CREATE FUNCTION public.get_pending_proposals_for_job(p_job_id uuid)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  worker_id                 uuid,
  hourly_rate               numeric,
  estimated_hours_min       numeric,
  estimated_hours_max       numeric,
  people_needed             integer,
  helpers_equipment_required boolean,
  notes                     text,
  status                    text,
  scheduled_date            date,
  scheduled_time            time,
  scheduled_flexible        boolean,
  created_at                timestamptz,
  worker_name               text,
  worker_avatar_url         text,
  pricing_mode              text,
  total_price               numeric,
  includes                  text[],
  estimated_days_min        integer,
  estimated_days_max        integer,
  valid_until               date,
  is_expired                boolean,
  worker_plan_tier          text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    jp.id, jp.job_id, jp.worker_id, jp.hourly_rate, jp.estimated_hours_min,
    jp.estimated_hours_max, jp.people_needed, jp.helpers_equipment_required,
    jp.notes, jp.status, jp.scheduled_date, jp.scheduled_time,
    jp.scheduled_flexible, jp.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url,
    jp.pricing_mode, jp.total_price, jp.includes,
    jp.estimated_days_min, jp.estimated_days_max, jp.valid_until,
    (jp.valid_until IS NOT NULL AND jp.valid_until < today_pt()) AS is_expired,
    worker_active_tier(jp.worker_id) AS worker_plan_tier
  FROM   job_proposals jp
  JOIN   profiles      p ON p.id = jp.worker_id
  WHERE  jp.job_id = p_job_id
    AND  jp.status = 'pending'
    AND  EXISTS (
      SELECT 1 FROM job_requests jr
      WHERE jr.id = jp.job_id AND jr.client_id = auth.uid()
    )
  ORDER BY jp.created_at ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_pending_proposals_for_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_pending_proposals_for_job(uuid) TO authenticated, service_role;


-- ── 4. Ganhos do próprio ────────────────────────────────────────
-- Uma linha por trabalho feito (completed ou awaiting_confirmation), com a
-- data em que foi marcado como feito (hora de Lisboa). O valor calcula-se
-- na app (earnings_calculator.dart), para ser o mesmo dos outros ecrãs:
--   responsável, por hora:  hourly_rate × horas registadas
--   responsável, valor total: total_price − pagamento dos ajudantes
--   ajudante:               agreed_rate × horas registadas
-- worked_minutes: soma dos dias de trabalho fechados; sem dias, o tempo
-- entre started_at e marked_done_at; sem nenhum dos dois, NULL (a app usa
-- então a estimativa da proposta e diz que é estimativa).
-- helpers_cost (só responsável): soma de agreed_rate dos ajudantes aceites
-- × horas registadas; NULL sem horas registadas.

DROP FUNCTION IF EXISTS public.get_my_earnings(date, date);

CREATE FUNCTION public.get_my_earnings(p_from date, p_to date)
RETURNS TABLE(
  job_id               uuid,
  role                 text,
  service_type_name    text,
  done_on              date,
  job_status           text,
  pricing_mode         text,
  rate                 numeric,
  total_price          numeric,
  worked_minutes       integer,
  estimated_hours_min  numeric,
  estimated_hours_max  numeric,
  helpers_cost         numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'Intervalo de datas inválido.';
  END IF;

  IF worker_active_tier(v_uid) = 'free' THEN
    RAISE EXCEPTION 'O painel de ganhos é do plano Pro.'
      USING ERRCODE = 'P0001', HINT = 'plan_required';
  END IF;

  RETURN QUERY
  WITH done_jobs AS (
    SELECT jr.id,
           jr.status,
           jr.service_type_id,
           jr.accepted_proposal_id,
           jr.started_at,
           jr.marked_done_at,
           (COALESCE(jr.marked_done_at, jr.updated_at)
              AT TIME ZONE 'Europe/Lisbon')::date AS done_on
    FROM   job_requests jr
    WHERE  jr.status IN ('completed', 'awaiting_confirmation')
      AND  jr.accepted_proposal_id IS NOT NULL
  ),
  minutes AS (
    SELECT dj.id AS job_id,
           COALESCE(
             (SELECT (sum(extract(epoch FROM (wd.ended_at - wd.started_at))) / 60)::integer
              FROM   job_work_days wd
              WHERE  wd.job_id = dj.id AND wd.ended_at IS NOT NULL
              HAVING count(*) > 0),
             CASE WHEN dj.started_at IS NOT NULL
                       AND dj.marked_done_at IS NOT NULL
                       AND dj.marked_done_at > dj.started_at
                  THEN (extract(epoch FROM (dj.marked_done_at - dj.started_at)) / 60)::integer
             END
           ) AS worked_minutes
    FROM   done_jobs dj
    WHERE  dj.done_on BETWEEN p_from AND p_to
  )
  -- Responsável
  SELECT dj.id,
         'principal'::text,
         st.name,
         dj.done_on,
         dj.status,
         jp.pricing_mode,
         jp.hourly_rate,
         jp.total_price,
         m.worked_minutes,
         jp.estimated_hours_min,
         jp.estimated_hours_max,
         CASE WHEN m.worked_minutes IS NULL THEN NULL ELSE
           COALESCE((
             SELECT sum(ha.agreed_rate)
             FROM   help_requests hr
             JOIN   help_acceptances ha ON ha.help_request_id = hr.id
             WHERE  hr.job_id = dj.id AND ha.status = 'accepted'
           ), 0) * m.worked_minutes / 60.0
         END
  FROM   done_jobs dj
  JOIN   minutes m        ON m.job_id = dj.id
  JOIN   job_proposals jp ON jp.id = dj.accepted_proposal_id
  LEFT JOIN service_types st ON st.id = dj.service_type_id
  WHERE  jp.worker_id = v_uid

  UNION ALL

  -- Ajudante
  SELECT dj.id,
         'helper'::text,
         st.name,
         dj.done_on,
         dj.status,
         'hourly'::text,
         ha.agreed_rate,
         NULL::numeric,
         m.worked_minutes,
         jp.estimated_hours_min,
         jp.estimated_hours_max,
         NULL::numeric
  FROM   done_jobs dj
  JOIN   minutes m          ON m.job_id = dj.id
  JOIN   job_proposals jp   ON jp.id = dj.accepted_proposal_id
  JOIN   help_requests hr   ON hr.job_id = dj.id
  JOIN   help_acceptances ha ON ha.help_request_id = hr.id
  LEFT JOIN service_types st ON st.id = dj.service_type_id
  WHERE  ha.worker_id = v_uid
    AND  ha.status = 'accepted'

  ORDER BY 4 DESC, 1;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_earnings(date, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_earnings(date, date) TO authenticated, service_role;
