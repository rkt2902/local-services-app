-- ══════════════════════════════════════════════════════════════
-- 0057 — Pedir de novo ao mesmo jardineiro (pedido direto)
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0056
-- (redefine notify_workers_new_job da 0054 e get_jobs_in_radius da 0046).
-- Pode correr-se mais do que uma vez sem erro.
--
-- Design A5 (22/10). Depois de um trabalho concluído, o cliente pede de
-- novo ao mesmo jardineiro: o pedido novo nasce `open` como qualquer
-- outro, mas durante 24 horas só esse jardineiro o vê e pode propor.
-- Acaba a exclusividade quando:
--   - o jardineiro diz "Não posso desta vez" (declined);
--   - passam as 24 horas (expired, cron de 5 em 5 minutos);
--   - o cliente toca "Mostrar já a todos" (released);
--   - o cliente recusa a proposta dele, ou ele retira-a.
-- Depois disso o pedido fica visível a todos e os jardineiros da zona
-- recebem o aviso normal de pedido novo. Não há JobStatus novo: o pedido
-- continua `open`; o estado da exclusividade vive em `direct_status`.
--
-- Como o cliente escolhe o jardineiro sem a app mandar um id de
-- utilizador: o INSERT leva `direct_source_job_id` (o trabalho concluído
-- de onde vem o pedido) e um trigger BEFORE INSERT tira o jardineiro da
-- proposta aceite desse trabalho, depois de confirmar que o trabalho é do
-- cliente e está concluído. Qualquer valor que a app mande em
-- direct_worker_id/direct_until/direct_status é ignorado.
--
-- RPCs novas (identidade sempre por auth.uid(), só recebem p_job_id):
--   release_direct_job_request(p_job_id)   cliente: "Mostrar já a todos"
--   decline_direct_job_request(p_job_id)   jardineiro: "Não posso desta vez"
--   get_repeat_hire_for_job(p_job_id)      cliente: cartão "Precisas outra vez?"
--   get_my_previous_workers()              cliente: "Os teus jardineiros"
--   get_direct_request_context(p_job_id)   jardineiro: "Já trabalhaste com..."
--
-- Tipos novos de notificação: `direct_job_request` (ao jardineiro) e
-- `direct_request_released` (ao cliente, quando ele recusa ou o prazo
-- acaba).
-- ══════════════════════════════════════════════════════════════


-- ── 1. Colunas ──────────────────────────────────────────────────

