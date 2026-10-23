-- ══════════════════════════════════════════════════════════════
-- 0062 — Lembretes de oportunidades, pedido sem propostas (RC5),
--        dicas da época e textos das notificações
-- ══════════════════════════════════════════════════════════════
-- Aplicar depois da 0058 e da 0059 (usa `job_proposals.total_price` e
-- `pricing_mode` da 0058, e as colunas `direct_*` da 0059). Pode correr-se
-- mais do que uma vez.
--
-- 1. Pedido aberto sem propostas, por etapas (cron de hora a hora, só
--    entre as 8h e as 21h de Lisboa, para não acordar ninguém):
--    · ao publicar: aviso aos jardineiros da zona (como antes);
--    · 6 h depois, ainda sem propostas: lembrete aos mesmos jardineiros
--      (no máximo um lembrete por jardineiro a cada 20 h; com vários
--      pedidos junta-os num só aviso);
--    · 24 h depois, ainda sem propostas: o pedido passa a ser mostrado até
--      10 km além do raio de cada jardineiro, avisa os que ficam nessa
--      faixa, e o cliente recebe "Ainda sem propostas" com sugestões
--      (alargar a data, ajustar a descrição, mostrar mais longe).
--    O relógio conta desde que o pedido ficou visível a todos (um pedido
--    direto só conta depois de a reserva acabar).
-- 2. "Mostrar a jardineiros mais longe" (`widen_job_search`): o cliente
--    alarga mais 10 km, até 30 km além do raio.
-- 3. Dicas da época por push (`seasonal_campaigns`): outubro, preparar o
--    jardim para o inverno; fevereiro, limpeza de terrenos. Os textos vivem
--    na tabela (a BD continua sem saber que serviços existem). Quem não
--    quiser desliga em "Dicas da época" (`set_seasonal_tips`).
-- 4. Textos das notificações: um só sítio (trigger BEFORE INSERT em
--    `notifications`) troca os textos genéricos antigos por textos com
--    nomes, valores e distância, sempre a tratar por tu. As funções que
--    criam as notificações não mudam.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de pessoas.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Colunas novas em job_requests ───────────────────────────

ALTER TABLE public.job_requests
  ADD COLUMN IF NOT EXISTS search_extra_km        smallint    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS visible_to_all_at      timestamptz,
  ADD COLUMN IF NOT EXISTS followup_stage         smallint    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS no_proposals_nudged_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'job_requests_search_extra_km_check'
  ) THEN
    ALTER TABLE public.job_requests
      ADD CONSTRAINT job_requests_search_extra_km_check
      CHECK (search_extra_km BETWEEN 0 AND 30);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'job_requests_followup_stage_check'
  ) THEN
    ALTER TABLE public.job_requests
      ADD CONSTRAINT job_requests_followup_stage_check
      CHECK (followup_stage BETWEEN 0 AND 2);
  END IF;
END $$;

COMMENT ON COLUMN public.job_requests.search_extra_km IS
  'Km além do raio de cada jardineiro em que o pedido também aparece (0 a 30). 0062.';
COMMENT ON COLUMN public.job_requests.visible_to_all_at IS
  'Quando o pedido ficou visível a todos (criação, ou fim da reserva do pedido direto). 0062.';
COMMENT ON COLUMN public.job_requests.followup_stage IS
  '0 = só o aviso inicial; 1 = lembrete aos jardineiros enviado; 2 = mostrado mais longe e cliente avisado. 0062.';
COMMENT ON COLUMN public.job_requests.no_proposals_nudged_at IS
  'Quando o cliente recebeu "Ainda sem propostas" (a app mostra as sugestões a partir daqui). 0062.';

-- Pedidos que já existem: não disparar lembretes atrasados ao aplicar.
UPDATE public.job_requests
SET    visible_to_all_at = created_at
WHERE  visible_to_all_at IS NULL
  AND  COALESCE(direct_status, '') NOT IN ('waiting', 'on_hold');

UPDATE public.job_requests
SET    followup_stage = 2
WHERE  status = 'open'
  AND  followup_stage = 0
  AND  created_at < now() - interval '6 hours';

CREATE INDEX IF NOT EXISTS job_requests_open_followup_idx
  ON public.job_requests (followup_stage, visible_to_all_at)
  WHERE status = 'open' AND proposal_count = 0;


-- ── 2. Quando o pedido fica visível a todos; campos só do servidor ──

