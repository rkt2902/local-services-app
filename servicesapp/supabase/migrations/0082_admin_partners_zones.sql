-- ══════════════════════════════════════════════════════════════
-- 0082 — Painel de admin: cartões frota, gasolineiras parceiras e
--        zonas no mapa
-- ══════════════════════════════════════════════════════════════
--
-- NÃO APLICADA. Aplicar à mão no SQL Editor do Supabase, depois da 0081.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. Cartões frota no painel: admin_list_fleet_cards e
--      admin_review_fleet_card (aprovar, recusar, retirar). Deixa de ser
--      preciso o UPDATE à mão no SQL Editor (0037). O jardineiro recebe
--      um aviso (tipo 'fleet_card_reviewed') e vê a mensagem da recusa.
--   2. Gasolineiras parceiras (tabela partner_locations, só do painel):
--      admin_list_partner_locations (com jardineiros e pedidos perto),
--      admin_save_partner_location, admin_delete_partner_location.
--   3. admin_map_zones: o país em quadrados (10 km por omissão) com
--      pedidos, pedidos sem resposta, jardineiros que cobrem a zona e
--      gasolineiras, para as camadas "Sem resposta" e "Densidade".
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


-- ── 2. Gasolineiras parceiras ───────────────────────────────────

CREATE TABLE IF NOT EXISTS public.partner_locations (
  id         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  kind       text        NOT NULL DEFAULT 'fuel_station'
                         CHECK (kind IN ('fuel_station', 'other')),
  name       text        NOT NULL,
  brand      text,
  -- prospect = em conversa; active = parceira; ended = deixou de ser.
  status     text        NOT NULL DEFAULT 'prospect'
                         CHECK (status IN ('prospect', 'active', 'ended')),
  address    text,
  locality   text,
  lat        numeric(9,6) NOT NULL,
  lng        numeric(9,6) NOT NULL,
  notes      text,
  created_by uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.partner_locations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.partner_locations FROM anon, authenticated;

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

-- "Perto" de uma gasolineira = 10 km. Pedidos dos últimos 90 dias.
DROP FUNCTION IF EXISTS public.admin_list_partner_locations();
CREATE FUNCTION public.admin_list_partner_locations()
RETURNS TABLE(
  id                 uuid,
  kind               text,
  name               text,
  brand              text,
  status             text,
  address            text,
  locality           text,
  lat                double precision,
  lng                double precision,
  notes              text,
  created_at         timestamptz,
  updated_at         timestamptz,
  workers_covering   integer,
  workers_nearby     integer,
  jobs_nearby        integer,
  jobs_unanswered    integer
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
  SELECT pl.id, pl.kind, pl.name, pl.brand, pl.status, pl.address, pl.locality,
         pl.lat::double precision, pl.lng::double precision, pl.notes,
         pl.created_at, pl.updated_at,
         (SELECT count(*)::integer FROM w
          WHERE public.km_between(w.lat, w.lng, pl.lat, pl.lng) <= w.radius_km),
         (SELECT count(*)::integer FROM w
          WHERE public.km_between(w.lat, w.lng, pl.lat, pl.lng) <= 10),
         (SELECT count(*)::integer FROM j
          WHERE public.km_between(j.lat, j.lng, pl.lat, pl.lng) <= 10),
         (SELECT count(*)::integer FROM j
          WHERE j.unanswered AND public.km_between(j.lat, j.lng, pl.lat, pl.lng) <= 10)
  FROM partner_locations pl
  ORDER BY CASE pl.status WHEN 'active' THEN 0 WHEN 'prospect' THEN 1 ELSE 2 END,
           pl.name;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_partner_locations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_partner_locations() TO authenticated, service_role;

-- p_id NULL cria; senão altera. Devolve o id.
DROP FUNCTION IF EXISTS public.admin_save_partner_location(uuid, text, text, text, text, text, text, numeric, numeric, text);
CREATE FUNCTION public.admin_save_partner_location(
  p_id       uuid,
  p_name     text,
  p_brand    text,
  p_kind     text,
  p_status   text,
  p_address  text,
  p_locality text,
  p_lat      numeric,
  p_lng      numeric,
  p_notes    text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_name text := btrim(COALESCE(p_name, ''));
  v_id   uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(v_name) < 2 OR length(v_name) > 80 THEN
    RAISE EXCEPTION 'O nome tem de ter entre 2 e 80 carateres.';
  END IF;
  IF COALESCE(p_kind, '') NOT IN ('fuel_station', 'other') THEN
    RAISE EXCEPTION 'Tipo de parceiro desconhecido.';
  END IF;
  IF COALESCE(p_status, '') NOT IN ('prospect', 'active', 'ended') THEN
    RAISE EXCEPTION 'Estado de parceiro desconhecido.';
  END IF;
  -- Portugal continental, Açores e Madeira.
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat NOT BETWEEN 30 AND 42.2 OR p_lng NOT BETWEEN -31.5 AND -6.1 THEN
    RAISE EXCEPTION 'Escolhe a localização em Portugal (pesquisa a morada ou toca no mapa).';
  END IF;
  IF length(COALESCE(p_notes, '')) > 1000 THEN
    RAISE EXCEPTION 'As notas têm de ter até 1000 carateres.';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO partner_locations (kind, name, brand, status, address, locality, lat, lng, notes, created_by)
    VALUES (p_kind, v_name, NULLIF(btrim(COALESCE(p_brand, '')), ''), p_status,
            NULLIF(btrim(COALESCE(p_address, '')), ''), NULLIF(btrim(COALESCE(p_locality, '')), ''),
            round(p_lat, 6), round(p_lng, 6), NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid())
    RETURNING id INTO v_id;
    PERFORM public.admin_log('partner_created', v_id,
      jsonb_build_object('name', v_name, 'status', p_status));
  ELSE
    UPDATE partner_locations
    SET kind = p_kind, name = v_name, brand = NULLIF(btrim(COALESCE(p_brand, '')), ''),
        status = p_status, address = NULLIF(btrim(COALESCE(p_address, '')), ''),
        locality = NULLIF(btrim(COALESCE(p_locality, '')), ''),
        lat = round(p_lat, 6), lng = round(p_lng, 6),
        notes = NULLIF(btrim(COALESCE(p_notes, '')), ''), updated_at = now()
    WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Parceiro não encontrado.';
    END IF;
    PERFORM public.admin_log('partner_updated', v_id,
      jsonb_build_object('name', v_name, 'status', p_status));
  END IF;
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_save_partner_location(uuid, text, text, text, text, text, text, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_partner_location(uuid, text, text, text, text, text, text, numeric, numeric, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_delete_partner_location(uuid);
CREATE FUNCTION public.admin_delete_partner_location(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_name text;
BEGIN
  PERFORM public.assert_verified_admin();
  DELETE FROM partner_locations WHERE id = p_id RETURNING name INTO v_name;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Parceiro não encontrado.';
  END IF;
  PERFORM public.admin_log('partner_deleted', p_id, jsonb_build_object('name', v_name));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_delete_partner_location(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_partner_location(uuid) TO authenticated, service_role;


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
    FROM partner_locations pl WHERE pl.status <> 'ended'
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