ALTER TABLE job_requests
  ADD COLUMN IF NOT EXISTS direct_worker_id     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS direct_source_job_id uuid REFERENCES job_requests(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS direct_until         timestamptz,
  ADD COLUMN IF NOT EXISTS direct_status        text;

ALTER TABLE job_requests DROP CONSTRAINT IF EXISTS job_requests_direct_status_check;
ALTER TABLE job_requests ADD CONSTRAINT job_requests_direct_status_check
  CHECK (direct_status IN ('waiting', 'declined', 'expired', 'released'));

CREATE INDEX IF NOT EXISTS job_requests_direct_waiting_idx
  ON job_requests (direct_until)
  WHERE direct_status = 'waiting';


-- ── 2. Helper: o pedido está reservado a outro jardineiro? ──────
-- Só conta o tempo: assim que o prazo passa, o pedido abre a todos sem
-- esperar pelo cron (que depois só muda o estado e avisa).

CREATE OR REPLACE FUNCTION public.job_reserved_for_other(
  p_direct_status    text,
  p_direct_until     timestamptz,
  p_direct_worker_id uuid,
  p_worker_id        uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT p_direct_status = 'waiting'
     AND p_direct_until  > now()
     AND p_direct_worker_id IS DISTINCT FROM p_worker_id;
$function$;


-- ── 3. Ao criar o pedido: resolve o jardineiro ──────────────────

CREATE OR REPLACE FUNCTION public.job_request_direct_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id uuid;
BEGIN
  NEW.direct_worker_id := NULL;
  NEW.direct_until     := NULL;
  NEW.direct_status    := NULL;

  IF NEW.direct_source_job_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT jp.worker_id INTO v_worker_id
  FROM   job_requests  src
  JOIN   job_proposals jp ON jp.id = src.accepted_proposal_id
  WHERE  src.id        = NEW.direct_source_job_id
    AND  src.client_id = NEW.client_id
    AND  src.status    = 'completed';

  IF v_worker_id IS NULL THEN
    RAISE EXCEPTION 'Só podes pedir de novo a um jardineiro com quem já concluíste um trabalho.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM worker_profiles WHERE profile_id = v_worker_id) THEN
    RAISE EXCEPTION 'Este jardineiro já não aceita pedidos.';
  END IF;

  NEW.direct_worker_id := v_worker_id;
  NEW.direct_until     := now() + interval '24 hours';
  NEW.direct_status    := 'waiting';
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_request_direct_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_job_request_direct_before_insert ON job_requests;
CREATE TRIGGER trg_job_request_direct_before_insert
  BEFORE INSERT ON job_requests
  FOR EACH ROW EXECUTE FUNCTION job_request_direct_before_insert();


-- ── 4. Avisos de pedido novo ────────────────────────────────────
-- O corpo da 0054 passa para notify_workers_job_open, que também serve
-- quando um pedido direto abre a todos. Nunca avisa o jardineiro do
-- pedido direto outra vez (já teve o aviso dele, ou recusou).

CREATE OR REPLACE FUNCTION public.notify_workers_job_open(p_job job_requests)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    wp.profile_id,
    'new_job_in_radius',
    'Novo pedido perto de ti',
    'Há um pedido novo na tua zona. Vê os detalhes e envia a tua proposta.',
    p_job.id,
    'job_request'
  FROM worker_profiles wp
  WHERE wp.profile_id <> p_job.client_id
    AND wp.profile_id IS DISTINCT FROM p_job.direct_worker_id
    AND NOT (wp.profile_id = ANY(COALESCE(p_job.excluded_worker_ids, '{}'::uuid[])))
    AND (
      EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
          AND  wst.service_type_id = p_job.service_type_id
      )
      OR NOT EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
      )
    )
    AND (
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((p_job.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
        + cos(radians(wp.base_lat::double precision))
          * cos(radians(p_job.location_lat::double precision))
          * power(sin(radians((p_job.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
      )))
    ) <= wp.radius_km;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_job_open(job_requests) FROM PUBLIC, anon, authenticated;

-- Mesmo nome da 0054 (o trigger on_job_created / trigger_notify_workers_new_job
-- aponta para esta função). Pedido direto: só o jardineiro escolhido.
CREATE OR REPLACE FUNCTION public.notify_workers_new_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.direct_status = 'waiting' AND NEW.direct_worker_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      NEW.direct_worker_id,
      'direct_job_request',
      'Pedido só para ti',
      'Um cliente com quem já trabalhaste pediu-te um trabalho. Tens 24 horas para responder antes de o pedido abrir a outros jardineiros.',
      NEW.id,
      'job_request'
    );
    RETURN NEW;
  END IF;

  PERFORM notify_workers_job_open(NEW);
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_new_job() FROM PUBLIC, anon, authenticated;


-- ── 5. Abrir a todos (núcleo, só interno) ───────────────────────
-- p_status: 'declined', 'expired' ou 'released'. Dá ao pedido as mesmas
-- 48h para receber propostas que um pedido normal tem, contadas a partir
-- de agora. Avisa o cliente quando não foi ele a abrir.

CREATE OR REPLACE FUNCTION public.open_direct_job_to_all(
  p_job_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job         job_requests%ROWTYPE;
  v_worker_name text;
BEGIN
  IF p_status NOT IN ('declined', 'expired', 'released') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  UPDATE job_requests
  SET    direct_status = p_status,
         excluded_worker_ids = CASE
           WHEN p_status = 'declined' AND NOT (direct_worker_id = ANY(excluded_worker_ids))
             THEN array_append(excluded_worker_ids, direct_worker_id)
           ELSE excluded_worker_ids
         END,
         expires_at = GREATEST(expires_at, now() + interval '48 hours'),
         updated_at = now()
  WHERE  id = p_job_id
    AND  status = 'open'
    AND  direct_status = 'waiting'
  RETURNING * INTO v_job;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM notify_workers_job_open(v_job);

  IF p_status IN ('declined', 'expired') THEN
    SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_worker_name
    FROM   profiles WHERE id = v_job.direct_worker_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_job.client_id,
      'direct_request_released',
      CASE WHEN p_status = 'declined'
           THEN COALESCE(v_worker_name, 'O jardineiro') || ' não pode desta vez'
           ELSE COALESCE(v_worker_name, 'O jardineiro') || ' não respondeu a tempo'
      END,
      'O teu pedido já está visível para outros jardineiros da zona.',
      v_job.id,
      'job_request'
    );
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.open_direct_job_to_all(uuid, text) FROM PUBLIC, anon, authenticated;


-- ── 6. RPCs: "Mostrar já a todos" e "Não posso desta vez" ───────

CREATE OR REPLACE FUNCTION public.release_direct_job_request(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;

  IF NOT FOUND OR v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está aberto.';
  END IF;
  -- Já aberto a todos (recusou, prazo, ou dois toques): nada a fazer.
  IF v_job.direct_status IS DISTINCT FROM 'waiting' THEN
    RETURN;
  END IF;

  PERFORM open_direct_job_to_all(p_job_id, 'released');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.release_direct_job_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.release_direct_job_request(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.decline_direct_job_request(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;

  IF NOT FOUND OR v_job.direct_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'open' OR v_job.direct_status IS DISTINCT FROM 'waiting' THEN
    RAISE EXCEPTION 'Este pedido já está visível para outros jardineiros.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já enviaste uma proposta para este pedido. Retira-a primeiro.';
  END IF;

  PERFORM open_direct_job_to_all(p_job_id, 'declined');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.decline_direct_job_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decline_direct_job_request(uuid) TO authenticated, service_role;


-- ── 7. Propostas durante a exclusividade ────────────────────────
-- Antes de inserir: só o jardineiro escolhido propõe. Trigger em vez de
-- mexer na create_proposal (fica igual à 0044).

CREATE OR REPLACE FUNCTION public.job_proposal_direct_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM job_requests jr
    WHERE  jr.id = NEW.job_id
      AND  job_reserved_for_other(jr.direct_status, jr.direct_until, jr.direct_worker_id, NEW.worker_id)
  ) THEN
    RAISE EXCEPTION 'Este pedido ainda está reservado a outro jardineiro.';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_proposal_direct_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_job_proposal_direct_before_insert ON job_proposals;
CREATE TRIGGER trg_job_proposal_direct_before_insert
  BEFORE INSERT ON job_proposals
  FOR EACH ROW EXECUTE FUNCTION job_proposal_direct_before_insert();

-- Depois de mudar: o cliente recusou a proposta do jardineiro escolhido
-- (abre a todos, sem aviso ao cliente) ou ele retirou-a (conta como
-- "não pode desta vez").
CREATE OR REPLACE FUNCTION public.job_proposal_direct_after_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'pending' AND NEW.status IN ('rejected', 'superseded')
     AND EXISTS (
       SELECT 1 FROM job_requests jr
       WHERE  jr.id = NEW.job_id
         AND  jr.status = 'open'
         AND  jr.direct_status = 'waiting'
         AND  jr.direct_worker_id = NEW.worker_id
     )
  THEN
    PERFORM open_direct_job_to_all(
      NEW.job_id,
      CASE WHEN NEW.status = 'superseded' THEN 'declined' ELSE 'released' END
    );
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_proposal_direct_after_update() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_job_proposal_direct_after_update ON job_proposals;
CREATE TRIGGER trg_job_proposal_direct_after_update
  AFTER UPDATE OF status ON job_proposals
  FOR EACH ROW EXECUTE FUNCTION job_proposal_direct_after_update();


-- ── 8. Visibilidade para os outros jardineiros ──────────────────

-- 8.1 Igual à 0043, mais: o id do jardineiro escolhido e do trabalho de
-- origem só os vê o próprio jardineiro escolhido.
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
      'location_lng', round(p_job.location_lng, 2),
      'direct_worker_id', CASE WHEN p_job.direct_worker_id = auth.uid()
                               THEN p_job.direct_worker_id END,
      'direct_source_job_id', CASE WHEN p_job.direct_worker_id = auth.uid()
                                   THEN p_job.direct_source_job_id END
    )
  );
$function$;

-- 8.2 Igual à 0043, mais a reserva no ramo da oportunidade aberta.
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
          AND NOT (auth.uid() = ANY(jr.excluded_worker_ids))
          AND NOT job_reserved_for_other(jr.direct_status, jr.direct_until, jr.direct_worker_id, auth.uid()))
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

-- 8.3 Igual à 0046, mais: os pedidos reservados a outro não aparecem; o
-- pedido direto para mim aparece mesmo fora do meu raio, e primeiro.
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
   AND   (
           (jr.location_lat BETWEEN b.lat - b.r / 111.0 AND b.lat + b.r / 111.0
            AND jr.location_lng BETWEEN b.lng - b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
                                    AND b.lng + b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01)))
           OR (jr.direct_status = 'waiting' AND jr.direct_worker_id = auth.uid())
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
    SELECT (jr.direct_status = 'waiting'
            AND jr.direct_until > now()
            AND jr.direct_worker_id = auth.uid()) AS for_me
  ) dr
  WHERE  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT (jr.date_mode = 'fixed' AND jr.preferred_date < today_pt())
    AND  NOT job_reserved_for_other(jr.direct_status, jr.direct_until, jr.direct_worker_id, auth.uid())
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  (d.distance_km <= b.r OR dr.for_me)
  ORDER BY dr.for_me DESC, d.distance_km ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;