CREATE OR REPLACE FUNCTION public.job_request_track_visibility()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.search_extra_km        := 0;
    NEW.followup_stage         := 0;
    NEW.no_proposals_nudged_at := NULL;
    NEW.visible_to_all_at :=
      CASE WHEN COALESCE(NEW.direct_status, '') IN ('waiting', 'on_hold')
           THEN NULL ELSE now() END;
    RETURN NEW;
  END IF;

  -- A app (cliente com sessão) não mexe nestes campos: só as RPCs e o cron.
  IF current_setting('request.jwt.claim.sub', true) IS NOT NULL
     AND current_user IN ('authenticated', 'anon')
     AND (NEW.search_extra_km        IS DISTINCT FROM OLD.search_extra_km
       OR NEW.followup_stage         IS DISTINCT FROM OLD.followup_stage
       OR NEW.no_proposals_nudged_at IS DISTINCT FROM OLD.no_proposals_nudged_at
       OR NEW.visible_to_all_at      IS DISTINCT FROM OLD.visible_to_all_at)
  THEN
    RAISE EXCEPTION 'Estes dados do pedido não se podem alterar.';
  END IF;

  -- Fim da reserva do pedido direto: o relógio dos lembretes começa agora.
  IF COALESCE(OLD.direct_status, '') IN ('waiting', 'on_hold')
     AND COALESCE(NEW.direct_status, '') NOT IN ('waiting', 'on_hold')
  THEN
    NEW.visible_to_all_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_request_track_visibility ON job_requests;
CREATE TRIGGER trg_job_request_track_visibility
  BEFORE INSERT OR UPDATE ON job_requests
  FOR EACH ROW EXECUTE FUNCTION job_request_track_visibility();


-- ── 3. Ajudantes ───────────────────────────────────────────────

