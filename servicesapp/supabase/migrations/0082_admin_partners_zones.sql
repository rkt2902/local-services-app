-- ══════════════════════════════════════════════════════════════
-- 0082 — Painel de admin: cartões frota, gasolineiras parceiras e
--        zonas no mapa
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (17/11/2026, Henrique).
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. Cartões frota no painel: admin_list_fleet_cards e
--      admin_review_fleet_card (aprovar, recusar, retirar). Deixa de ser
--      preciso o UPDATE à mão no SQL Editor (0037). O jardineiro recebe
--      um aviso (tipo 'fleet_card_reviewed') e vê a mensagem da recusa.
--   2. Parceiros (tabela partners): o painel cria e altera
--      (admin_list_partners, admin_save_partner, admin_delete_partner),
--      com foto (bucket partner-images), descrição, código de desconto,
--      código de barras, QR, link, condições e localização opcionais. A
--      app lê get_partners (só ativos e visíveis; os códigos dos que são
--      só Pro+ ficam escondidos a quem não é Pro+). Um parceiro de
--      exemplo para ver o ecrã (apagar antes do lançamento).
--      A app regista o uso (log_partner_event: abrir, copiar o código,
--      abrir o link ou o mapa) e o painel mostra os números de cada um.
--      get_partners devolve a distância à base do jardineiro.
--      admin_partner_alerts diz quantos acabam nos próximos 7 dias.
--   3. admin_map_zones: o país em quadrados (10 km por omissão) com
--      pedidos, pedidos sem resposta, jardineiros que cobrem a zona e
--      parceiros com localização, para as camadas "Sem resposta" e "Densidade".
--   4. Avisos de parceiro novo: admin_send_notice aceita p_partner_id e
--      o aviso (tipo 'partner_new') abre o parceiro na app.
--
-- Regras de sempre: cada admin_* chama assert_verified_admin(); quem
-- chama é auth.uid(); nenhuma RPC recebe worker_id/client_id/user_id.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Cartões frota ────────────────────────────────────────────

ALTER TABLE public.worker_fleet_cards
  ADD COLUMN IF NOT EXISTS reviewed_at    timestamptz,
  ADD COLUMN IF NOT EXISTS review_message text;

-- O jardineiro continua a só poder criar o pedido, e agora também não
-- pode escrever a decisão.
DROP POLICY IF EXISTS "Worker pede um cartão frota" ON public.worker_fleet_cards;
CREATE POLICY "Worker pede um cartão frota"
  ON public.worker_fleet_cards FOR INSERT TO authenticated
  WITH CHECK (worker_id = auth.uid() AND status = 'pending'
              AND reviewed_at IS NULL AND review_message IS NULL);

-- Conta suspensa também não pede cartões (0080).
DROP TRIGGER IF EXISTS trg_block_suspended_writes ON public.worker_fleet_cards;
CREATE TRIGGER trg_block_suspended_writes
  BEFORE INSERT OR UPDATE ON public.worker_fleet_cards
  FOR EACH ROW EXECUTE FUNCTION public.block_suspended_writes();

CREATE INDEX IF NOT EXISTS worker_fleet_cards_status_idx
  ON public.worker_fleet_cards (status, created_at DESC);