-- 8.4 Igual à 0040, mais a reserva (o nome do cliente não aparece a quem
-- não pode ver o pedido).
CREATE OR REPLACE FUNCTION public.get_open_job_client_identity(p_job_id uuid)
RETURNS TABLE(client_name text, client_avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.full_name, p.avatar_url
  FROM   job_requests jr
  JOIN   profiles     p ON p.id = jr.client_id
  WHERE  jr.id = p_job_id
    AND  jr.status = 'open'
    AND  NOT job_reserved_for_other(jr.direct_status, jr.direct_until, jr.direct_worker_id, auth.uid());
$function$;


-- ── 9. Leituras para os ecrãs ───────────────────────────────────

-- 9.1 Cartão "Precisas outra vez?" no detalhe de um trabalho concluído.
-- Uma linha, ou nenhuma se o trabalho não é do cliente ou não está
-- concluído. `can_request` falso quando o jardineiro já não tem perfil.
-- `my_stars` é a nota que o cliente deu (a app esconde o cartão com 1 a 3).
CREATE OR REPLACE FUNCTION public.get_repeat_hire_for_job(p_job_id uuid)
RETURNS TABLE(
  worker_id         uuid,
  worker_name       text,
  worker_avatar_url text,
  service_type_id   uuid,
  job_date          date,
  can_request       boolean,
  my_stars          integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jp.worker_id,
         p.full_name,
         p.avatar_url,
         jr.service_type_id,
         COALESCE(jr.confirmed_date, jr.updated_at::date),
         EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = jp.worker_id),
         (SELECT r.stars FROM ratings r
          WHERE  r.job_id = jr.id AND r.rater_id = auth.uid() AND r.ratee_id = jp.worker_id)
  FROM   job_requests  jr
  JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
  LEFT JOIN profiles   p  ON p.id  = jp.worker_id
  WHERE  jr.id        = p_job_id
    AND  jr.client_id = auth.uid()
    AND  jr.status    = 'completed';
$function$;

REVOKE EXECUTE ON FUNCTION public.get_repeat_hire_for_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_repeat_hire_for_job(uuid) TO authenticated, service_role;

-- 9.2 "Os teus jardineiros" no Início: o último trabalho concluído com
-- cada jardineiro que ainda tem perfil, sem os que levaram 1 a 3 estrelas
-- do cliente nesse trabalho. Os 10 mais recentes.
CREATE OR REPLACE FUNCTION public.get_my_previous_workers()
RETURNS TABLE(
  worker_id         uuid,
  worker_name       text,
  worker_avatar_url text,
  last_job_id       uuid,
  service_type_id   uuid,
  job_date          date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT w.worker_id, p.full_name, p.avatar_url, w.job_id, w.service_type_id, w.job_date
  FROM (
    SELECT DISTINCT ON (jp.worker_id)
           jp.worker_id,
           jr.id AS job_id,
           jr.service_type_id,
           COALESCE(jr.confirmed_date, jr.updated_at::date) AS job_date
    FROM   job_requests  jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.client_id = auth.uid()
      AND  jr.status    = 'completed'
    ORDER BY jp.worker_id, COALESCE(jr.confirmed_date, jr.updated_at::date) DESC, jr.updated_at DESC
  ) w
  JOIN   profiles        p  ON p.id = w.worker_id
  JOIN   worker_profiles wp ON wp.profile_id = w.worker_id
  WHERE  NOT EXISTS (
    SELECT 1 FROM ratings r
    WHERE  r.job_id = w.job_id AND r.rater_id = auth.uid()
      AND  r.ratee_id = w.worker_id AND r.stars < 4
  )
  ORDER BY w.job_date DESC
  LIMIT 10;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_previous_workers() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_previous_workers() TO authenticated, service_role;

-- 9.3 "Já trabalhaste com ... a ..., ..., ... €/h" no detalhe da
-- oportunidade. Só para o jardineiro escolhido; usa o trabalho de origem.
CREATE OR REPLACE FUNCTION public.get_direct_request_context(p_job_id uuid)
RETURNS TABLE(
  client_name     text,
  job_date        date,
  service_type_id uuid,
  hourly_rate     numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.full_name,
         COALESCE(src.confirmed_date, src.updated_at::date),
         src.service_type_id,
         jp.hourly_rate
  FROM   job_requests  jr
  JOIN   job_requests  src ON src.id = jr.direct_source_job_id
  JOIN   job_proposals jp  ON jp.id  = src.accepted_proposal_id
                          AND jp.worker_id = auth.uid()
  LEFT JOIN profiles   p   ON p.id   = jr.client_id
  WHERE  jr.id = p_job_id
    AND  jr.direct_worker_id = auth.uid();
$function$;

REVOKE EXECUTE ON FUNCTION public.get_direct_request_context(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_direct_request_context(uuid) TO authenticated, service_role;


-- ── 10. Prazo: cron de 5 em 5 minutos ───────────────────────────

CREATE OR REPLACE FUNCTION public.expire_direct_job_requests()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  FOR v_job_id IN
    SELECT id FROM job_requests
    WHERE  direct_status = 'waiting'
      AND  direct_until <= now()
      AND  status = 'open'
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM open_direct_job_to_all(v_job_id, 'expired');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.expire_direct_job_requests() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'expire-direct-job-requests',
  '*/5 * * * *',
  'SELECT expire_direct_job_requests()'
);


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select jobname, schedule, active from cron.job
--  where jobname = 'expire-direct-job-requests';
-- select column_name from information_schema.columns
--  where table_name = 'job_requests' and column_name like 'direct_%';
-- select tgname from pg_trigger
--  where tgname in ('trg_job_request_direct_before_insert',
--                   'trg_job_proposal_direct_before_insert',
--                   'trg_job_proposal_direct_after_update');