-- Distância em km (haversine), igual à das outras funções.
CREATE OR REPLACE FUNCTION public.km_between(
  p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT 2 * 6371 * asin(LEAST(1, sqrt(
    power(sin(radians((p_lat2::double precision - p_lat1::double precision) / 2)), 2)
    + cos(radians(p_lat1::double precision))
      * cos(radians(p_lat2::double precision))
      * power(sin(radians((p_lng2::double precision - p_lng1::double precision) / 2)), 2)
  )));
$function$;

-- "12,50 €" / "120 €".
CREATE OR REPLACE FUNCTION public.pt_money(p_value numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_value IS NULL THEN NULL
    WHEN p_value = trunc(p_value) THEN to_char(p_value, 'FM9999990') || ' €'
    ELSE replace(to_char(p_value, 'FM999990.00'), '.', ',') || ' €'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.first_name_of(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT NULLIF(btrim(split_part(btrim(full_name), ' ', 1)), '')
  FROM   profiles
  WHERE  id = p_user AND deleted_at IS NULL;
$function$;

REVOKE EXECUTE ON FUNCTION public.first_name_of(uuid) FROM PUBLIC, anon, authenticated;

-- Jardineiros que podem propor a este pedido (fazem o serviço ou não
-- escolheram serviços, não são o cliente nem foram excluídos, ainda não
-- propuseram), com a distância e o raio de cada um.
CREATE OR REPLACE FUNCTION public.job_candidate_workers(p_job job_requests)
RETURNS TABLE(worker_id uuid, distance_km double precision, radius_km integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT wp.profile_id,
         km_between(wp.base_lat, wp.base_lng, p_job.location_lat, p_job.location_lng),
         wp.radius_km
  FROM   worker_profiles wp
  JOIN   profiles p ON p.id = wp.profile_id AND p.deleted_at IS NULL
  WHERE  wp.profile_id <> p_job.client_id
    AND  NOT (wp.profile_id = ANY(COALESCE(p_job.excluded_worker_ids, '{}'::uuid[])))
    AND  (
           EXISTS (SELECT 1 FROM worker_service_types wst
                   WHERE wst.worker_id = wp.profile_id
                     AND wst.service_type_id = p_job.service_type_id)
           OR NOT EXISTS (SELECT 1 FROM worker_service_types wst
                          WHERE wst.worker_id = wp.profile_id)
         )
    AND  NOT EXISTS (SELECT 1 FROM job_proposals jp
                     WHERE jp.job_id = p_job.id AND jp.worker_id = wp.profile_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.job_candidate_workers(job_requests) FROM PUBLIC, anon, authenticated;

-- Avisa os jardineiros que passam a ver o pedido quando a faixa extra
-- cresce de p_from_km para p_to_km.
CREATE OR REPLACE FUNCTION public.notify_workers_wider_ring(
  p_job job_requests, p_from_km integer, p_to_km integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT c.worker_id,
         'new_job_in_radius',
         'Pedido um pouco mais longe',
         'Ainda ninguém da zona respondeu a este pedido em '
           || job_area_label(p_job.location_area) || ', a '
           || round(c.distance_km)::int || ' km de ti. Se te der jeito, envia proposta.',
         p_job.id,
         'job_request'
  FROM   job_candidate_workers(p_job) c
  WHERE  c.distance_km >  c.radius_km + p_from_km
    AND  c.distance_km <= c.radius_km + p_to_km;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_wider_ring(job_requests, integer, integer) FROM PUBLIC, anon, authenticated;


-- ── 4. Lista do jardineiro: a faixa extra conta ────────────────
-- Igual à 0059, com `d.distance_km <= b.r + jr.search_extra_km` (a caixa
-- de pré-filtro cresce 30 km, o máximo da faixa).

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
           LEAST(GREATEST(radius_km, 1), 50)::double precision + 30 AS rb,
           worker_lat::double precision AS lat,
           worker_lng::double precision AS lng
  )
  SELECT mask_job_location(jr)
  FROM   box b
  JOIN   public.job_requests jr
    ON   jr.status = 'open'
   AND   (
           (jr.location_lat BETWEEN b.lat - b.rb / 111.0 AND b.lat + b.rb / 111.0
            AND jr.location_lng BETWEEN b.lng - b.rb / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
                                    AND b.lng + b.rb / (111.0 * GREATEST(cos(radians(b.lat)), 0.01)))
           OR (jr.direct_status IN ('waiting', 'on_hold') AND jr.direct_worker_id = auth.uid())
         )
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((jr.location_lat::double precision - b.lat) / 2)), 2)
      + cos(radians(b.lat))
        * cos(radians(jr.location_lat::double precision))
        * power(sin(radians((jr.location_lng::double precision - b.lng) / 2)), 2)
    ))) AS distance_km
  ) d
  CROSS JOIN LATERAL (
    SELECT jr.direct_worker_id = auth.uid()
           AND (
             (jr.direct_status = 'waiting'
               AND (jr.direct_until > now() OR NOT jr.direct_auto_release))
             OR (jr.direct_status = 'on_hold' AND jr.direct_hold_reason = 'expired')
           ) AS for_me
  ) dr
  WHERE  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT (jr.date_mode = 'fixed' AND jr.preferred_date < today_pt())
    AND  NOT job_reserved_for_other(jr.direct_status, jr.direct_until,
                                    jr.direct_worker_id, auth.uid(),
                                    jr.direct_auto_release)
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  (d.distance_km <= b.r + jr.search_extra_km OR COALESCE(dr.for_me, false))
  ORDER BY COALESCE(dr.for_me, false) DESC, d.distance_km ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;


-- ── 5. Mostrar mais longe (cron e botão do cliente) ────────────