-- p_status: 'pending', 'active', 'rejected' ou NULL (todos). Só a linha
-- mais recente de cada jardineiro conta como o cartão dele; as outras
-- vêm com is_latest = false.
DROP FUNCTION IF EXISTS public.admin_list_fleet_cards(text, integer, integer);
CREATE FUNCTION public.admin_list_fleet_cards(
  p_status text DEFAULT 'pending',
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id               uuid,
  worker_id        uuid,
  worker_name      text,
  location_name    text,
  plan             text,
  worker_suspended boolean,
  card_number      text,
  holder_name      text,
  barcode_value    text,
  status           text,
  created_at       timestamptz,
  reviewed_at      timestamptz,
  review_message   text,
  attempts         integer,
  is_latest        boolean,
  total_count      bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  IF p_status IS NOT NULL AND p_status NOT IN ('pending', 'active', 'rejected') THEN
    RAISE EXCEPTION 'Estado de cartão desconhecido.';
  END IF;
  PERFORM public.admin_log('view_fleet_cards', NULL,
    jsonb_build_object('status', p_status));

  RETURN QUERY
  WITH c AS (
    SELECT fc.*,
           count(*) OVER (PARTITION BY fc.worker_id)::integer AS n_attempts,
           row_number() OVER (PARTITION BY fc.worker_id
                              ORDER BY fc.created_at DESC, fc.id DESC) = 1 AS latest
    FROM worker_fleet_cards fc
  )
  SELECT c.id, c.worker_id, COALESCE(p.full_name, 'Jardineiro'), wp.location_name,
         COALESCE(pl.tier, 'free'), (s.suspended_at IS NOT NULL),
         c.card_number, c.holder_name, c.barcode_value, c.status, c.created_at,
         c.reviewed_at, c.review_message, c.n_attempts, c.latest,
         count(*) OVER ()
  FROM c
  JOIN profiles p ON p.id = c.worker_id AND p.deleted_at IS NULL
  LEFT JOIN worker_profiles wp ON wp.profile_id = c.worker_id
  LEFT JOIN worker_plans pl ON pl.worker_id = c.worker_id
  LEFT JOIN account_status s ON s.profile_id = c.worker_id
  WHERE (p_status IS NULL OR c.status = p_status)
  ORDER BY c.latest DESC,
           CASE WHEN c.status = 'pending' THEN c.created_at END ASC,
           c.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_fleet_cards(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_fleet_cards(text, integer, integer) TO authenticated, service_role;

-- Aprovar (pending → active), recusar (pending → rejected) ou retirar
-- (active → rejected). Só o cartão mais recente do jardineiro. Recusar
-- e retirar pedem um motivo da lista; a mensagem ao jardineiro é a do
-- motivo, ou a escrita pelo admin (obrigatória em 'other').
DROP FUNCTION IF EXISTS public.admin_review_fleet_card(uuid, text, text, text);
CREATE FUNCTION public.admin_review_fleet_card(
  p_card_id  uuid,
  p_decision text,
  p_reason   text DEFAULT NULL,
  p_message  text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_card    worker_fleet_cards%ROWTYPE;
  v_latest  uuid;
  v_message text := NULLIF(btrim(COALESCE(p_message, '')), '');
  v_action  text;
BEGIN
  PERFORM public.assert_verified_admin();

  SELECT * INTO v_card FROM worker_fleet_cards WHERE id = p_card_id FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM profiles
                              WHERE id = v_card.worker_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Cartão não encontrado.';
  END IF;

  SELECT fc.id INTO v_latest FROM worker_fleet_cards fc
  WHERE fc.worker_id = v_card.worker_id
  ORDER BY fc.created_at DESC, fc.id DESC LIMIT 1;
  IF v_latest <> v_card.id THEN
    RAISE EXCEPTION 'O jardineiro já pediu outro cartão depois deste. Decide o mais recente.';
  END IF;

  IF p_decision = 'active' THEN
    IF v_card.status <> 'pending' THEN
      RAISE EXCEPTION 'Este cartão já não está à espera de aprovação.';
    END IF;
    v_action := 'fleet_card_approved';
    v_message := NULL;
  ELSIF p_decision = 'rejected' THEN
    IF v_card.status = 'rejected' THEN
      RAISE EXCEPTION 'Este cartão já está recusado.';
    END IF;
    IF p_reason IS NULL OR p_reason NOT IN ('unreadable', 'not_eligible', 'partner_refused', 'other') THEN
      RAISE EXCEPTION 'Escolhe um motivo da lista.';
    END IF;
    IF p_reason = 'other' AND length(COALESCE(v_message, '')) < 10 THEN
      RAISE EXCEPTION 'Escreve ao jardineiro o motivo (10 carateres ou mais).';
    END IF;
    IF length(COALESCE(v_message, '')) > 300 THEN
      RAISE EXCEPTION 'A mensagem tem de ter até 300 carateres.';
    END IF;
    v_message := COALESCE(v_message, CASE p_reason
      WHEN 'unreadable' THEN 'Não conseguimos ler os dados do cartão. Fotografa-o outra vez, com boa luz.'
      WHEN 'not_eligible' THEN 'O cartão frota é um benefício do plano Pro+.'
      WHEN 'partner_refused' THEN 'A gasolineira parceira não aceitou este cartão.'
    END);
    v_action := CASE WHEN v_card.status = 'active' THEN 'fleet_card_revoked' ELSE 'fleet_card_rejected' END;
  ELSE
    RAISE EXCEPTION 'Decisão desconhecida.';
  END IF;

  UPDATE worker_fleet_cards
  SET status = p_decision, reviewed_at = now(), review_message = v_message
  WHERE id = v_card.id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_card.worker_id, 'fleet_card_reviewed',
          CASE v_action
            WHEN 'fleet_card_approved' THEN 'Cartão frota ativo'
            WHEN 'fleet_card_revoked' THEN 'Cartão frota desativado'
            ELSE 'Cartão frota recusado' END,
          CASE v_action
            WHEN 'fleet_card_approved' THEN 'O teu cartão frota foi aprovado. Já o podes mostrar na gasolineira.'
            ELSE v_message END,
          v_card.id, 'fleet_card');

  PERFORM public.admin_log(v_action, v_card.worker_id,
    jsonb_build_object('card_id', v_card.id, 'reason', p_reason, 'message', v_message));
  RETURN p_decision;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_review_fleet_card(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_fleet_card(uuid, text, text, text) TO authenticated, service_role;


-- ── 2. Parceiros ────────────────────────────────────────────────

-- Um parceiro (gasolineira, loja, ...) com o que o jardineiro vê na app
-- e o que só o painel vê (estado, notas). A localização é opcional.
-- Uma versão anterior desta migration criava "partner_locations": se
-- já existir, passa a "partners".
DO $$
BEGIN
  IF to_regclass('public.partner_locations') IS NOT NULL
     AND to_regclass('public.partners') IS NULL THEN
    ALTER TABLE public.partner_locations RENAME TO partners;
  END IF;
END $$;
DROP FUNCTION IF EXISTS public.admin_list_partner_locations();
DROP FUNCTION IF EXISTS public.admin_save_partner_location(uuid, text, text, text, text, text, text, numeric, numeric, text);
DROP FUNCTION IF EXISTS public.admin_delete_partner_location(uuid);

CREATE TABLE IF NOT EXISTS public.partners (
  id         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  kind       text        NOT NULL DEFAULT 'fuel_station',
  name       text        NOT NULL,
  brand      text,
  -- prospect = em conversa; active = parceiro; ended = deixou de ser.
  status     text        NOT NULL DEFAULT 'prospect'
                         CHECK (status IN ('prospect', 'active', 'ended')),
  address    text,
  locality   text,
  lat        numeric(9,6),
  lng        numeric(9,6),
  notes      text,
  created_by uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.partners ALTER COLUMN lat DROP NOT NULL;
ALTER TABLE public.partners ALTER COLUMN lng DROP NOT NULL;
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS headline       text,
  ADD COLUMN IF NOT EXISTS description    text,
  ADD COLUMN IF NOT EXISTS image_path     text,
  ADD COLUMN IF NOT EXISTS discount_code  text,
  ADD COLUMN IF NOT EXISTS barcode_value  text,
  ADD COLUMN IF NOT EXISTS barcode_format text    NOT NULL DEFAULT 'code128',
  ADD COLUMN IF NOT EXISTS qr_value       text,
  ADD COLUMN IF NOT EXISTS link_url       text,
  ADD COLUMN IF NOT EXISTS link_label     text,
  ADD COLUMN IF NOT EXISTS terms          text,
  ADD COLUMN IF NOT EXISTS valid_until    date,
  ADD COLUMN IF NOT EXISTS visible_in_app boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pro_plus_only  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sort_order     integer NOT NULL DEFAULT 100;

-- Os CHECK do tipo vêm de nomes antigos; refazem-se com nomes fixos.
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.partners'::regclass AND contype = 'c'
             AND pg_get_constraintdef(oid) LIKE '%kind%'
  LOOP
    EXECUTE format('ALTER TABLE public.partners DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.partners ADD CONSTRAINT partners_kind_check
  CHECK (kind IN ('fuel_station', 'garden_store', 'equipment', 'services', 'other'));
ALTER TABLE public.partners DROP CONSTRAINT IF EXISTS partners_barcode_format_check;
ALTER TABLE public.partners ADD CONSTRAINT partners_barcode_format_check
  CHECK (barcode_format IN ('code128', 'ean13'));
ALTER TABLE public.partners DROP CONSTRAINT IF EXISTS partners_location_pair;
ALTER TABLE public.partners ADD CONSTRAINT partners_location_pair
  CHECK ((lat IS NULL) = (lng IS NULL));

ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.partners FROM anon, authenticated;

-- Uso de cada parceiro na app, para o painel mostrar quantos jardineiros
-- o abriram, copiaram o código ou tocaram no link (argumento para fechar
-- e renovar parcerias). Só escreve log_partner_event.
CREATE TABLE IF NOT EXISTS public.partner_events (
  id         bigserial   PRIMARY KEY,
  partner_id uuid        NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  worker_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind       text        NOT NULL
                         CHECK (kind IN ('open', 'copy_code', 'open_link', 'open_map')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS partner_events_partner_idx
  ON public.partner_events (partner_id, kind, created_at DESC);
CREATE INDEX IF NOT EXISTS partner_events_worker_idx
  ON public.partner_events (worker_id, partner_id, kind, created_at DESC);
ALTER TABLE public.partner_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.partner_events FROM anon, authenticated;
CREATE INDEX IF NOT EXISTS partners_app_idx ON public.partners (sort_order, name)
  WHERE status = 'active' AND visible_in_app;

-- Fotos dos parceiros: leitura pública (vão nos banners), escrita só do
-- admin com segundo fator. is_verified_admin() só diz se quem chama é
-- admin; as policies do Storage correm como 'authenticated'.
-- Até 5 MB, só JPEG, PNG ou WebP (como os outros buckets desde a 0042).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('partner-images', 'partner-images', true, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = true,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;
GRANT EXECUTE ON FUNCTION public.is_verified_admin() TO authenticated;

DROP POLICY IF EXISTS "partner-images: leitura pública" ON storage.objects;
CREATE POLICY "partner-images: leitura pública"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'partner-images');
DROP POLICY IF EXISTS "partner-images: admin envia" ON storage.objects;
CREATE POLICY "partner-images: admin envia"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'partner-images' AND public.is_verified_admin());
DROP POLICY IF EXISTS "partner-images: admin altera" ON storage.objects;
CREATE POLICY "partner-images: admin altera"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'partner-images' AND public.is_verified_admin())
  WITH CHECK (bucket_id = 'partner-images' AND public.is_verified_admin());
DROP POLICY IF EXISTS "partner-images: admin apaga" ON storage.objects;
CREATE POLICY "partner-images: admin apaga"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'partner-images' AND public.is_verified_admin());

-- Jardineiros que contam para o mapa: com base marcada, ativos, reais.
CREATE OR REPLACE FUNCTION public.admin_active_worker_bases()
RETURNS TABLE(worker_id uuid, lat numeric, lng numeric, radius_km integer, location_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT wp.profile_id, wp.base_lat, wp.base_lng,
         LEAST(GREATEST(COALESCE(wp.radius_km, 10), 1), 50), wp.location_name
  FROM worker_profiles wp
  WHERE wp.base_lat IS NOT NULL AND wp.base_lng IS NOT NULL
    AND NOT (wp.base_lat = 0 AND wp.base_lng = 0)
    AND public.admin_counts_person(wp.profile_id);
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_active_worker_bases() FROM PUBLIC, anon, authenticated;

-- EAN-13: 13 dígitos com o dígito de controlo certo.
CREATE OR REPLACE FUNCTION public.is_valid_ean13(p_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT p_code ~ '^\d{13}$' AND (
    10 - (SELECT sum(substr(p_code, i, 1)::int * CASE WHEN i % 2 = 0 THEN 3 ELSE 1 END)
          FROM generate_series(1, 12) i) % 10) % 10 = substr(p_code, 13, 1)::int;
$function$;

-- A app regista o uso. Só jardineiros, só parceiros que a app mostra, e
-- o mesmo gesto do mesmo jardineiro conta uma vez por hora (abrir e
-- fechar várias vezes não infla os números). Falhar aqui não pode
-- estragar o ecrã: a app ignora erros.
DROP FUNCTION IF EXISTS public.log_partner_event(uuid, text);
CREATE FUNCTION public.log_partner_event(p_partner_id uuid, p_kind text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sem sessão.' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('open', 'copy_code', 'open_link', 'open_map') THEN
    RAISE EXCEPTION 'Gesto desconhecido.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND role = 'worker') THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM partners pa WHERE pa.id = p_partner_id
                   AND pa.status = 'active' AND pa.visible_in_app
                   AND (pa.valid_until IS NULL OR pa.valid_until >= CURRENT_DATE)) THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM partner_events e
             WHERE e.worker_id = v_uid AND e.partner_id = p_partner_id
               AND e.kind = p_kind AND e.created_at > now() - interval '1 hour') THEN
    RETURN;
  END IF;
  INSERT INTO partner_events (partner_id, worker_id, kind)
  VALUES (p_partner_id, v_uid, p_kind);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.log_partner_event(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_partner_event(uuid, text) TO authenticated, service_role;

-- Alerta da Visão geral: parceiros na app que acabam nos próximos 7 dias
-- e os que estão marcados "na app" mas já passaram a validade (e por
-- isso já não aparecem).
DROP FUNCTION IF EXISTS public.admin_partner_alerts();
CREATE FUNCTION public.admin_partner_alerts()
RETURNS TABLE(ending_soon integer, expired_visible integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT count(*) FILTER (WHERE pa.valid_until BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)::integer,
         count(*) FILTER (WHERE pa.valid_until < CURRENT_DATE)::integer
  FROM partners pa
  WHERE pa.status = 'active' AND pa.visible_in_app;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_partner_alerts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_partner_alerts() TO authenticated, service_role;

-- Lista do painel: tudo, mais o que há perto de quem tem localização
-- (10 km; pedidos dos últimos 90 dias). Sem localização, os números
-- vêm a NULL.
DROP FUNCTION IF EXISTS public.admin_list_partners();
CREATE FUNCTION public.admin_list_partners()
RETURNS TABLE(
  id               uuid,
  kind             text,
  name             text,
  brand            text,
  status           text,
  headline         text,
  description      text,
  image_path       text,
  discount_code    text,
  barcode_value    text,
  barcode_format   text,
  qr_value         text,
  link_url         text,
  link_label       text,
  terms            text,
  valid_until      date,
  visible_in_app   boolean,
  pro_plus_only    boolean,
  sort_order       integer,
  address          text,
  locality         text,
  lat              double precision,
  lng              double precision,
  notes            text,
  created_at       timestamptz,
  updated_at       timestamptz,
  workers_covering integer,
  workers_nearby   integer,
  jobs_nearby      integer,
  jobs_unanswered  integer,
  -- Uso na app nos últimos 30 dias (jardineiros diferentes) e desde sempre.
  workers_opened_30d    integer,
  workers_opened_total  integer,
  workers_copied_30d    integer,
  workers_link_30d      integer,
  workers_map_30d       integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  WITH w AS (SELECT * FROM public.admin_active_worker_bases()),
  j AS (
    SELECT jr.location_lat AS lat, jr.location_lng AS lng,
           (jr.status = 'no_response'
            OR (jr.status = 'open' AND jr.created_at < now() - interval '24 hours'
                AND NOT EXISTS (SELECT 1 FROM job_proposals jp WHERE jp.job_id = jr.id))) AS unanswered
    FROM job_requests jr
    WHERE jr.created_at >= now() - interval '90 days'
      AND jr.location_lat IS NOT NULL AND jr.location_lng IS NOT NULL
      AND public.admin_counts_person(jr.client_id)
  )
  SELECT pa.id, pa.kind, pa.name, pa.brand, pa.status, pa.headline, pa.description,
         pa.image_path, pa.discount_code, pa.barcode_value, pa.barcode_format,
         pa.qr_value, pa.link_url, pa.link_label, pa.terms, pa.valid_until,
         pa.visible_in_app, pa.pro_plus_only, pa.sort_order,
         pa.address, pa.locality, pa.lat::double precision, pa.lng::double precision,
         pa.notes, pa.created_at, pa.updated_at,
         CASE WHEN pa.lat IS NOT NULL THEN (SELECT count(*)::integer FROM w
           WHERE public.km_between(w.lat, w.lng, pa.lat, pa.lng) <= w.radius_km) END,
         CASE WHEN pa.lat IS NOT NULL THEN (SELECT count(*)::integer FROM w
           WHERE public.km_between(w.lat, w.lng, pa.lat, pa.lng) <= 10) END,
         CASE WHEN pa.lat IS NOT NULL THEN (SELECT count(*)::integer FROM j
           WHERE public.km_between(j.lat, j.lng, pa.lat, pa.lng) <= 10) END,
         CASE WHEN pa.lat IS NOT NULL THEN (SELECT count(*)::integer FROM j
           WHERE j.unanswered AND public.km_between(j.lat, j.lng, pa.lat, pa.lng) <= 10) END,
         COALESCE(u.opened_30d, 0), COALESCE(u.opened_total, 0), COALESCE(u.copied_30d, 0),
         COALESCE(u.link_30d, 0), COALESCE(u.map_30d, 0)
  FROM partners pa
  LEFT JOIN LATERAL (
    SELECT count(DISTINCT e.worker_id) FILTER (WHERE e.kind = 'open' AND e.created_at > now() - interval '30 days')::integer AS opened_30d,
           count(DISTINCT e.worker_id) FILTER (WHERE e.kind = 'open')::integer AS opened_total,
           count(DISTINCT e.worker_id) FILTER (WHERE e.kind = 'copy_code' AND e.created_at > now() - interval '30 days')::integer AS copied_30d,
           count(DISTINCT e.worker_id) FILTER (WHERE e.kind = 'open_link' AND e.created_at > now() - interval '30 days')::integer AS link_30d,
           count(DISTINCT e.worker_id) FILTER (WHERE e.kind = 'open_map' AND e.created_at > now() - interval '30 days')::integer AS map_30d
    FROM partner_events e
    WHERE e.partner_id = pa.id AND public.admin_counts_person(e.worker_id)
  ) u ON true
  ORDER BY CASE pa.status WHEN 'active' THEN 0 WHEN 'prospect' THEN 1 ELSE 2 END,
           pa.sort_order, pa.name;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_partners() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_partners() TO authenticated, service_role;

-- Cria (p_id NULL) ou altera. p_data leva os campos pelo nome da coluna;
-- texto vazio fica NULL (e a app não mostra essa parte).
DROP FUNCTION IF EXISTS public.admin_save_partner(uuid, jsonb);
CREATE FUNCTION public.admin_save_partner(p_id uuid, p_data jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  d       jsonb := COALESCE(p_data, '{}'::jsonb);
  v_name  text := btrim(COALESCE(d->>'name', ''));
  v_kind  text := COALESCE(NULLIF(btrim(d->>'kind'), ''), 'fuel_station');
  v_status text := COALESCE(NULLIF(btrim(d->>'status'), ''), 'prospect');
  v_lat   numeric := NULLIF(d->>'lat', '')::numeric;
  v_lng   numeric := NULLIF(d->>'lng', '')::numeric;
  v_fmt   text := COALESCE(NULLIF(btrim(d->>'barcode_format'), ''), 'code128');
  v_bar   text := NULLIF(btrim(COALESCE(d->>'barcode_value', '')), '');
  v_link  text := NULLIF(btrim(COALESCE(d->>'link_url', '')), '');
  v_img   text := NULLIF(btrim(COALESCE(d->>'image_path', '')), '');
  v_sort  integer := COALESCE(NULLIF(d->>'sort_order', '')::integer, 100);
  v_until date := NULLIF(d->>'valid_until', '')::date;
  v_id    uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(v_name) < 2 OR length(v_name) > 80 THEN
    RAISE EXCEPTION 'O nome tem de ter entre 2 e 80 carateres.';
  END IF;
  IF v_kind NOT IN ('fuel_station', 'garden_store', 'equipment', 'services', 'other') THEN
    RAISE EXCEPTION 'Tipo de parceiro desconhecido.';
  END IF;
  IF v_status NOT IN ('prospect', 'active', 'ended') THEN
    RAISE EXCEPTION 'Estado de parceiro desconhecido.';
  END IF;
  IF (v_lat IS NULL) <> (v_lng IS NULL) THEN
    RAISE EXCEPTION 'A localização precisa de latitude e longitude.';
  END IF;
  -- Portugal continental, Açores e Madeira.
  IF v_lat IS NOT NULL AND (v_lat NOT BETWEEN 30 AND 42.2 OR v_lng NOT BETWEEN -31.5 AND -6.1) THEN
    RAISE EXCEPTION 'Escolhe a localização em Portugal (pesquisa a morada ou toca no mapa).';
  END IF;
  IF length(COALESCE(d->>'headline', '')) > 80 THEN
    RAISE EXCEPTION 'A frase do banner tem de ter até 80 carateres.';
  END IF;
  IF length(COALESCE(d->>'description', '')) > 2000 THEN
    RAISE EXCEPTION 'A descrição tem de ter até 2000 carateres.';
  END IF;
  IF length(COALESCE(d->>'terms', '')) > 1000 OR length(COALESCE(d->>'notes', '')) > 1000 THEN
    RAISE EXCEPTION 'As condições e as notas têm de ter até 1000 carateres.';
  END IF;
  IF length(COALESCE(d->>'discount_code', '')) > 40 THEN
    RAISE EXCEPTION 'O código de desconto tem de ter até 40 carateres.';
  END IF;
  IF v_fmt NOT IN ('code128', 'ean13') THEN
    RAISE EXCEPTION 'Formato de código de barras desconhecido.';
  END IF;
  IF v_bar IS NOT NULL THEN
    IF v_fmt = 'ean13' AND NOT public.is_valid_ean13(v_bar) THEN
      RAISE EXCEPTION 'O código EAN-13 tem de ter 13 dígitos e o último tem de bater certo.';
    END IF;
    IF v_fmt = 'code128' AND (v_bar !~ '^[ -~]+$' OR length(v_bar) > 80) THEN
      RAISE EXCEPTION 'O código de barras só pode ter letras sem acentos, números e símbolos simples (até 80).';
    END IF;
  END IF;
  IF length(COALESCE(d->>'qr_value', '')) > 500 THEN
    RAISE EXCEPTION 'O conteúdo do QR tem de ter até 500 carateres.';
  END IF;
  IF v_link IS NOT NULL AND (v_link !~ '^https://[^[:space:]]+$' OR length(v_link) > 500) THEN
    RAISE EXCEPTION 'O link tem de começar por https://.';
  END IF;
  IF length(COALESCE(d->>'link_label', '')) > 40 THEN
    RAISE EXCEPTION 'O texto do botão do link tem de ter até 40 carateres.';
  END IF;
  IF v_img IS NOT NULL AND (v_img LIKE '%..%' OR v_img LIKE '/%' OR length(v_img) > 300) THEN
    RAISE EXCEPTION 'Foto inválida.';
  END IF;
  IF v_sort NOT BETWEEN 0 AND 1000 THEN
    RAISE EXCEPTION 'A ordem tem de estar entre 0 e 1000.';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO partners (kind, name, status, created_by)
    VALUES (v_kind, v_name, v_status, auth.uid())
    RETURNING id INTO v_id;
  ELSE
    SELECT id INTO v_id FROM partners WHERE id = p_id FOR UPDATE;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Parceiro não encontrado.';
    END IF;
  END IF;

  UPDATE partners SET
    kind = v_kind, name = v_name, status = v_status,
    brand = NULLIF(btrim(COALESCE(d->>'brand', '')), ''),
    headline = NULLIF(btrim(COALESCE(d->>'headline', '')), ''),
    description = NULLIF(btrim(COALESCE(d->>'description', '')), ''),
    image_path = v_img,
    discount_code = NULLIF(btrim(COALESCE(d->>'discount_code', '')), ''),
    barcode_value = v_bar, barcode_format = v_fmt,
    qr_value = NULLIF(btrim(COALESCE(d->>'qr_value', '')), ''),
    link_url = v_link,
    link_label = NULLIF(btrim(COALESCE(d->>'link_label', '')), ''),
    terms = NULLIF(btrim(COALESCE(d->>'terms', '')), ''),
    valid_until = v_until,
    visible_in_app = COALESCE((d->>'visible_in_app')::boolean, false),
    pro_plus_only = COALESCE((d->>'pro_plus_only')::boolean, true),
    sort_order = v_sort,
    address = NULLIF(btrim(COALESCE(d->>'address', '')), ''),
    locality = NULLIF(btrim(COALESCE(d->>'locality', '')), ''),
    lat = round(v_lat, 6), lng = round(v_lng, 6),
    notes = NULLIF(btrim(COALESCE(d->>'notes', '')), ''),
    updated_at = now()
  WHERE id = v_id;

  PERFORM public.admin_log(CASE WHEN p_id IS NULL THEN 'partner_created' ELSE 'partner_updated' END,
    v_id, jsonb_build_object('name', v_name, 'status', v_status,
      'visible_in_app', COALESCE((d->>'visible_in_app')::boolean, false)));
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_save_partner(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_partner(uuid, jsonb) TO authenticated, service_role;

-- Apaga e devolve o caminho da foto (a app apaga o ficheiro).
DROP FUNCTION IF EXISTS public.admin_delete_partner(uuid);
CREATE FUNCTION public.admin_delete_partner(p_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_name text;
  v_img  text;
BEGIN
  PERFORM public.assert_verified_admin();
  DELETE FROM partners WHERE id = p_id RETURNING name, image_path INTO v_name, v_img;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Parceiro não encontrado.';
  END IF;
  PERFORM public.admin_log('partner_deleted', p_id, jsonb_build_object('name', v_name));
  RETURN v_img;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_delete_partner(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_partner(uuid) TO authenticated, service_role;

-- Para a app: parceiros ativos e visíveis, dentro da validade. Nos que
-- são só do Pro+, quem não é Pro+ não recebe os códigos (vêm a NULL e
-- locked = true); os has_* dizem o que há, para a app mostrar o que se
-- ganha com o Pro+. Sem estado interno nem notas.
DROP FUNCTION IF EXISTS public.get_partners();
CREATE FUNCTION public.get_partners()
RETURNS TABLE(
  id                uuid,
  kind              text,
  name              text,
  brand             text,
  headline          text,
  description       text,
  image_path        text,
  discount_code     text,
  barcode_value     text,
  barcode_format    text,
  qr_value          text,
  link_url          text,
  link_label        text,
  terms             text,
  valid_until       date,
  address           text,
  locality          text,
  lat               double precision,
  lng               double precision,
  locked            boolean,
  has_discount_code boolean,
  has_barcode       boolean,
  has_qr            boolean,
  -- Distância (km) da base do jardineiro ao parceiro; NULL sem uma das duas.
  distance_km       double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_plus boolean;
  v_lat  numeric;
  v_lng  numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sem sessão.' USING ERRCODE = '42501';
  END IF;
  v_plus := public.worker_active_tier(auth.uid()) = 'pro_plus';
  SELECT wp.base_lat, wp.base_lng INTO v_lat, v_lng
  FROM worker_profiles wp
  WHERE wp.profile_id = auth.uid()
    AND wp.base_lat IS NOT NULL AND NOT (wp.base_lat = 0 AND wp.base_lng = 0);
  RETURN QUERY
  SELECT pa.id, pa.kind, pa.name, pa.brand, pa.headline, pa.description, pa.image_path,
         CASE WHEN l.locked THEN NULL ELSE pa.discount_code END,
         CASE WHEN l.locked THEN NULL ELSE pa.barcode_value END,
         pa.barcode_format,
         CASE WHEN l.locked THEN NULL ELSE pa.qr_value END,
         pa.link_url, pa.link_label, pa.terms, pa.valid_until,
         pa.address, pa.locality, pa.lat::double precision, pa.lng::double precision,
         l.locked,
         pa.discount_code IS NOT NULL, pa.barcode_value IS NOT NULL, pa.qr_value IS NOT NULL,
         d.km
  FROM partners pa
  CROSS JOIN LATERAL (SELECT CASE WHEN v_lat IS NOT NULL AND pa.lat IS NOT NULL
                              THEN public.km_between(v_lat, v_lng, pa.lat, pa.lng)::double precision
                              END AS km) d
  CROSS JOIN LATERAL (SELECT (pa.pro_plus_only AND NOT v_plus
                              AND (pa.discount_code IS NOT NULL OR pa.barcode_value IS NOT NULL
                                   OR pa.qr_value IS NOT NULL)) AS locked) l
  WHERE pa.status = 'active' AND pa.visible_in_app
    AND (pa.valid_until IS NULL OR pa.valid_until >= CURRENT_DATE)
  -- A ordem do painel manda; com a mesma ordem, o mais perto primeiro.
  ORDER BY pa.sort_order, d.km NULLS LAST, pa.name;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_partners() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_partners() TO authenticated, service_role;

-- Parceiro de exemplo, só para ver o ecrã com todos os campos (sem foto;
-- a foto põe-se no painel). Apagar no painel (Parceiros) antes do
-- lançamento. Se a migration voltar a correr depois de apagado, ele volta
-- (o id fixo só evita duplicados): nessa altura, tirar este INSERT.
INSERT INTO public.partners (
  id, kind, name, brand, status, headline, description, discount_code,
  barcode_value, barcode_format, qr_value, link_url, link_label, terms,
  visible_in_app, pro_plus_only, sort_order, address, locality, lat, lng, notes)
VALUES (
  '7a1b0000-0000-4000-8000-000000000001', 'fuel_station', 'Parceiro de exemplo',
  'Marca Exemplo', 'active', '10% de desconto em combustível',
  'Exemplo de parceiro para ver como fica o ecrã. Mostra o cartão de cliente na '
  'caixa ou usa o código de desconto. Válido em todos os postos da marca.',
  'PROJARDIM10', 'PJ-EXEMPLO-0001', 'code128', 'https://projardim.pt',
  'https://projardim.pt', 'Ver o site',
  'Exemplo: desconto não acumulável com outras promoções.',
  true, false, 0, 'Avenida da Liberdade 1, Lisboa', 'Lisboa', 38.716000, -9.142000,
  'MOCK: apagar antes do lançamento.')
ON CONFLICT (id) DO NOTHING;


-- ── 3. Zonas: sem resposta e densidade ──────────────────────────

-- O país em quadrados de p_cell_km (5 a 50). Só vêm quadrados com
-- pedidos do período, base de jardineiros ou gasolineiras (não acabadas).
-- "Sem resposta" = pedido que acabou sem resposta (no_response) ou ainda
-- aberto há mais de 24 h sem nenhuma proposta. workers_covering conta os
-- jardineiros cujo raio chega ao centro do quadrado.
DROP FUNCTION IF EXISTS public.admin_map_zones(integer, numeric);
CREATE FUNCTION public.admin_map_zones(p_days integer DEFAULT 90, p_cell_km numeric DEFAULT 10)
RETURNS TABLE(
  cell                        text,
  lat_min                     double precision,
  lng_min                     double precision,
  lat_max                     double precision,
  lng_max                     double precision,
  area                        text,
  jobs                        integer,
  jobs_unanswered             integer,
  jobs_completed              integer,
  median_hours_first_proposal double precision,
  workers_based               integer,
  workers_covering            integer,
  partners                    integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_km   double precision := LEAST(GREATEST(COALESCE(p_cell_km, 10), 5), 50);
  -- Graus por quadrado; a longitude à latitude média de Portugal.
  v_dlat double precision := v_km / 111.0;
  v_dlng double precision := v_km / (111.32 * cos(radians(39.5)));
  v_from timestamptz := public.admin_period_start(p_days);
BEGIN
  PERFORM public.assert_verified_admin();

  RETURN QUERY
  WITH j AS (
    SELECT floor(jr.location_lat::double precision / v_dlat)::integer AS iy,
           floor(jr.location_lng::double precision / v_dlng)::integer AS ix,
           jr.location_area AS area, jr.status,
           (jr.status = 'no_response'
            OR (jr.status = 'open' AND jr.created_at < now() - interval '24 hours'
                AND NOT EXISTS (SELECT 1 FROM job_proposals jp WHERE jp.job_id = jr.id))) AS unanswered,
           (SELECT EXTRACT(EPOCH FROM (min(jp.created_at) - jr.created_at)) / 3600.0
            FROM job_proposals jp WHERE jp.job_id = jr.id) AS hours_first
    FROM job_requests jr
    WHERE jr.created_at >= v_from
      AND jr.location_lat IS NOT NULL AND jr.location_lng IS NOT NULL
      AND public.admin_counts_person(jr.client_id)
  ),
  w AS (
    SELECT b.*, floor(b.lat::double precision / v_dlat)::integer AS iy,
           floor(b.lng::double precision / v_dlng)::integer AS ix
    FROM public.admin_active_worker_bases() b
  ),
  pa AS (
    SELECT floor(pl.lat::double precision / v_dlat)::integer AS iy,
           floor(pl.lng::double precision / v_dlng)::integer AS ix, pl.locality
    FROM partners pl WHERE pl.status <> 'ended' AND pl.lat IS NOT NULL
  ),
  cells AS (
    SELECT iy, ix FROM j UNION SELECT iy, ix FROM w UNION SELECT iy, ix FROM pa
  )
  SELECT c.iy || ':' || c.ix,
         c.iy * v_dlat, c.ix * v_dlng, (c.iy + 1) * v_dlat, (c.ix + 1) * v_dlng,
         COALESCE(
           (SELECT mode() WITHIN GROUP (ORDER BY j.area) FROM j
            WHERE j.iy = c.iy AND j.ix = c.ix AND j.area IS NOT NULL),
           (SELECT mode() WITHIN GROUP (ORDER BY pa.locality) FROM pa
            WHERE pa.iy = c.iy AND pa.ix = c.ix AND pa.locality IS NOT NULL),
           (SELECT mode() WITHIN GROUP (ORDER BY w.location_name) FROM w
            WHERE w.iy = c.iy AND w.ix = c.ix AND w.location_name IS NOT NULL)),
         (SELECT count(*)::integer FROM j WHERE j.iy = c.iy AND j.ix = c.ix),
         (SELECT count(*)::integer FROM j WHERE j.iy = c.iy AND j.ix = c.ix AND j.unanswered),
         (SELECT count(*)::integer FROM j WHERE j.iy = c.iy AND j.ix = c.ix AND j.status = 'completed'),
         (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY j.hours_first))::numeric, 1)::double precision
          FROM j WHERE j.iy = c.iy AND j.ix = c.ix AND j.hours_first IS NOT NULL),
         (SELECT count(*)::integer FROM w WHERE w.iy = c.iy AND w.ix = c.ix),
         (SELECT count(*)::integer FROM w
          WHERE public.km_between(w.lat, w.lng,
                  ((c.iy + 0.5) * v_dlat)::numeric, ((c.ix + 0.5) * v_dlng)::numeric) <= w.radius_km),
         (SELECT count(*)::integer FROM pa WHERE pa.iy = c.iy AND pa.ix = c.ix)
  FROM cells c;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_map_zones(integer, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_map_zones(integer, numeric) TO authenticated, service_role;


-- ── 4. Avisos de parceiro novo ──────────────────────────────────

-- Um aviso pode apontar para um parceiro: os jardineiros recebem-no com o
-- tipo 'partner_new' (relatedId = parceiro) e, ao tocar, abre o ecrã
-- dele. Só para jardineiros e só se o parceiro aparece na app.
ALTER TABLE public.admin_notices
  ADD COLUMN IF NOT EXISTS partner_id uuid REFERENCES public.partners(id) ON DELETE SET NULL;

DROP FUNCTION IF EXISTS public.admin_send_notice(text, text, text, text[], uuid, text, integer);
DROP FUNCTION IF EXISTS public.admin_send_notice(text, text, text, text[], uuid, text, integer, uuid);
CREATE FUNCTION public.admin_send_notice(
  p_title           text,
  p_body            text,
  p_role            text,
  p_tiers           text[],
  p_service_type_id uuid,
  p_area            text,
  p_expected        integer,
  p_partner_id      uuid DEFAULT NULL
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
  v_partner  text;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_check_notice_audience(p_role, p_tiers);
  IF length(v_title) < 3 OR length(v_title) > 80 THEN
    RAISE EXCEPTION 'O título tem de ter entre 3 e 80 carateres.';
  END IF;
  IF length(v_body) < 10 OR length(v_body) > 500 THEN
    RAISE EXCEPTION 'O texto tem de ter entre 10 e 500 carateres.';
  END IF;
  IF p_partner_id IS NOT NULL THEN
    IF p_role <> 'worker' THEN
      RAISE EXCEPTION 'Os avisos de parceiro são só para jardineiros.';
    END IF;
    SELECT pa.name INTO v_partner FROM partners pa
    WHERE pa.id = p_partner_id AND pa.status = 'active' AND pa.visible_in_app
      AND (pa.valid_until IS NULL OR pa.valid_until >= CURRENT_DATE);
    IF v_partner IS NULL THEN
      RAISE EXCEPTION 'Este parceiro não aparece na app (tem de estar "Parceiro", com "Mostrar na app" e dentro da validade).';
    END IF;
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
  INSERT INTO admin_notices (title, body, audience, recipients, created_by, partner_id)
  VALUES (v_title, v_body, v_audience, v_n, auth.uid(), p_partner_id)
  RETURNING id INTO v_id;

  -- Com parceiro, relatedId é o parceiro (a app abre-o); sem parceiro, é o
  -- envio, como na 0081.
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT r.user_id,
         CASE WHEN p_partner_id IS NULL THEN 'admin_notice' ELSE 'partner_new' END,
         v_title, v_body,
         COALESCE(p_partner_id, v_id),
         CASE WHEN p_partner_id IS NULL THEN 'admin_notice' ELSE 'partner' END
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area) r;

  PERFORM public.admin_log('send_notice', v_id, v_audience || jsonb_strip_nulls(jsonb_build_object(
    'title', v_title, 'recipients', v_n, 'partner', v_partner)));
  RETURN v_n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_send_notice(text, text, text, text[], uuid, text, integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_notice(text, text, text, text[], uuid, text, integer, uuid) TO authenticated, service_role;

-- O histórico diz de que parceiro era o aviso. Os lidos de um aviso de
-- parceiro contam-se pelo parceiro e pela hora do envio (a mesma
-- transação dá o mesmo now() às duas tabelas).
DROP FUNCTION IF EXISTS public.admin_list_notices(integer, integer);
CREATE FUNCTION public.admin_list_notices(p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
RETURNS TABLE(
  id           uuid,
  title        text,
  body         text,
  audience     jsonb,
  recipients   integer,
  read_count   integer,
  created_at   timestamptz,
  admin_email  text,
  partner_id   uuid,
  partner_name text,
  total_count  bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT n.id, n.title, n.body, n.audience, n.recipients,
         CASE WHEN n.partner_id IS NULL THEN
           (SELECT count(*)::integer FROM notifications x
            WHERE x.related_id = n.id AND x.type = 'admin_notice' AND x.read)
         ELSE
           (SELECT count(*)::integer FROM notifications x
            WHERE x.related_id = n.partner_id AND x.type = 'partner_new'
              AND x.created_at = n.created_at AND x.read)
         END,
         n.created_at, u.email::text, n.partner_id, pa.name, count(*) OVER ()
  FROM admin_notices n
  LEFT JOIN auth.users u ON u.id = n.created_by
  LEFT JOIN partners pa ON pa.id = n.partner_id
  ORDER BY n.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_notices(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_notices(integer, integer) TO authenticated, service_role;
