-- ══════════════════════════════════════════════════════════════
-- 0059 — Pedido direto pelo cartão do jardineiro e registo de visitas
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0058
-- (e da 0057, que criou o pedido direto). Pode correr-se mais do que uma
-- vez sem erro.
--
-- Design A7 (22/10). O cliente abre o cartão público /w/:id (link ou QR)
-- e pede orçamento só àquele jardineiro. Usa o mecanismo da 0057 (24 horas
-- só para ele, "Não posso desta vez", "Mostrar já a todos"), com três
-- coisas novas:
--
--   1. Nova origem do pedido direto: o cartão. O INSERT leva
--      `direct_card_worker_id` (o jardineiro do cartão que o cliente
--      abriu). Não é identidade: o cliente continua a ser auth.uid() pela
--      policy de INSERT, e o trigger valida que o id é de um jardineiro
--      ativo que aceita pedidos diretos, diferente do próprio cliente.
--      `direct_origin` regista de onde veio: public_card, repeat_hire ou
--      your_gardeners.
--
--   2. Interruptor "Se não puder, mostrar a outros jardineiros"
--      (`direct_auto_release`, por omissão ligado, como na 0057). Desligado:
--      se o jardineiro recusar ou o prazo acabar, o pedido NÃO abre a todos;
--      fica `on_hold` (só o cliente e, se o prazo acabou, o jardineiro o
--      veem) até o cliente escolher "Mostrar a todos" ou "Cancelar pedido".
--
--   3. Registo de quem entra pelo cartão (pedido do Henrique):
--      - worker_card_visits: cada abertura do cartão, com a origem (qr,
--        link ou app), um id aleatório do aparelho e, com sessão, o
--        utilizador. Escrita só pela RPC log_worker_card_visit (também sem
--        sessão), leitura só no SQL Editor.
--      - client_referrals: o cliente que criou conta depois de abrir o
--        cartão fica ligado ao jardineiro (claim_worker_card_visit).
--      - job_requests.card_visit_id: o pedido feito a partir dessa visita.
--      - Vista worker_card_funnel com os números por jardineiro.
--
-- Acesso por plano (Pro mais tarde): worker_can_receive_direct_requests e
-- worker_can_use_public_card devolvem hoje `true` para todos os
-- jardineiros ativos. Quando o Pro existir, muda-se só o corpo destas duas
-- funções; a app lê o resultado pela vista worker_public_card.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Acesso às funcionalidades do cartão ──────────────────────

CREATE OR REPLACE FUNCTION public.worker_can_use_public_card(p_worker_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   worker_profiles wp
    JOIN   profiles p ON p.id = wp.profile_id
    WHERE  wp.profile_id = p_worker_id
      AND  p.deleted_at IS NULL
  );
$function$;