CREATE OR REPLACE FUNCTION public.widen_job_reach(p_job_id uuid, p_step integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
  v_new integer;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  v_new := LEAST(v_job.search_extra_km + p_step, 30);
  IF v_new <= v_job.search_extra_km THEN
    RETURN v_job.search_extra_km;
  END IF;

  UPDATE job_requests
  SET    search_extra_km = v_new,
         -- Quem passa a ver o pedido precisa de tempo para responder.
         expires_at      = GREATEST(expires_at, now() + interval '24 hours'),
         updated_at      = now()
  WHERE  id = p_job_id;

  PERFORM notify_workers_wider_ring(v_job, v_job.search_extra_km, v_new);
  RETURN v_new;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.widen_job_reach(uuid, integer) FROM PUBLIC, anon, authenticated;

-- "Mostrar a jardineiros mais longe" (cliente). Devolve os km extra.
CREATE OR REPLACE FUNCTION public.widen_job_search(p_job_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id;
  IF v_job.id IS NULL OR v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está aberto.';
  END IF;
  IF COALESCE(v_job.direct_status, '') IN ('waiting', 'on_hold') THEN
    RAISE EXCEPTION 'Este pedido ainda está reservado a um jardineiro. Mostra-o primeiro a todos.';
  END IF;
  IF v_job.search_extra_km >= 30 THEN
    RAISE EXCEPTION 'O pedido já está a ser mostrado o mais longe possível.';
  END IF;

  UPDATE job_requests
  SET    followup_stage = 2,
         no_proposals_nudged_at = COALESCE(no_proposals_nudged_at, now())
  WHERE  id = p_job_id;

  RETURN widen_job_reach(p_job_id, 10);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.widen_job_search(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.widen_job_search(uuid) TO authenticated;


-- ── 6. Cron: lembrete às 6 h, mais longe às 24 h ───────────────

CREATE OR REPLACE FUNCTION public.process_open_job_followups()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hour   integer := extract(hour FROM now() AT TIME ZONE 'Europe/Lisbon');
  v_job    job_requests;
  v_ids    uuid[];
  r        record;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;
  -- Só de dia: um pedido que faz 6 h às 3 da manhã espera pelas 8h.
  IF v_hour < 8 OR v_hour >= 21 THEN
    RETURN;
  END IF;

  -- 6.1 24 h sem propostas: mostrar 10 km mais longe e avisar o cliente.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status = 'open'
      AND  proposal_count = 0
      AND  followup_stage < 2
      AND  visible_to_all_at IS NOT NULL
      AND  visible_to_all_at <= now() - interval '24 hours'
      AND  COALESCE(direct_status, '') NOT IN ('waiting', 'on_hold')
      AND  expires_at > now()
      AND  NOT (date_mode = 'fixed' AND preferred_date < today_pt())
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    followup_stage = 2, no_proposals_nudged_at = now()
    WHERE  id = v_job.id;

    IF v_job.search_extra_km < 10 THEN
      PERFORM widen_job_reach(v_job.id, 10 - v_job.search_extra_km);
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_proposals_yet', 'Ainda sem propostas',
      'Já mostrámos o teu pedido a jardineiros um pouco mais longe. Também ajuda alargar a data ou juntar mais detalhes à descrição.',
      v_job.id, 'job_request');
  END LOOP;

  -- 6.2 6 h sem propostas: lembrete aos jardineiros que o veem.
  SELECT array_agg(id) INTO v_ids
  FROM   job_requests
  WHERE  status = 'open'
    AND  proposal_count = 0
    AND  followup_stage = 0
    AND  visible_to_all_at IS NOT NULL
    AND  visible_to_all_at <= now() - interval '6 hours'
    AND  COALESCE(direct_status, '') NOT IN ('waiting', 'on_hold')
    AND  expires_at > now()
    AND  NOT (date_mode = 'fixed' AND preferred_date < today_pt());

  IF v_ids IS NULL THEN
    RETURN;
  END IF;

  UPDATE job_requests SET followup_stage = 1 WHERE id = ANY(v_ids);

  -- Um aviso por jardineiro: com um pedido diz qual; com vários junta-os.
  -- Quem já teve um lembrete nas últimas 20 h fica de fora.
  FOR r IN
    WITH pairs AS (
      SELECT c.worker_id, jr.id AS job_id, jr.location_area, c.distance_km
      FROM   job_requests jr
      CROSS JOIN LATERAL job_candidate_workers(jr) c
      WHERE  jr.id = ANY(v_ids)
        AND  c.distance_km <= c.radius_km + jr.search_extra_km
    )
    SELECT p.worker_id,
           count(*)                       AS n,
           (array_agg(p.job_id ORDER BY p.distance_km))[1]        AS job_id,
           (array_agg(p.location_area ORDER BY p.distance_km))[1] AS area,
           min(p.distance_km)             AS distance_km
    FROM   pairs p
    WHERE  NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE  n.user_id = p.worker_id
        AND  n.type = 'job_opportunity_reminder'
        AND  n.created_at > now() - interval '20 hours'
    )
    GROUP  BY p.worker_id
  LOOP
    IF r.n = 1 THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.worker_id, 'job_opportunity_reminder', 'Ainda ninguém enviou proposta',
        'O pedido em ' || job_area_label(r.area) || ', a ' || round(r.distance_km)::int
          || ' km de ti, continua sem propostas. Quem responde primeiro tem mais hipóteses.',
        r.job_id, 'job_request');
    ELSE
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.worker_id, 'job_opportunity_reminder', r.n || ' pedidos sem propostas perto de ti',
        'Há ' || r.n || ' pedidos na tua zona à espera da primeira proposta. Vê-os em Pedidos disponíveis.',
        NULL, NULL);
    END IF;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_open_job_followups() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'open-job-followups',
  '15 * * * *',
  'SELECT process_open_job_followups()'
);


-- ── 7. Dicas da época ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.seasonal_campaigns (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  month       smallint NOT NULL CHECK (month BETWEEN 1 AND 12),
  day         smallint NOT NULL DEFAULT 1 CHECK (day BETWEEN 1 AND 28),
  audience    text NOT NULL DEFAULT 'client' CHECK (audience IN ('client', 'worker')),
  title       text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 80),
  body        text NOT NULL CHECK (char_length(body) BETWEEN 10 AND 240),
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.seasonal_campaign_sends (
  campaign_id uuid NOT NULL REFERENCES seasonal_campaigns(id) ON DELETE CASCADE,
  year        smallint NOT NULL,
  recipients  integer NOT NULL DEFAULT 0,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, year)
);

ALTER TABLE public.seasonal_campaigns      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seasonal_campaign_sends ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.seasonal_campaigns, public.seasonal_campaign_sends FROM anon, authenticated;

INSERT INTO public.seasonal_campaigns (slug, month, day, audience, title, body)
VALUES
  ('preparar-inverno', 10, 1, 'client',
   'Prepara o jardim para o inverno',
   'Outubro é boa altura para podar, apanhar as folhas e proteger as plantas do frio. Pede orçamento a um jardineiro da tua zona.'),
  ('limpeza-terrenos', 2, 1, 'client',
   'Altura de limpar o terreno',
   'Fevereiro é a altura certa para limpar o terreno antes da primavera e do calor. Pede já orçamento, antes de as agendas encherem.')
ON CONFLICT (slug) DO NOTHING;

-- Preferência "Dicas da época" (ligada por omissão).
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id        uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  seasonal_tips  boolean NOT NULL DEFAULT true,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_preferences FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_notification_preferences()
RETURNS TABLE(seasonal_tips boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT np.seasonal_tips FROM notification_preferences np WHERE np.user_id = auth.uid()),
    true
  )
  WHERE auth.uid() IS NOT NULL;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_notification_preferences() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_notification_preferences() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_seasonal_tips(p_enabled boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão necessária.';
  END IF;
  INSERT INTO notification_preferences (user_id, seasonal_tips, updated_at)
  VALUES (auth.uid(), COALESCE(p_enabled, true), now())
  ON CONFLICT (user_id) DO UPDATE
    SET seasonal_tips = EXCLUDED.seasonal_tips, updated_at = now();
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_seasonal_tips(boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_seasonal_tips(boolean) TO authenticated;

-- Envia as dicas do mês a partir do dia marcado, uma vez por ano. Se o
-- cron falhar um dia, envia no seguinte (dentro do mesmo mês).
CREATE OR REPLACE FUNCTION public.send_seasonal_campaigns()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := today_pt();
  v_year  smallint := extract(year FROM v_today);
  c       seasonal_campaigns;
  v_count integer;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  FOR c IN
    SELECT * FROM seasonal_campaigns sc
    WHERE  sc.active
      AND  sc.month = extract(month FROM v_today)
      AND  sc.day  <= extract(day FROM v_today)
      AND  NOT EXISTS (SELECT 1 FROM seasonal_campaign_sends s
                       WHERE s.campaign_id = sc.id AND s.year = v_year)
  LOOP
    -- Marca primeiro: se algo falhar a meio, não se repete no dia seguinte.
    INSERT INTO seasonal_campaign_sends (campaign_id, year) VALUES (c.id, v_year);

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT p.id, 'seasonal_tip', c.title, c.body, c.id, 'seasonal_campaign'
    FROM   profiles p
    LEFT JOIN notification_preferences np ON np.user_id = p.id
    WHERE  p.role = c.audience
      AND  p.deleted_at IS NULL
      AND  COALESCE(np.seasonal_tips, true);
    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE seasonal_campaign_sends SET recipients = v_count
    WHERE  campaign_id = c.id AND year = v_year;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_seasonal_campaigns() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'seasonal-campaigns',
  '0 10 * * *',
  'SELECT send_seasonal_campaigns()'
);


-- ── 8. Textos das notificações num só sítio ────────────────────
-- Trigger BEFORE INSERT já existente (0049): além de juntar "(Serviço,
-- DD/MM)" ao fim, troca os textos genéricos das funções antigas por
-- textos com nomes, valores e distância. Só mexe quando o texto é o
-- antigo, por isso os textos novos escritos nas funções ficam como estão.