CREATE OR REPLACE FUNCTION public.worker_can_receive_direct_requests(p_worker_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT worker_can_use_public_card(p_worker_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.worker_can_use_public_card(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.worker_can_receive_direct_requests(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.worker_can_use_public_card(uuid) TO anon, authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.worker_can_receive_direct_requests(uuid) TO anon, authenticated, service_role;


-- ── 2. Cartão público: ids dos serviços, acesso e última avaliação ──
-- Mesmas colunas e filtro da 0051, mais no fim: service_type_ids (o passo
-- 1 do pedido só mostra estes), as duas flags de acesso e o comentário
-- mais recente (só o primeiro nome de quem avaliou).

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
  lr.created_at AS latest_review_at
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


-- ── 3. Registo de visitas ao cartão ─────────────────────────────

CREATE TABLE IF NOT EXISTS public.worker_card_visits (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id   uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  source      text NOT NULL CHECK (source IN ('qr', 'link', 'app')),
  device_key  text CHECK (device_key IS NULL OR char_length(device_key) BETWEEN 8 AND 64),
  visitor_id  uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS worker_card_visits_worker_idx
  ON public.worker_card_visits (worker_id, created_at DESC);
CREATE INDEX IF NOT EXISTS worker_card_visits_device_idx
  ON public.worker_card_visits (worker_id, device_key, created_at DESC);

ALTER TABLE public.worker_card_visits ENABLE ROW LEVEL SECURITY;
-- Sem policies: escrita só pelas RPCs abaixo, leitura só no SQL Editor.
REVOKE ALL ON public.worker_card_visits FROM anon, authenticated;

-- Cliente que criou conta depois de abrir um cartão (um por cliente).
CREATE TABLE IF NOT EXISTS public.client_referrals (
  client_id   uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  worker_id   uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  visit_id    uuid REFERENCES worker_card_visits(id) ON DELETE SET NULL,
  source      text NOT NULL CHECK (source IN ('qr', 'link', 'app')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS client_referrals_worker_idx
  ON public.client_referrals (worker_id);

ALTER TABLE public.client_referrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.client_referrals FROM anon, authenticated;

-- 3.1 Abrir o cartão. Funciona sem sessão. O mesmo aparelho no mesmo
-- cartão em menos de 30 minutos conta uma vez (devolve a mesma visita).
-- O próprio jardineiro a ver o cartão não conta (devolve NULL).
-- p_worker_id é o cartão aberto, não quem chama.
CREATE OR REPLACE FUNCTION public.log_worker_card_visit(
  p_worker_id  uuid,
  p_source     text,
  p_device_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_source text := CASE WHEN p_source IN ('qr', 'link', 'app') THEN p_source ELSE 'link' END;
  v_key    text := NULLIF(btrim(p_device_key), '');
  v_id     uuid;
BEGIN
  IF v_key IS NOT NULL AND char_length(v_key) NOT BETWEEN 8 AND 64 THEN
    v_key := NULL;
  END IF;

  IF v_uid IS NOT NULL AND v_uid = p_worker_id THEN
    RETURN NULL;
  END IF;

  IF NOT worker_can_use_public_card(p_worker_id) THEN
    RETURN NULL;
  END IF;

  IF v_key IS NOT NULL THEN
    SELECT id INTO v_id
    FROM   worker_card_visits
    WHERE  worker_id  = p_worker_id
      AND  device_key = v_key
      AND  created_at > now() - interval '30 minutes'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_id IS NOT NULL THEN
      IF v_uid IS NOT NULL THEN
        UPDATE worker_card_visits SET visitor_id = v_uid
        WHERE  id = v_id AND visitor_id IS NULL;
      END IF;
      RETURN v_id;
    END IF;
  END IF;

  INSERT INTO worker_card_visits (worker_id, source, device_key, visitor_id)
  VALUES (p_worker_id, v_source, v_key, v_uid)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.log_worker_card_visit(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.log_worker_card_visit(uuid, text, text) TO anon, authenticated, service_role;

-- 3.2 Depois de entrar ou criar conta a partir do cartão: liga a visita ao
-- utilizador e, se a conta de cliente foi criada depois da visita (até 7
-- dias), regista o cliente como vindo daquele jardineiro.
CREATE OR REPLACE FUNCTION public.claim_worker_card_visit(p_visit_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_visit worker_card_visits%ROWTYPE;
  v_prof  profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida.';
  END IF;

  SELECT * INTO v_visit FROM worker_card_visits WHERE id = p_visit_id;
  IF NOT FOUND OR v_visit.worker_id = v_uid THEN
    RETURN;
  END IF;
  IF v_visit.visitor_id IS NOT NULL AND v_visit.visitor_id <> v_uid THEN
    RETURN;
  END IF;

  UPDATE worker_card_visits SET visitor_id = v_uid
  WHERE  id = p_visit_id AND visitor_id IS NULL;

  SELECT * INTO v_prof FROM profiles WHERE id = v_uid;
  IF FOUND
     AND v_prof.role = 'client'
     AND v_prof.created_at >= v_visit.created_at - interval '5 minutes'
     AND v_prof.created_at <= v_visit.created_at + interval '7 days'
  THEN
    INSERT INTO client_referrals (client_id, worker_id, visit_id, source)
    VALUES (v_uid, v_visit.worker_id, v_visit.id, v_visit.source)
    ON CONFLICT (client_id) DO NOTHING;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.claim_worker_card_visit(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_worker_card_visit(uuid) TO authenticated, service_role;


-- ── 4. Colunas novas do pedido direto ───────────────────────────

ALTER TABLE job_requests
  ADD COLUMN IF NOT EXISTS direct_card_worker_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS direct_auto_release   boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS direct_origin         text,
  ADD COLUMN IF NOT EXISTS direct_hold_reason    text,
  ADD COLUMN IF NOT EXISTS card_visit_id         uuid REFERENCES worker_card_visits(id) ON DELETE SET NULL;

ALTER TABLE job_requests DROP CONSTRAINT IF EXISTS job_requests_direct_status_check;
ALTER TABLE job_requests ADD CONSTRAINT job_requests_direct_status_check
  CHECK (direct_status IN ('waiting', 'declined', 'expired', 'released', 'on_hold'));

ALTER TABLE job_requests DROP CONSTRAINT IF EXISTS job_requests_direct_origin_check;
ALTER TABLE job_requests ADD CONSTRAINT job_requests_direct_origin_check
  CHECK (direct_origin IN ('public_card', 'repeat_hire', 'your_gardeners'));

ALTER TABLE job_requests DROP CONSTRAINT IF EXISTS job_requests_direct_hold_reason_check;
ALTER TABLE job_requests ADD CONSTRAINT job_requests_direct_hold_reason_check
  CHECK (direct_hold_reason IN ('declined', 'expired'));

-- Pedidos diretos da 0057 vieram todos do "Pedir de novo".
UPDATE job_requests SET direct_origin = 'repeat_hire'
WHERE  direct_source_job_id IS NOT NULL AND direct_origin IS NULL;

CREATE INDEX IF NOT EXISTS job_requests_card_visit_idx
  ON job_requests (card_visit_id) WHERE card_visit_id IS NOT NULL;


-- ── 5. Reserva: o interruptor desligado mantém o pedido fechado ─
-- Mesma ideia da 0057, mais o quinto argumento. Com o interruptor
-- desligado o prazo não abre o pedido sozinho, e `on_hold` continua
-- reservado até o cliente decidir.

DROP FUNCTION IF EXISTS public.job_reserved_for_other(text, timestamptz, uuid, uuid);

CREATE OR REPLACE FUNCTION public.job_reserved_for_other(
  p_direct_status       text,
  p_direct_until        timestamptz,
  p_direct_worker_id    uuid,
  p_worker_id           uuid,
  p_direct_auto_release boolean DEFAULT true
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT p_direct_worker_id IS DISTINCT FROM p_worker_id
     AND (
       (p_direct_status = 'waiting'
         AND (p_direct_until > now() OR NOT COALESCE(p_direct_auto_release, true)))
       OR p_direct_status = 'on_hold'
     );
$function$;


-- ── 6. Ao criar o pedido: resolve o jardineiro ──────────────────
-- Igual à 0057 para o "Pedir de novo"; novo ramo para o cartão.

CREATE OR REPLACE FUNCTION public.job_request_direct_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id uuid;
BEGIN
  NEW.direct_worker_id   := NULL;
  NEW.direct_until       := NULL;
  NEW.direct_status      := NULL;
  NEW.direct_hold_reason := NULL;

  IF NEW.direct_source_job_id IS NOT NULL THEN
    SELECT jp.worker_id INTO v_worker_id
    FROM   job_requests  src
    JOIN   job_proposals jp ON jp.id = src.accepted_proposal_id
    WHERE  src.id        = NEW.direct_source_job_id
      AND  src.client_id = NEW.client_id
      AND  src.status    = 'completed';

    IF v_worker_id IS NULL THEN
      RAISE EXCEPTION 'Só podes pedir de novo a um jardineiro com quem já concluíste um trabalho.';
    END IF;

    NEW.direct_card_worker_id := NULL;
    NEW.card_visit_id         := NULL;
    NEW.direct_origin := CASE WHEN NEW.direct_origin = 'your_gardeners'
                              THEN 'your_gardeners' ELSE 'repeat_hire' END;

  ELSIF NEW.direct_card_worker_id IS NOT NULL THEN
    v_worker_id := NEW.direct_card_worker_id;

    IF v_worker_id = NEW.client_id THEN
      RAISE EXCEPTION 'Não podes pedir um orçamento a ti próprio.';
    END IF;
    NEW.direct_origin := 'public_card';

  ELSE
    NEW.direct_origin       := NULL;
    NEW.card_visit_id       := NULL;
    NEW.direct_auto_release := true;
    RETURN NEW;
  END IF;

  IF NOT worker_can_receive_direct_requests(v_worker_id) THEN
    RAISE EXCEPTION 'Este jardineiro já não aceita pedidos.';
  END IF;

  -- A visita só fica ligada se for ao cartão deste jardineiro.
  IF NEW.card_visit_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM worker_card_visits
      WHERE  id = NEW.card_visit_id AND worker_id = v_worker_id
    ) THEN
      NEW.card_visit_id := NULL;
    ELSE
      UPDATE worker_card_visits SET visitor_id = NEW.client_id
      WHERE  id = NEW.card_visit_id AND visitor_id IS NULL;
    END IF;
  END IF;

  NEW.direct_auto_release := COALESCE(NEW.direct_auto_release, true);
  NEW.direct_worker_id    := v_worker_id;
  NEW.direct_until        := now() + interval '24 hours';
  NEW.direct_status       := 'waiting';
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_request_direct_before_insert() FROM PUBLIC, anon, authenticated;
-- O trigger trg_job_request_direct_before_insert (0057) já aponta para esta função.

-- Os campos diretos não se mudam depois de criado o pedido (só pelas
-- funções abaixo, que correm como dono).
CREATE OR REPLACE FUNCTION public.job_request_direct_lock_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('request.jwt.claim.sub', true) IS NOT NULL
     AND current_user IN ('authenticated', 'anon')
     AND (NEW.direct_card_worker_id IS DISTINCT FROM OLD.direct_card_worker_id
       OR NEW.direct_auto_release   IS DISTINCT FROM OLD.direct_auto_release
       OR NEW.direct_origin         IS DISTINCT FROM OLD.direct_origin
       OR NEW.direct_hold_reason    IS DISTINCT FROM OLD.direct_hold_reason
       OR NEW.card_visit_id         IS DISTINCT FROM OLD.card_visit_id
       OR NEW.direct_worker_id      IS DISTINCT FROM OLD.direct_worker_id
       OR NEW.direct_until          IS DISTINCT FROM OLD.direct_until
       OR NEW.direct_status         IS DISTINCT FROM OLD.direct_status)
  THEN
    RAISE EXCEPTION 'Os dados do pedido direto não se podem alterar.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_request_direct_lock_update ON job_requests;
CREATE TRIGGER trg_job_request_direct_lock_update
  BEFORE UPDATE ON job_requests
  FOR EACH ROW EXECUTE FUNCTION job_request_direct_lock_update();


-- ── 7. Aviso ao jardineiro ──────────────────────────────────────
-- Igual à 0057; pelo cartão o texto diz quem pediu e o serviço.

CREATE OR REPLACE FUNCTION public.notify_workers_new_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client  text;
  v_service text;
BEGIN
  IF NEW.direct_status = 'waiting' AND NEW.direct_worker_id IS NOT NULL THEN
    IF NEW.direct_origin = 'public_card' THEN
      SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_client
      FROM   profiles WHERE id = NEW.client_id;
      SELECT name INTO v_service FROM service_types WHERE id = NEW.service_type_id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        NEW.direct_worker_id,
        'direct_job_request',
        'Novo pedido pelo teu cartão',
        COALESCE(v_client, 'Um cliente') || ' quer um orçamento'
          || COALESCE(' para ' || v_service, '') || '. Tens 24 horas.',
        NEW.id,
        'job_request'
      );
    ELSE
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        NEW.direct_worker_id,
        'direct_job_request',
        'Pedido só para ti',
        'Um cliente com quem já trabalhaste pediu-te um trabalho. Tens 24 horas para responder antes de o pedido abrir a outros jardineiros.',
        NEW.id,
        'job_request'
      );
    END IF;
    RETURN NEW;
  END IF;

  PERFORM notify_workers_job_open(NEW);
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_new_job() FROM PUBLIC, anon, authenticated;


-- ── 8. Fim da reserva: abrir a todos ou parar ───────────────────

-- 8.1 Igual à 0057, mas também abre um pedido parado (on_hold) quando o
-- cliente escolhe "Mostrar a todos".
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
         direct_hold_reason = NULL,
         excluded_worker_ids = CASE
           WHEN p_status = 'declined' AND NOT (direct_worker_id = ANY(excluded_worker_ids))
             THEN array_append(excluded_worker_ids, direct_worker_id)
           ELSE excluded_worker_ids
         END,
         expires_at = GREATEST(expires_at, now() + interval '48 hours'),
         updated_at = now()
  WHERE  id = p_job_id
    AND  status = 'open'
    AND  (direct_status = 'waiting'
          OR (direct_status = 'on_hold' AND p_status = 'released'))
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

-- 8.2 Interruptor desligado: o pedido fica parado à espera do cliente.
CREATE OR REPLACE FUNCTION public.hold_direct_job(
  p_job_id uuid,
  p_reason text
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
  IF p_reason NOT IN ('declined', 'expired') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  UPDATE job_requests
  SET    direct_status = 'on_hold',
         direct_hold_reason = p_reason,
         excluded_worker_ids = CASE
           WHEN p_reason = 'declined' AND NOT (direct_worker_id = ANY(excluded_worker_ids))
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

  SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_worker_name
  FROM   profiles WHERE id = v_job.direct_worker_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'direct_request_released',
    CASE WHEN p_reason = 'declined'
         THEN COALESCE(v_worker_name, 'O jardineiro') || ' não pode desta vez'
         ELSE COALESCE(v_worker_name, 'O jardineiro') || ' não respondeu a tempo'
    END,
    'O pedido está parado. Queres mostrá-lo a outros jardineiros?',
    v_job.id,
    'job_request'
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.hold_direct_job(uuid, text) FROM PUBLIC, anon, authenticated;

-- 8.3 Escolhe entre abrir e parar, conforme o interruptor do cliente.
CREATE OR REPLACE FUNCTION public.end_direct_reservation(
  p_job_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auto boolean;
BEGIN
  SELECT direct_auto_release INTO v_auto FROM job_requests WHERE id = p_job_id;
  IF COALESCE(v_auto, true) THEN
    PERFORM open_direct_job_to_all(p_job_id, p_reason);
  ELSE
    PERFORM hold_direct_job(p_job_id, p_reason);
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.end_direct_reservation(uuid, text) FROM PUBLIC, anon, authenticated;


-- ── 9. RPCs do cliente e do jardineiro ──────────────────────────

-- 9.1 "Mostrar já a todos" e, com o pedido parado, "Mostrar a todos".
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
  IF v_job.direct_status IS DISTINCT FROM 'waiting'
     AND v_job.direct_status IS DISTINCT FROM 'on_hold' THEN
    RETURN;
  END IF;

  PERFORM open_direct_job_to_all(p_job_id, 'released');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.release_direct_job_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.release_direct_job_request(uuid) TO authenticated, service_role;

-- 9.2 "Não posso desta vez": como na 0057, mas respeita o interruptor.
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
    RAISE EXCEPTION 'Este pedido já não está reservado para ti.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já enviaste uma proposta para este pedido. Retira-a primeiro.';
  END IF;

  PERFORM end_direct_reservation(p_job_id, 'declined');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.decline_direct_job_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.decline_direct_job_request(uuid) TO authenticated, service_role;

-- 9.3 Proposta do escolhido recusada pelo cliente (abre sempre: foi o
-- cliente) ou retirada por ele (conta como recusa, respeita o interruptor).
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
         AND  jr.direct_status IN ('waiting', 'on_hold')
         AND  jr.direct_worker_id = NEW.worker_id
     )
  THEN
    IF NEW.status = 'superseded' THEN
      PERFORM end_direct_reservation(NEW.job_id, 'declined');
    ELSE
      PERFORM open_direct_job_to_all(NEW.job_id, 'released');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_proposal_direct_after_update() FROM PUBLIC, anon, authenticated;

-- 9.4 Propostas durante a reserva (igual à 0057, com o interruptor).
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
      AND  job_reserved_for_other(jr.direct_status, jr.direct_until,
                                  jr.direct_worker_id, NEW.worker_id,
                                  jr.direct_auto_release)
  ) THEN
    RAISE EXCEPTION 'Este pedido ainda está reservado a outro jardineiro.';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_proposal_direct_before_insert() FROM PUBLIC, anon, authenticated;


-- ── 10. Visibilidade (iguais à 0057, com o interruptor) ─────────

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
          AND NOT job_reserved_for_other(jr.direct_status, jr.direct_until,
                                         jr.direct_worker_id, auth.uid(),
                                         jr.direct_auto_release))
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

-- O pedido direto para mim aparece mesmo fora do meu raio, e primeiro:
-- durante as 24 horas e, com o interruptor desligado, depois do prazo
-- enquanto o cliente não decide.
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
    AND  (d.distance_km <= b.r OR COALESCE(dr.for_me, false))
  ORDER BY COALESCE(dr.for_me, false) DESC, d.distance_km ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;

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
    AND  NOT job_reserved_for_other(jr.direct_status, jr.direct_until,
                                    jr.direct_worker_id, auth.uid(),
                                    jr.direct_auto_release);
$function$;

-- Igual à 0057, mais: a visita e o jardineiro do cartão só os vê o próprio
-- jardineiro escolhido.
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
                                   THEN p_job.direct_source_job_id END,
      'direct_card_worker_id', CASE WHEN p_job.direct_worker_id = auth.uid()
                                    THEN p_job.direct_card_worker_id END,
      'direct_origin', CASE WHEN p_job.direct_worker_id = auth.uid()
                            THEN p_job.direct_origin END,
      'card_visit_id', NULL
    )
  );
$function$;


-- ── 11. Prazo: o cron respeita o interruptor ────────────────────

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
    PERFORM end_direct_reservation(v_job_id, 'expired');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.expire_direct_job_requests() FROM PUBLIC, anon, authenticated;
-- O cron expire-direct-job-requests (0057) já chama esta função.


-- ── 12. Números por jardineiro (só no SQL Editor) ───────────────

CREATE OR REPLACE VIEW public.worker_card_funnel AS
SELECT
  wp.profile_id AS worker_id,
  p.full_name   AS worker_name,
  COALESCE(v.visits, 0)            AS visits,
  COALESCE(v.visits_qr, 0)         AS visits_qr,
  COALESCE(v.visits_link, 0)       AS visits_link,
  COALESCE(v.visits_app, 0)        AS visits_app,
  COALESCE(v.devices, 0)           AS unique_devices,
  COALESCE(v.signed_in, 0)         AS signed_in_visitors,
  COALESCE(cr.new_clients, 0)      AS new_clients,
  COALESCE(cr.new_clients_qr, 0)   AS new_clients_qr,
  COALESCE(j.card_requests, 0)     AS card_requests,
  COALESCE(j.card_requests_hired, 0) AS card_requests_hired,
  v.last_visit_at
FROM worker_profiles wp
JOIN profiles p ON p.id = wp.profile_id
LEFT JOIN (
  SELECT worker_id,
         COUNT(*)                                    AS visits,
         COUNT(*) FILTER (WHERE source = 'qr')       AS visits_qr,
         COUNT(*) FILTER (WHERE source = 'link')     AS visits_link,
         COUNT(*) FILTER (WHERE source = 'app')      AS visits_app,
         COUNT(DISTINCT device_key)                  AS devices,
         COUNT(DISTINCT visitor_id)                  AS signed_in,
         MAX(created_at)                             AS last_visit_at
  FROM   worker_card_visits
  GROUP BY worker_id
) v ON v.worker_id = wp.profile_id
LEFT JOIN (
  SELECT worker_id,
         COUNT(*)                              AS new_clients,
         COUNT(*) FILTER (WHERE source = 'qr') AS new_clients_qr
  FROM   client_referrals
  GROUP BY worker_id
) cr ON cr.worker_id = wp.profile_id
LEFT JOIN (
  SELECT jr.direct_worker_id AS worker_id,
         COUNT(*) AS card_requests,
         COUNT(*) FILTER (
           WHERE jp.worker_id = jr.direct_worker_id
         ) AS card_requests_hired
  FROM   job_requests jr
  LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.direct_origin = 'public_card'
  GROUP BY jr.direct_worker_id
) j ON j.worker_id = wp.profile_id;

REVOKE ALL ON public.worker_card_funnel FROM PUBLIC, anon, authenticated;


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Consultas úteis (só leitura, no SQL Editor)
-- ══════════════════════════════════════════════════════════════
-- Números por jardineiro, os que têm mais visitas primeiro:
--   select * from worker_card_funnel where visits > 0 order by visits desc;
--
-- Clientes que entraram por cada cartão:
--   select cr.created_at, cr.source, w.full_name as jardineiro, c.full_name as cliente
--     from client_referrals cr
--     join profiles w on w.id = cr.worker_id
--     join profiles c on c.id = cr.client_id
--    order by cr.created_at desc;
--
-- Visitas dos últimos 30 dias por dia e origem:
--   select date_trunc('day', created_at) as dia, source, count(*)
--     from worker_card_visits
--    where created_at > now() - interval '30 days'
--    group by 1, 2 order by 1 desc;
--
-- Verificação depois de aplicar:
--   select column_name from information_schema.columns
--    where table_name = 'job_requests'
--      and column_name in ('direct_card_worker_id','direct_auto_release',
--                          'direct_origin','direct_hold_reason','card_visit_id');
--   select count(*) from worker_card_visits;