CREATE OR REPLACE FUNCTION public.notifications_add_job_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_id  uuid;
  v_job     job_requests;
  v_service text;
  v_date    date;
  v_context text;
  v_name    text;
  v_price   text;
  v_km      integer;
  v_prop    job_proposals;
BEGIN
  BEGIN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id AND deleted_at IS NOT NULL
    ) THEN
      RETURN NULL;
    END IF;

    IF NEW.related_id IS NULL OR NEW.related_type IS NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.related_type = 'job_request' THEN
      v_job_id := NEW.related_id;
    ELSIF NEW.related_type = 'help_request' THEN
      SELECT job_id INTO v_job_id FROM help_requests WHERE id = NEW.related_id;
    END IF;

    IF v_job_id IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT * INTO v_job FROM job_requests WHERE id = v_job_id;

    -- Textos antigos → textos com quem e quanto.
    IF NEW.related_type = 'job_request' THEN
      CASE NEW.type
        WHEN 'new_job_in_radius' THEN
          IF NEW.title = 'Novo pedido perto de ti' THEN
            SELECT round(km_between(wp.base_lat, wp.base_lng,
                                    v_job.location_lat, v_job.location_lng))::int
            INTO   v_km
            FROM   worker_profiles wp WHERE wp.profile_id = NEW.user_id;
            NEW.body := 'Pedido novo em ' || job_area_label(v_job.location_area)
              || COALESCE(', a ' || v_km || ' km de ti', '')
              || '. Sê o primeiro a enviar proposta.';
          END IF;

        WHEN 'proposal_received' THEN
          IF NEW.body = 'Um jardineiro enviou uma proposta para o seu pedido.' THEN
            SELECT * INTO v_prop FROM job_proposals
            WHERE  job_id = v_job_id AND status = 'pending'
            ORDER  BY created_at DESC LIMIT 1;
            v_name := first_name_of(v_prop.worker_id);
            v_price := CASE
              WHEN v_prop.pricing_mode = 'fixed_total' AND v_prop.total_price IS NOT NULL
                THEN pt_money(v_prop.total_price) || ' no total'
              WHEN v_prop.hourly_rate IS NOT NULL
                THEN pt_money(v_prop.hourly_rate) || '/h'
            END;
            NEW.title := 'Nova proposta' || COALESCE(' de ' || v_name, '');
            NEW.body := COALESCE(v_name, 'Um jardineiro') || ' enviou uma proposta'
              || COALESCE(': ' || v_price, '')
              || CASE WHEN v_job.proposal_count > 1
                      THEN '. Já tens ' || v_job.proposal_count || ' propostas para comparar.'
                      ELSE '. Vê os detalhes e decide quando quiseres.' END;
          END IF;

        WHEN 'proposal_withdrawn' THEN
          IF NEW.body IN ('Um jardineiro retirou a sua proposta.',
                          'Um jardineiro retirou a proposta que te tinha feito.') THEN
            SELECT first_name_of(worker_id) INTO v_name FROM job_proposals
            WHERE  job_id = v_job_id AND status = 'withdrawn'
            ORDER  BY updated_at DESC LIMIT 1;
            NEW.body := COALESCE(v_name, 'Um jardineiro') || ' retirou a proposta.'
              || CASE WHEN v_job.proposal_count > 0
                      THEN ' As outras continuam à tua espera.'
                      ELSE ' O pedido continua aberto a outros jardineiros.' END;
          END IF;

        WHEN 'proposal_accepted' THEN
          IF NEW.body = 'O cliente aceitou a sua proposta.' THEN
            v_name := first_name_of(v_job.client_id);
            NEW.title := 'Proposta aceite';
            NEW.body := COALESCE(v_name, 'O cliente')
              || ' aceitou a tua proposta. Combina os pormenores por WhatsApp.';
          END IF;

        WHEN 'proposal_rejected' THEN
          IF NEW.body = 'O cliente recusou a sua proposta.' THEN
            NEW.body := 'O cliente recusou a tua proposta. Há mais pedidos à tua espera.';
          ELSIF NEW.body = 'O cliente escolheu outra proposta.' THEN
            NEW.body := 'O cliente escolheu outra proposta. Há mais pedidos à tua espera.';
          END IF;

        WHEN 'job_cancelled' THEN
          IF NEW.body = 'Um pedido foi cancelado.' THEN
            v_name := first_name_of(v_job.cancelled_by);
            IF NEW.user_id = v_job.client_id THEN
              NEW.title := 'Trabalho cancelado';
              NEW.body := COALESCE(v_name, 'O jardineiro')
                || ' cancelou o trabalho. Vamos mostrar o pedido de novo a outros jardineiros.';
            ELSE
              NEW.title := 'Trabalho cancelado';
              NEW.body := COALESCE(v_name, 'O cliente') || ' cancelou o trabalho.';
            END IF;
          END IF;

        WHEN 'job_reopened' THEN
          IF NEW.body = 'O pedido foi reaberto automaticamente.' THEN
            NEW.title := 'O teu pedido voltou a estar aberto';
            NEW.body := 'Já está visível para outros jardineiros. As novas propostas aparecem aqui.';
          END IF;

        WHEN 'job_started' THEN
          IF NEW.body = 'O jardineiro começou o trabalho.' THEN
            SELECT first_name_of(jp.worker_id) INTO v_name
            FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;
            NEW.body := COALESCE(v_name, 'O jardineiro') || ' começou o trabalho.';
          END IF;

        WHEN 'reschedule_proposed' THEN
          IF NEW.body = 'A outra parte propôs uma nova data para o trabalho.' THEN
            v_name := first_name_of(v_job.reschedule_proposed_by);
            NEW.title := 'Pedido de nova data';
            NEW.body := COALESCE(v_name, 'A outra pessoa') || ' propôs mudar o trabalho para '
              || COALESCE(to_char(v_job.reschedule_proposed_date, 'DD/MM'), 'outra data')
              || '. Aceita ou recusa na app.';
          END IF;

        WHEN 'reschedule_accepted' THEN
          IF NEW.body = 'A nova data foi aceite.' THEN
            NEW.title := 'Nova data aceite';
            NEW.body := 'O trabalho passou para '
              || COALESCE(to_char(v_job.confirmed_date, 'DD/MM'), 'a nova data') || '.';
          END IF;

        WHEN 'job_no_response' THEN
          IF NEW.title = 'Sem resposta' THEN
            NEW.title := 'Pedido sem propostas';
            NEW.body := 'O teu pedido fechou sem propostas. Podes publicá-lo de novo, com outra data ou mais detalhes.';
          END IF;

        ELSE
          NULL;
      END CASE;
    END IF;

    IF NEW.type = 'help_rejected'
       AND NEW.body = 'O worker principal não selecionou a tua candidatura.' THEN
      NEW.body := 'O jardineiro responsável escolheu outra pessoa para esta vaga.';
    END IF;

    SELECT st.name, COALESCE(jr.confirmed_date, jr.preferred_date)
    INTO   v_service, v_date
    FROM   job_requests  jr
    JOIN   service_types st ON st.id = jr.service_type_id
    WHERE  jr.id = v_job_id;

    IF v_service IS NULL OR btrim(v_service) = '' THEN
      RETURN NEW;
    END IF;

    v_context := v_service || COALESCE(', ' || to_char(v_date, 'DD/MM'), '');

    IF NEW.body IS NOT NULL AND strpos(NEW.body, '(' || v_context || ')') = 0 THEN
      NEW.body := NEW.body || ' (' || v_context || ')';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
  END;

  RETURN NEW;
END;
$function$;


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select jobname, schedule, active from cron.job
--  where jobname in ('open-job-followups', 'seasonal-campaigns');
-- select slug, month, day, audience, active, title from seasonal_campaigns;
--
-- Pedidos abertos sem propostas e em que etapa estão:
-- select id, created_at, visible_to_all_at, followup_stage, search_extra_km,
--        no_proposals_nudged_at
--   from job_requests where status = 'open' and proposal_count = 0
--  order by created_at desc;
--
-- Dicas enviadas por ano:
-- select c.slug, s.year, s.recipients, s.sent_at
--   from seasonal_campaign_sends s join seasonal_campaigns c on c.id = s.campaign_id;
--
-- Mudar um texto ou desligar uma dica:
-- update seasonal_campaigns set body = '...' where slug = 'limpeza-terrenos';
-- update seasonal_campaigns set active = false where slug = 'preparar-inverno';
