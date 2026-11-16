-- ══════════════════════════════════════════════════════════════
-- 0078 — Painel de admin para suporte, fase A (Rastrear)
-- ══════════════════════════════════════════════════════════════
--
-- NÃO APLICADA. Aplicar à mão no SQL Editor do Supabase, depois da 0077.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. job_events: linha do tempo de cada pedido (quem fez o quê e
--      quando). Preenchida por triggers em job_requests, job_proposals,
--      job_work_days, job_reports, ratings e help_requests. Os crons
--      escrevem aqui sozinhos, porque mudam as mesmas tabelas: sem
--      auth.uid() o evento fica como "sistema". Pedidos antigos recebem
--      os eventos que dá para tirar dos carimbos que já existem
--      (marcados com data.backfill = true).
--   2. RPCs de leitura do painel: admin_search, admin_list_jobs,
--      admin_get_job, admin_get_job_photos, admin_list_clients,
--      admin_get_client, admin_reveal_contact.
--   3. admin_list_workers e admin_get_worker (0060) passam a devolver o
--      telefone mascarado; o número inteiro só sai de admin_reveal_contact.
--      admin_get_worker passa a registar a consulta.
--
-- Regras de acesso (iguais à 0060): todas as admin_* chamam
-- assert_verified_admin() primeiro (admin_users + aal2). Nenhuma recebe
-- o id do admin: quem chama é sempre auth.uid(). Os ids que recebem são
-- do ALVO (pedido, pessoa). job_events não tem policies: só as funções
-- SECURITY DEFINER lhe mexem.
--
-- Ler regista-se: abrir a ficha de um pedido ou de uma pessoa, ver as
-- fotos, revelar telefone ou morada e cada pesquisa criam uma linha em
-- admin_actions. Por isso estas RPCs são VOLATILE (escrevem).
--
-- A Agenda do jardineiro (worker_calendar_entries) nunca é lida aqui.
-- ══════════════════════════════════════════════════════════════


-- ── 1. job_events ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.job_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      uuid        NOT NULL REFERENCES public.job_requests(id) ON DELETE CASCADE,
  event_type  text        NOT NULL,
  actor_id    uuid,
  actor_kind  text        NOT NULL DEFAULT 'system',
  data        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.job_events DROP CONSTRAINT IF EXISTS job_events_actor_kind_check;
ALTER TABLE public.job_events ADD CONSTRAINT job_events_actor_kind_check
  CHECK (actor_kind IN ('client', 'worker', 'helper', 'admin', 'system', 'user'));
CREATE INDEX IF NOT EXISTS job_events_job_idx
  ON public.job_events (job_id, created_at);
ALTER TABLE public.job_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.job_events FROM anon, authenticated;

-- Quem fez a mudança, visto do pedido. Sem auth.uid() (crons, SQL
-- Editor) é o sistema.
CREATE OR REPLACE FUNCTION public.job_event_actor_kind(p_job_id uuid, p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_uid IS NULL THEN 'system'
    WHEN EXISTS (SELECT 1 FROM admin_users WHERE user_id = p_uid) THEN 'admin'
    WHEN EXISTS (SELECT 1 FROM job_requests WHERE id = p_job_id AND client_id = p_uid) THEN 'client'
    WHEN EXISTS (SELECT 1 FROM job_proposals WHERE job_id = p_job_id AND worker_id = p_uid) THEN 'worker'
    WHEN EXISTS (SELECT 1 FROM job_requests WHERE id = p_job_id
                 AND (direct_worker_id = p_uid OR direct_card_worker_id = p_uid)) THEN 'worker'
    WHEN EXISTS (SELECT 1 FROM help_acceptances ha
                 JOIN help_requests hr ON hr.id = ha.help_request_id
                 WHERE hr.job_id = p_job_id AND ha.worker_id = p_uid) THEN 'helper'
    ELSE 'user'
  END
$function$;
REVOKE EXECUTE ON FUNCTION public.job_event_actor_kind(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Escreve um evento. Nunca deixa rebentar a ação que o originou: se
-- falhar, fica um WARNING no log e a ação segue.
CREATE OR REPLACE FUNCTION public.log_job_event(
  p_job_id uuid,
  p_type   text,
  p_data   jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  INSERT INTO job_events (job_id, event_type, actor_id, actor_kind, data)
  VALUES (p_job_id, p_type, v_uid,
          public.job_event_actor_kind(p_job_id, v_uid),
          COALESCE(jsonb_strip_nulls(p_data), '{}'::jsonb));
EXCEPTION WHEN others THEN
  RAISE WARNING 'log_job_event(%, %): %', p_job_id, p_type, SQLERRM;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.log_job_event(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;


-- ── 2. Triggers ─────────────────────────────────────────────────

-- job_requests: criado, estados, início, remarcações, visibilidade,
-- reserva do pedido direto e fotos de antes e depois.
CREATE OR REPLACE FUNCTION public.trg_job_events_job_requests()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.log_job_event(NEW.id, 'created', jsonb_build_object(
      'date_mode',      NEW.date_mode,
      'preferred_date', NEW.preferred_date,
      'urgency',        NEW.urgency,
      'direct',         NEW.direct_worker_id IS NOT NULL,
      'direct_origin',  NEW.direct_origin,
      'reopened_from',  NEW.reopened_from));
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_type := CASE
      WHEN NEW.status = 'confirmed' AND OLD.status = 'open' THEN 'accepted'
      WHEN NEW.status = 'awaiting_confirmation' THEN 'marked_done'
      WHEN NEW.status = 'completed' THEN 'completed'
      WHEN NEW.status = 'cancelled' THEN 'cancelled'
      WHEN NEW.status = 'no_response' THEN 'expired'
      ELSE 'status_changed'
    END;
    PERFORM public.log_job_event(NEW.id, v_type, jsonb_build_object(
      'from',          OLD.status,
      'to',            NEW.status,
      'proposal_id',   CASE WHEN v_type = 'accepted' THEN NEW.accepted_proposal_id END,
      'cancelled_by',  CASE WHEN v_type = 'cancelled' THEN NEW.cancelled_by END,
      'reason',        CASE WHEN v_type = 'cancelled' THEN NEW.cancel_reason END,
      'reason_detail', CASE WHEN v_type = 'cancelled' THEN NEW.cancel_reason_detail END));
  END IF;

  IF NEW.started_at IS NOT NULL AND OLD.started_at IS NULL THEN
    PERFORM public.log_job_event(NEW.id, 'started', '{}'::jsonb);
  END IF;

  IF NEW.reschedule_status IS DISTINCT FROM OLD.reschedule_status
     AND NEW.reschedule_status IS NOT NULL THEN
    PERFORM public.log_job_event(NEW.id, 'reschedule_' || NEW.reschedule_status,
      jsonb_build_object(
        'date',     NEW.reschedule_proposed_date,
        'time',     NEW.reschedule_proposed_time,
        'flexible', NEW.reschedule_proposed_flexible,
        'by',       NEW.reschedule_proposed_by));
  END IF;

  -- Data marcada mudou sem ser na aceitação (essa já fica em 'accepted').
  IF NEW.status = OLD.status
     AND (NEW.confirmed_date IS DISTINCT FROM OLD.confirmed_date
          OR NEW.confirmed_time IS DISTINCT FROM OLD.confirmed_time
          OR NEW.confirmed_flexible IS DISTINCT FROM OLD.confirmed_flexible) THEN
    PERFORM public.log_job_event(NEW.id, 'date_changed', jsonb_build_object(
      'from_date', OLD.confirmed_date, 'from_time', OLD.confirmed_time,
      'to_date',   NEW.confirmed_date, 'to_time',   NEW.confirmed_time,
      'flexible',  NEW.confirmed_flexible));
  END IF;

  IF COALESCE(NEW.search_extra_km, 0) > COALESCE(OLD.search_extra_km, 0) THEN
    PERFORM public.log_job_event(NEW.id, 'search_widened',
      jsonb_build_object('extra_km', NEW.search_extra_km));
  END IF;

  IF NEW.direct_status IS DISTINCT FROM OLD.direct_status
     AND NEW.direct_status IS NOT NULL THEN
    PERFORM public.log_job_event(NEW.id, 'direct_' || NEW.direct_status,
      jsonb_build_object('reason', NEW.direct_hold_reason));
  END IF;

  IF cardinality(COALESCE(NEW.before_photo_paths, '{}')) > cardinality(COALESCE(OLD.before_photo_paths, '{}')) THEN
    PERFORM public.log_job_event(NEW.id, 'photos_before',
      jsonb_build_object('count', cardinality(NEW.before_photo_paths)));
  END IF;
  IF cardinality(COALESCE(NEW.after_photo_paths, '{}')) > cardinality(COALESCE(OLD.after_photo_paths, '{}')) THEN
    PERFORM public.log_job_event(NEW.id, 'photos_after',
      jsonb_build_object('count', cardinality(NEW.after_photo_paths)));
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_job_requests ON public.job_requests;
CREATE TRIGGER trg_job_events_job_requests
  AFTER INSERT OR UPDATE ON public.job_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_job_requests();

-- job_proposals: enviada e mudanças de estado. 'superseded' pelo próprio
-- jardineiro é "retirada"; pelo sistema ou pela aceitação de outra é
-- "fechada".
CREATE OR REPLACE FUNCTION public.trg_job_events_job_proposals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.log_job_event(NEW.job_id, 'proposal_sent', jsonb_build_object(
      'proposal_id',  NEW.id,
      'worker_id',    NEW.worker_id,
      'pricing_mode', NEW.pricing_mode,
      'hourly_rate',  NEW.hourly_rate,
      'total_price',  NEW.total_price));
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'accepted' THEN
    PERFORM public.log_job_event(NEW.job_id,
      CASE
        WHEN NEW.status = 'superseded' AND auth.uid() = NEW.worker_id THEN 'proposal_withdrawn'
        WHEN NEW.status = 'superseded' THEN 'proposal_closed'
        ELSE 'proposal_' || NEW.status
      END,
      jsonb_build_object('proposal_id', NEW.id, 'worker_id', NEW.worker_id,
                         'from', OLD.status, 'to', NEW.status));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_job_proposals ON public.job_proposals;
CREATE TRIGGER trg_job_events_job_proposals
  AFTER INSERT OR UPDATE OF status ON public.job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_job_proposals();

-- job_work_days: começo e fim de cada dia (trabalhos com relógio).
CREATE OR REPLACE FUNCTION public.trg_job_events_work_days()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.started_at IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.started_at IS NULL) THEN
    PERFORM public.log_job_event(NEW.job_id, 'day_started',
      jsonb_build_object('day', NEW.day_number));
  END IF;
  IF NEW.ended_at IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.ended_at IS NULL) THEN
    PERFORM public.log_job_event(NEW.job_id, 'day_ended',
      jsonb_build_object('day', NEW.day_number));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_work_days ON public.job_work_days;
CREATE TRIGGER trg_job_events_work_days
  AFTER INSERT OR UPDATE OF started_at, ended_at ON public.job_work_days
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_work_days();

-- job_reports: "Reportar um problema".
CREATE OR REPLACE FUNCTION public.trg_job_events_reports()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.log_job_event(NEW.job_id, 'reported', jsonb_build_object(
    'report_id', NEW.id, 'reporter_id', NEW.reporter_id));
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_reports ON public.job_reports;
CREATE TRIGGER trg_job_events_reports
  AFTER INSERT ON public.job_reports
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_reports();

-- ratings: avaliação feita.
CREATE OR REPLACE FUNCTION public.trg_job_events_ratings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.job_id IS NOT NULL THEN
    PERFORM public.log_job_event(NEW.job_id, 'rated', jsonb_build_object(
      'rating_id', NEW.id, 'rater_id', NEW.rater_id,
      'ratee_id',  NEW.ratee_id, 'stars', NEW.stars));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_ratings ON public.ratings;
CREATE TRIGGER trg_job_events_ratings
  AFTER INSERT ON public.ratings
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_ratings();

-- help_requests: pedido de ajuda criado e mudanças de estado (aprovação
-- do cliente, vagas preenchidas, cancelado).
CREATE OR REPLACE FUNCTION public.trg_job_events_help_requests()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.log_job_event(NEW.job_id, 'help_requested', jsonb_build_object(
      'help_request_id', NEW.id, 'slots', NEW.slots_needed, 'status', NEW.status));
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM public.log_job_event(NEW.job_id, 'help_' || NEW.status, jsonb_build_object(
      'help_request_id', NEW.id, 'from', OLD.status));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_events_help_requests ON public.help_requests;
CREATE TRIGGER trg_job_events_help_requests
  AFTER INSERT OR UPDATE OF status ON public.help_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_job_events_help_requests();

REVOKE EXECUTE ON FUNCTION
  public.trg_job_events_job_requests(), public.trg_job_events_job_proposals(),
  public.trg_job_events_work_days(), public.trg_job_events_reports(),
  public.trg_job_events_ratings(), public.trg_job_events_help_requests()
  FROM PUBLIC, anon, authenticated;


-- ── 3. Eventos de pedidos antigos (a partir dos carimbos) ───────
-- Só para pedidos sem nenhum evento, por isso correr outra vez não
-- duplica nada.

WITH old_jobs AS (
  SELECT jr.* FROM job_requests jr
  WHERE NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = jr.id)
), accepted AS (
  SELECT jp.* FROM job_proposals jp JOIN old_jobs oj ON oj.accepted_proposal_id = jp.id
)
INSERT INTO job_events (job_id, event_type, actor_id, actor_kind, data, created_at)
SELECT job_id, event_type, actor_id, actor_kind, data || '{"backfill": true}'::jsonb, created_at
FROM (
  SELECT oj.id AS job_id, 'created' AS event_type, oj.client_id AS actor_id,
         'client' AS actor_kind,
         jsonb_strip_nulls(jsonb_build_object('date_mode', oj.date_mode,
           'direct', oj.direct_worker_id IS NOT NULL,
           'reopened_from', oj.reopened_from)) AS data,
         oj.created_at
  FROM old_jobs oj
  UNION ALL
  SELECT jp.job_id, 'proposal_sent', jp.worker_id, 'worker',
         jsonb_build_object('proposal_id', jp.id, 'worker_id', jp.worker_id),
         jp.created_at
  FROM job_proposals jp JOIN old_jobs oj ON oj.id = jp.job_id
  UNION ALL
  SELECT a.job_id, 'accepted', oj.client_id, 'client',
         jsonb_build_object('proposal_id', a.id),
         COALESCE(a.accepted_at, a.updated_at)
  FROM accepted a JOIN old_jobs oj ON oj.id = a.job_id
  UNION ALL
  SELECT oj.id, 'started', a.worker_id, 'worker', '{}'::jsonb, oj.started_at
  FROM old_jobs oj JOIN accepted a ON a.id = oj.accepted_proposal_id
  WHERE oj.started_at IS NOT NULL
  UNION ALL
  SELECT oj.id, 'marked_done', a.worker_id, 'worker', '{}'::jsonb, oj.marked_done_at
  FROM old_jobs oj JOIN accepted a ON a.id = oj.accepted_proposal_id
  WHERE oj.marked_done_at IS NOT NULL
  UNION ALL
  SELECT oj.id, 'cancelled', oj.cancelled_by,
         CASE WHEN oj.cancelled_by IS NULL THEN 'system'
              WHEN oj.cancelled_by = oj.client_id THEN 'client' ELSE 'worker' END,
         jsonb_strip_nulls(jsonb_build_object('cancelled_by', oj.cancelled_by,
           'reason', oj.cancel_reason, 'reason_detail', oj.cancel_reason_detail)),
         oj.updated_at
  FROM old_jobs oj WHERE oj.status = 'cancelled'
  UNION ALL
  SELECT r.job_id, 'reported', r.reporter_id,
         CASE WHEN r.reporter_id = oj.client_id THEN 'client' ELSE 'worker' END,
         jsonb_build_object('report_id', r.id, 'reporter_id', r.reporter_id),
         r.created_at
  FROM job_reports r JOIN old_jobs oj ON oj.id = r.job_id
  UNION ALL
  SELECT ra.job_id, 'rated', ra.rater_id,
         CASE WHEN ra.rater_id = oj.client_id THEN 'client' ELSE 'worker' END,
         jsonb_build_object('rating_id', ra.id, 'rater_id', ra.rater_id,
                            'ratee_id', ra.ratee_id, 'stars', ra.stars),
         ra.created_at
  FROM ratings ra JOIN old_jobs oj ON oj.id = ra.job_id
) ev
WHERE created_at IS NOT NULL;


-- ── 4. Ajudas ───────────────────────────────────────────────────

-- "+351 ••• ••• 123": chega para confirmar com a pessoa sem expor o número.
CREATE OR REPLACE FUNCTION public.admin_mask_phone(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_phone IS NULL OR btrim(p_phone) = '' THEN NULL
    WHEN length(regexp_replace(p_phone, '\D', '', 'g')) < 4 THEN '•••'
    ELSE '••• ••• ' || right(regexp_replace(p_phone, '\D', '', 'g'), 3)
  END
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_mask_phone(text) FROM PUBLIC, anon, authenticated;

-- Regista uma ação do admin que está a chamar (nunca recebe o id dele).
CREATE OR REPLACE FUNCTION public.admin_log(p_action text, p_target uuid, p_details jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  INSERT INTO admin_actions (admin_id, action, target_id, details)
  VALUES (auth.uid(), p_action, p_target, COALESCE(p_details, '{}'::jsonb))
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_log(text, uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- Pessoa que trabalhou no pedido (proposta aceite).
CREATE OR REPLACE FUNCTION public.job_accepted_worker_id(p_job_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jp.worker_id FROM job_requests jr
  JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE jr.id = p_job_id
$function$;
REVOKE EXECUTE ON FUNCTION public.job_accepted_worker_id(uuid) FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS notifications_related_idx
  ON public.notifications (related_id, created_at);
CREATE INDEX IF NOT EXISTS admin_actions_created_idx
  ON public.admin_actions (created_at DESC);


-- ── 5. Pesquisa global ──────────────────────────────────────────
-- Aceita email, telefone, nome, id completo ou início de id (6+
-- carateres hexadecimais, como o id curto dos emails de suporte).
-- Devolve no máximo 20 resultados: pedidos, clientes e jardineiros.

DROP FUNCTION IF EXISTS public.admin_search(text);
CREATE FUNCTION public.admin_search(p_q text)
RETURNS TABLE (
  kind      text,
  target_id uuid,
  title     text,
  subtitle  text,
  status    text,
  matched   text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_q      text := btrim(COALESCE(p_q, ''));
  v_lower  text := lower(btrim(COALESCE(p_q, '')));
  v_digits text := regexp_replace(COALESCE(p_q, ''), '\D', '', 'g');
  v_hex    text := lower(regexp_replace(btrim(COALESCE(p_q, '')), '^#', ''));
  v_is_hex boolean;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(v_q) < 2 THEN
    RETURN;
  END IF;
  v_is_hex := v_hex ~ '^[0-9a-f-]{6,36}$';

  PERFORM public.admin_log('search', NULL, jsonb_build_object('q', left(v_q, 120)));

  RETURN QUERY
  WITH people AS (
    SELECT p.id, p.role, p.full_name, p.deleted_at, u.email,
           CASE
             WHEN v_is_hex AND p.id::text LIKE v_hex || '%' THEN 'id'
             WHEN u.email IS NOT NULL AND lower(u.email) = v_lower THEN 'email'
             WHEN v_lower LIKE '%@%' AND lower(COALESCE(u.email, '')) LIKE '%' || v_lower || '%' THEN 'email'
             WHEN length(v_digits) >= 6
                  AND regexp_replace(COALESCE(p.phone, ''), '\D', '', 'g') LIKE '%' || v_digits || '%' THEN 'phone'
             WHEN p.full_name ILIKE '%' || v_q || '%' THEN 'name'
             WHEN v_lower NOT LIKE '%@%' AND length(v_q) >= 3
                  AND lower(COALESCE(u.email, '')) LIKE v_lower || '%' THEN 'email'
           END AS matched
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.role IN ('client', 'worker')
  ), jobs AS (
    SELECT jr.id, jr.status, jr.created_at, jr.location_area,
           st.name AS service_name, c.full_name AS client_name
    FROM job_requests jr
    LEFT JOIN service_types st ON st.id = jr.service_type_id
    LEFT JOIN profiles c ON c.id = jr.client_id
    WHERE v_is_hex AND jr.id::text LIKE v_hex || '%'
  )
  SELECT * FROM (
    SELECT 'job'::text AS r_kind, j.id AS r_id,
           COALESCE(j.service_name, 'Pedido') AS r_title,
           concat_ws(' · ', '#' || left(j.id::text, 8), j.client_name, j.location_area,
                     to_char(j.created_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY')) AS r_subtitle,
           j.status AS r_status, 'id'::text AS r_matched
    FROM jobs j
    UNION ALL
    SELECT pe.role, pe.id,
           COALESCE(NULLIF(btrim(pe.full_name), ''), 'Sem nome'),
           concat_ws(' · ', CASE pe.role WHEN 'client' THEN 'Cliente' ELSE 'Jardineiro' END,
                     pe.email, CASE WHEN pe.deleted_at IS NOT NULL THEN 'conta eliminada' END),
           CASE WHEN pe.deleted_at IS NOT NULL THEN 'deleted' ELSE 'active' END,
           pe.matched
    FROM people pe
    WHERE pe.matched IS NOT NULL
  ) r
  ORDER BY CASE r.r_matched WHEN 'id' THEN 0 WHEN 'email' THEN 1 WHEN 'phone' THEN 2 ELSE 3 END
  LIMIT 20;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_search(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_search(text) TO authenticated, service_role;


-- ── 6. Lista de pedidos ─────────────────────────────────────────
-- Filtros NULL = todos. p_area procura na zona (location_area).
-- p_from/p_to: data de criação (dia de Lisboa).

DROP FUNCTION IF EXISTS public.admin_list_jobs(text, uuid, text, date, date, boolean, boolean, boolean, integer, integer);
CREATE FUNCTION public.admin_list_jobs(
  p_status       text    DEFAULT NULL,
  p_service_id   uuid    DEFAULT NULL,
  p_area         text    DEFAULT NULL,
  p_from         date    DEFAULT NULL,
  p_to           date    DEFAULT NULL,
  p_with_report  boolean DEFAULT NULL,
  p_direct       boolean DEFAULT NULL,
  p_with_helpers boolean DEFAULT NULL,
  p_limit        integer DEFAULT 30,
  p_offset       integer DEFAULT 0
)
RETURNS TABLE (
  job_id          uuid,
  service_name    text,
  client_id       uuid,
  client_name     text,
  worker_id       uuid,
  worker_name     text,
  location_area   text,
  status          text,
  proposal_count  integer,
  date_mode       text,
  preferred_date  date,
  confirmed_date  date,
  created_at      timestamptz,
  updated_at      timestamptz,
  has_report      boolean,
  is_direct       boolean,
  has_helpers     boolean,
  total_count     integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_area text := NULLIF(btrim(COALESCE(p_area, '')), '');
BEGIN
  PERFORM public.assert_verified_admin();

  RETURN QUERY
  WITH base AS (
    SELECT jr.*,
           EXISTS (SELECT 1 FROM job_reports r WHERE r.job_id = jr.id) AS x_report,
           (jr.direct_worker_id IS NOT NULL OR jr.direct_origin IS NOT NULL) AS x_direct,
           EXISTS (SELECT 1 FROM help_requests h WHERE h.job_id = jr.id) AS x_helpers
    FROM job_requests jr
    WHERE (p_status IS NULL OR jr.status = p_status)
      AND (p_service_id IS NULL OR jr.service_type_id = p_service_id)
      AND (v_area IS NULL OR COALESCE(jr.location_area, '') ILIKE '%' || v_area || '%')
      AND (p_from IS NULL OR (jr.created_at AT TIME ZONE 'Europe/Lisbon')::date >= p_from)
      AND (p_to   IS NULL OR (jr.created_at AT TIME ZONE 'Europe/Lisbon')::date <= p_to)
  ), filtered AS (
    SELECT * FROM base b
    WHERE (p_with_report  IS NULL OR b.x_report  = p_with_report)
      AND (p_direct       IS NULL OR b.x_direct  = p_direct)
      AND (p_with_helpers IS NULL OR b.x_helpers = p_with_helpers)
  )
  SELECT f.id, st.name, f.client_id, c.full_name,
         jp.worker_id, w.full_name,
         f.location_area, f.status, COALESCE(f.proposal_count, 0),
         f.date_mode, f.preferred_date, f.confirmed_date,
         f.created_at, f.updated_at,
         f.x_report, f.x_direct, f.x_helpers,
         (count(*) OVER ())::integer
  FROM filtered f
  LEFT JOIN service_types st ON st.id = f.service_type_id
  LEFT JOIN profiles c       ON c.id  = f.client_id
  LEFT JOIN job_proposals jp ON jp.id = f.accepted_proposal_id
  LEFT JOIN profiles w       ON w.id  = jp.worker_id
  ORDER BY f.created_at DESC
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_jobs(text, uuid, text, date, date, boolean, boolean, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_jobs(text, uuid, text, date, date, boolean, boolean, boolean, integer, integer) TO authenticated, service_role;


-- ── 7. Ficha de um pedido ───────────────────────────────────────
-- Cabeçalho, linha do tempo, propostas, equipa e avisos. Sem morada
-- exata (só a zona) e sem fotos: essas saem de admin_reveal_contact e
-- admin_get_job_photos, que registam à parte.

DROP FUNCTION IF EXISTS public.admin_get_job(uuid);
CREATE FUNCTION public.admin_get_job(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests;
  v_worker uuid;
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  v_worker := public.job_accepted_worker_id(p_job_id);

  PERFORM public.admin_log('view_job', p_job_id, '{}'::jsonb);

  WITH help AS (
    SELECT hr.* FROM help_requests hr WHERE hr.job_id = p_job_id
  ), people AS (
    -- Toda a gente ligada ao pedido, para a lista de avisos.
    SELECT v_job.client_id AS uid
    UNION SELECT jp.worker_id FROM job_proposals jp WHERE jp.job_id = p_job_id
    UNION SELECT ha.worker_id FROM help_acceptances ha JOIN help h ON h.id = ha.help_request_id
    UNION SELECT v_job.direct_worker_id WHERE v_job.direct_worker_id IS NOT NULL
  )
  SELECT jsonb_build_object(
    'job_id',          v_job.id,
    'status',          v_job.status,
    'proposal_count',  COALESCE(v_job.proposal_count, 0),
    'service_name',    (SELECT name FROM service_types WHERE id = v_job.service_type_id),
    'description',     v_job.description,
    'size_estimate',   v_job.size_estimate,
    'urgency',         v_job.urgency,
    'location_area',   v_job.location_area,
    'has_address',     btrim(COALESCE(v_job.address_text, '')) <> '',
    'date_mode',       v_job.date_mode,
    'preferred_date',  v_job.preferred_date,
    'availability_text', v_job.availability_text,
    'confirmed_date',  v_job.confirmed_date,
    'confirmed_time',  v_job.confirmed_time,
    'confirmed_flexible', v_job.confirmed_flexible,
    'created_at',      v_job.created_at,
    'updated_at',      v_job.updated_at,
    'started_at',      v_job.started_at,
    'marked_done_at',  v_job.marked_done_at,
    'expires_at',      CASE WHEN v_job.status = 'open' THEN v_job.expires_at END,
    'auto_confirm_at', CASE WHEN v_job.status = 'awaiting_confirmation'
                            THEN v_job.marked_done_at + interval '7 days' END,
    'direct_until',    CASE WHEN v_job.direct_status = 'waiting' THEN v_job.direct_until END,
    'is_direct',       v_job.direct_worker_id IS NOT NULL OR v_job.direct_origin IS NOT NULL,
    'direct_status',   v_job.direct_status,
    'direct_origin',   v_job.direct_origin,
    'cancel_reason',   v_job.cancel_reason,
    'cancel_reason_detail', v_job.cancel_reason_detail,
    'cancelled_by',    v_job.cancelled_by,
    'reopened_from',   v_job.reopened_from,
    'reschedule_status', v_job.reschedule_status,
    'photo_count',     (SELECT count(*) FROM job_photos WHERE job_id = p_job_id)
                       + cardinality(COALESCE(v_job.before_photo_paths, '{}'))
                       + cardinality(COALESCE(v_job.after_photo_paths, '{}'))
                       + CASE WHEN v_job.completion_photo_path IS NULL THEN 0 ELSE 1 END,
    'client',          (SELECT jsonb_build_object('id', p.id, 'full_name', p.full_name,
                                 'avatar_url', p.avatar_url, 'deleted', p.deleted_at IS NOT NULL)
                        FROM profiles p WHERE p.id = v_job.client_id),
    'worker',          (SELECT jsonb_build_object('id', p.id, 'full_name', p.full_name,
                                 'avatar_url', p.avatar_url, 'deleted', p.deleted_at IS NOT NULL)
                        FROM profiles p WHERE p.id = v_worker),
    'direct_worker',   (SELECT jsonb_build_object('id', p.id, 'full_name', p.full_name)
                        FROM profiles p WHERE p.id = v_job.direct_worker_id),
    'timeline',        COALESCE((
      SELECT jsonb_agg(t ORDER BY t.at, t.seq)
      FROM (
        SELECT e.created_at AS at, 0 AS seq, e.event_type AS type, e.actor_kind,
               e.actor_id, ap.full_name AS actor_name, e.data
        FROM job_events e
        LEFT JOIN profiles ap ON ap.id = e.actor_id
        WHERE e.job_id = p_job_id
        UNION ALL
        SELECT a.created_at, 1, 'admin_' || a.action, 'admin',
               a.admin_id, NULL, a.details
        FROM admin_actions a
        WHERE a.target_id = p_job_id AND a.action <> 'view_job'
      ) t), '[]'::jsonb),
    'views',           (SELECT count(*) FROM admin_actions a
                        WHERE a.target_id = p_job_id AND a.action = 'view_job'),
    'proposals',       COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',               jp.id,
               'worker_id',        jp.worker_id,
               'worker_name',      w.full_name,
               'status',           jp.status,
               'is_accepted',      jp.id = v_job.accepted_proposal_id,
               'pricing_mode',     jp.pricing_mode,
               'hourly_rate',      jp.hourly_rate,
               'total_price',      jp.total_price,
               'hours_min',        jp.estimated_hours_min,
               'hours_max',        jp.estimated_hours_max,
               'days_min',         jp.estimated_days_min,
               'days_max',         jp.estimated_days_max,
               'people_needed',    jp.people_needed,
               'includes',         to_jsonb(COALESCE(jp.includes, '{}'::text[])),
               'notes',            jp.notes,
               'scheduled_date',   jp.scheduled_date,
               'scheduled_time',   jp.scheduled_time,
               'scheduled_flexible', jp.scheduled_flexible,
               'valid_until',      jp.valid_until,
               'created_at',       jp.created_at,
               'updated_at',       jp.updated_at,
               'accepted_at',      jp.accepted_at
             ) ORDER BY jp.created_at)
      FROM job_proposals jp
      LEFT JOIN profiles w ON w.id = jp.worker_id
      WHERE jp.job_id = p_job_id), '[]'::jsonb),
    'team',            COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',                 h.id,
               'status',             h.status,
               'slots_needed',       h.slots_needed,
               'equipment_required', h.equipment_required,
               'after_confirmation', h.created_post_confirmation,
               'created_at',         h.created_at,
               'acceptances',        COALESCE((
                 SELECT jsonb_agg(jsonb_build_object(
                          'id',                ha.id,
                          'worker_id',         ha.worker_id,
                          'worker_name',       hw.full_name,
                          'status',            ha.status,
                          'agreed_rate',       ha.agreed_rate,
                          'brought_equipment', ha.brought_equipment,
                          'message',           ha.message,
                          'created_at',        ha.created_at
                        ) ORDER BY ha.created_at)
                 FROM help_acceptances ha
                 LEFT JOIN profiles hw ON hw.id = ha.worker_id
                 WHERE ha.help_request_id = h.id), '[]'::jsonb)
             ) ORDER BY h.created_at)
      FROM help h), '[]'::jsonb),
    'notifications',   COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',          n.id,
               'user_id',     n.user_id,
               'user_name',   np.full_name,
               'user_role',   CASE WHEN n.user_id = v_job.client_id THEN 'client'
                                   WHEN n.user_id = v_worker THEN 'worker'
                                   ELSE 'other' END,
               'type',        n.type,
               'title',       n.title,
               'body',        n.body,
               'read',        n.read,
               'cleared_at',  n.cleared_at,
               'created_at',  n.created_at,
               -- Havia aparelho registado para push quando o aviso saiu?
               -- (Tokens apagados ao terminar sessão já não contam.)
               'had_push_token', EXISTS (SELECT 1 FROM device_tokens dt
                                         WHERE dt.user_id = n.user_id
                                           AND dt.created_at <= n.created_at),
               'has_push_token_now', EXISTS (SELECT 1 FROM device_tokens dt
                                             WHERE dt.user_id = n.user_id)
             ) ORDER BY n.created_at DESC)
      FROM notifications n
      LEFT JOIN profiles np ON np.id = n.user_id
      WHERE n.user_id IN (SELECT uid FROM people WHERE uid IS NOT NULL)
        AND (n.related_id = p_job_id
             OR n.related_id IN (SELECT id FROM help))), '[]'::jsonb),
    'reports',         COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',          r.id,
               'reporter_id', r.reporter_id,
               'reporter_name', rp.full_name,
               'description', r.description,
               'created_at',  r.created_at
             ) ORDER BY r.created_at)
      FROM job_reports r
      LEFT JOIN profiles rp ON rp.id = r.reporter_id
      WHERE r.job_id = p_job_id), '[]'::jsonb),
    'ratings',         COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',         ra.id,
               'rater_id',   ra.rater_id,
               'rater_name', rp.full_name,
               'ratee_id',   ra.ratee_id,
               'stars',      ra.stars,
               'comment',    ra.comment,
               'created_at', ra.created_at
             ) ORDER BY ra.created_at)
      FROM ratings ra
      LEFT JOIN profiles rp ON rp.id = ra.rater_id
      WHERE ra.job_id = p_job_id), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_job(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_job(uuid) TO authenticated, service_role;


-- ── 8. Fotos de um pedido ───────────────────────────────────────
-- Caminhos no bucket job-photos (público hoje, AUD-14). Ver as fotos
-- regista uma ação. Se o bucket passar a privado, isto passa a devolver
-- URLs assinadas.

DROP FUNCTION IF EXISTS public.admin_get_job_photos(uuid);
CREATE FUNCTION public.admin_get_job_photos(p_job_id uuid)
RETURNS TABLE (
  kind         text,
  storage_path text,
  taken_by     text,
  created_at   timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;

  PERFORM public.admin_log('view_job_photos', p_job_id, '{}'::jsonb);

  RETURN QUERY
  SELECT 'request'::text, ph.storage_path, 'client'::text, ph.created_at
  FROM job_photos ph WHERE ph.job_id = p_job_id
  UNION ALL
  SELECT 'before', x.path, 'worker', v_job.started_at
  FROM unnest(COALESCE(v_job.before_photo_paths, '{}'::text[])) AS x(path)
  UNION ALL
  SELECT 'after', x.path, 'worker', v_job.marked_done_at
  FROM unnest(COALESCE(v_job.after_photo_paths, '{}'::text[])) AS x(path)
  UNION ALL
  SELECT 'completion', v_job.completion_photo_path, 'worker', v_job.marked_done_at
  WHERE v_job.completion_photo_path IS NOT NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_job_photos(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_job_photos(uuid) TO authenticated, service_role;


-- ── 9. Lista de clientes ────────────────────────────────────────
-- p_state: NULL = todos; 'active' | 'deleted'. Telefone mascarado.

DROP FUNCTION IF EXISTS public.admin_list_clients(text, text, boolean, integer, integer);
CREATE FUNCTION public.admin_list_clients(
  p_search       text    DEFAULT NULL,
  p_state        text    DEFAULT NULL,
  p_with_reports boolean DEFAULT NULL,
  p_limit        integer DEFAULT 30,
  p_offset       integer DEFAULT 0
)
RETURNS TABLE (
  client_id       uuid,
  full_name       text,
  email           text,
  phone_masked    text,
  avatar_url      text,
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  deleted_at      timestamptz,
  jobs_total      integer,
  jobs_active     integer,
  avg_rating      numeric,
  rating_count    integer,
  reports_count   integer,
  total_count     integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_digits text := regexp_replace(COALESCE(p_search, ''), '\D', '', 'g');
BEGIN
  PERFORM public.assert_verified_admin();

  RETURN QUERY
  WITH base AS (
    SELECT p.id, p.full_name, p.phone, p.avatar_url, p.created_at, p.deleted_at,
           u.email, u.last_sign_in_at,
           -- Reportes que envolvem o cliente: feitos por ele ou nos pedidos dele.
           (SELECT count(*)::integer FROM job_reports r
            JOIN job_requests jr ON jr.id = r.job_id
            WHERE jr.client_id = p.id OR r.reporter_id = p.id) AS x_reports
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.role = 'client'
      AND (p_state IS NULL
           OR (p_state = 'active'  AND p.deleted_at IS NULL)
           OR (p_state = 'deleted' AND p.deleted_at IS NOT NULL))
      AND (v_search IS NULL
           OR p.full_name ILIKE '%' || v_search || '%'
           OR COALESCE(u.email, '') ILIKE '%' || v_search || '%'
           OR (length(v_digits) >= 6
               AND regexp_replace(COALESCE(p.phone, ''), '\D', '', 'g') LIKE '%' || v_digits || '%'))
  ), filtered AS (
    SELECT * FROM base b
    WHERE p_with_reports IS NULL OR (b.x_reports > 0) = p_with_reports
  )
  SELECT f.id, f.full_name, f.email, public.admin_mask_phone(f.phone), f.avatar_url,
         f.created_at, f.last_sign_in_at, f.deleted_at,
         (SELECT count(*)::integer FROM job_requests jr WHERE jr.client_id = f.id),
         (SELECT count(*)::integer FROM job_requests jr WHERE jr.client_id = f.id
            AND jr.status IN ('open', 'confirmed', 'awaiting_confirmation')),
         (SELECT round(avg(r.stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = f.id),
         (SELECT count(*)::integer FROM ratings r WHERE r.ratee_id = f.id),
         f.x_reports,
         (count(*) OVER ())::integer
  FROM filtered f
  ORDER BY f.created_at DESC
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_clients(text, text, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_clients(text, text, boolean, integer, integer) TO authenticated, service_role;


-- ── 10. Ficha de um cliente ─────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_get_client(uuid);
CREATE FUNCTION public.admin_get_client(p_client_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_client_id AND role = 'client') THEN
    RAISE EXCEPTION 'Cliente não encontrado.';
  END IF;

  PERFORM public.admin_log('view_client', p_client_id, '{}'::jsonb);

  SELECT jsonb_build_object(
    'client_id',       p.id,
    'full_name',       p.full_name,
    'email',           u.email,
    'email_confirmed', u.email_confirmed_at IS NOT NULL,
    'phone_masked',    public.admin_mask_phone(p.phone),
    'has_phone',       btrim(COALESCE(p.phone, '')) <> '',
    'avatar_url',      p.avatar_url,
    'created_at',      p.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'deleted_at',      p.deleted_at,
    'push_devices',    (SELECT count(*) FROM device_tokens dt WHERE dt.user_id = p.id),
    'jobs',            COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'job_id',         jr.id,
               'service_name',   st.name,
               'status',         jr.status,
               'proposal_count', COALESCE(jr.proposal_count, 0),
               'location_area',  jr.location_area,
               'worker_name',    w.full_name,
               'created_at',     jr.created_at,
               'has_report',     EXISTS (SELECT 1 FROM job_reports r WHERE r.job_id = jr.id)
             ) ORDER BY jr.created_at DESC)
      FROM job_requests jr
      LEFT JOIN service_types st ON st.id = jr.service_type_id
      LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
      LEFT JOIN profiles w       ON w.id  = jp.worker_id
      WHERE jr.client_id = p.id), '[]'::jsonb),
    'ratings_given',   COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'job_id', ra.job_id, 'ratee_name', rp.full_name, 'stars', ra.stars,
               'comment', ra.comment, 'created_at', ra.created_at
             ) ORDER BY ra.created_at DESC)
      FROM ratings ra LEFT JOIN profiles rp ON rp.id = ra.ratee_id
      WHERE ra.rater_id = p.id), '[]'::jsonb),
    'ratings_received', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'job_id', ra.job_id, 'rater_name', rp.full_name, 'stars', ra.stars,
               'comment', ra.comment, 'created_at', ra.created_at
             ) ORDER BY ra.created_at DESC)
      FROM ratings ra LEFT JOIN profiles rp ON rp.id = ra.rater_id
      WHERE ra.ratee_id = p.id), '[]'::jsonb),
    'reports',         COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'job_id', r.job_id, 'by_client', r.reporter_id = p.id,
               'description', r.description, 'created_at', r.created_at
             ) ORDER BY r.created_at DESC)
      FROM job_reports r JOIN job_requests jr ON jr.id = r.job_id
      WHERE jr.client_id = p.id OR r.reporter_id = p.id), '[]'::jsonb),
    'admin_history',   COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'action', a.action, 'details', a.details, 'created_at', a.created_at
             ) ORDER BY a.created_at DESC)
      FROM (SELECT * FROM admin_actions
            WHERE target_id = p.id AND action <> 'view_client'
            ORDER BY created_at DESC LIMIT 20) a), '[]'::jsonb)
  ) INTO v_result
  FROM profiles p
  LEFT JOIN auth.users u ON u.id = p.id
  WHERE p.id = p_client_id;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_client(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_client(uuid) TO authenticated, service_role;


-- ── 11. Revelar contacto ou morada ──────────────────────────────
-- p_kind 'phone': p_target_id é uma pessoa (cliente ou jardineiro).
-- p_kind 'address': p_target_id é um pedido; devolve a morada exata, as
-- coordenadas do pedido e da base do jardineiro aceite e a distância.
-- Fica sempre registado, com o motivo se vier.

DROP FUNCTION IF EXISTS public.admin_reveal_contact(uuid, text, text);
CREATE FUNCTION public.admin_reveal_contact(
  p_target_id uuid,
  p_kind      text DEFAULT 'phone',
  p_reason    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_reason text := NULLIF(btrim(left(COALESCE(p_reason, ''), 500)), '');
  v_result jsonb;
  v_job    job_requests;
  v_base   worker_profiles;
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_kind = 'phone' THEN
    SELECT jsonb_build_object('phone', p.phone, 'full_name', p.full_name)
      INTO v_result
    FROM profiles p WHERE p.id = p_target_id;
    IF v_result IS NULL THEN
      RAISE EXCEPTION 'Pessoa não encontrada.';
    END IF;
    PERFORM public.admin_log('reveal_phone', p_target_id,
      jsonb_strip_nulls(jsonb_build_object('reason', v_reason)));
    RETURN v_result;
  ELSIF p_kind = 'address' THEN
    SELECT * INTO v_job FROM job_requests WHERE id = p_target_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Pedido não encontrado.';
    END IF;
    SELECT wp.* INTO v_base FROM worker_profiles wp
    WHERE wp.profile_id = public.job_accepted_worker_id(p_target_id);
    PERFORM public.admin_log('reveal_address', p_target_id,
      jsonb_strip_nulls(jsonb_build_object('reason', v_reason)));
    RETURN jsonb_build_object(
      'address_text', v_job.address_text,
      'location_area', v_job.location_area,
      'lat', v_job.location_lat,
      'lng', v_job.location_lng,
      'worker_base_lat', v_base.base_lat,
      'worker_base_lng', v_base.base_lng,
      'worker_location_name', v_base.location_name,
      'distance_km', CASE
        WHEN v_job.location_lat IS NOT NULL AND v_base.base_lat IS NOT NULL THEN
          round((6371 * 2 * asin(sqrt(
            power(sin(radians((v_base.base_lat - v_job.location_lat)::float8) / 2), 2)
            + cos(radians(v_job.location_lat::float8)) * cos(radians(v_base.base_lat::float8))
              * power(sin(radians((v_base.base_lng - v_job.location_lng)::float8) / 2), 2)
          )))::numeric, 1)
      END);
  END IF;

  RAISE EXCEPTION 'Tipo inválido.';
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_reveal_contact(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reveal_contact(uuid, text, text) TO authenticated, service_role;


-- ── 12. Jardineiros: telefone mascarado e consulta registada ───
-- Copiadas da 0060 com três mudanças: phone sai mascarado (o número
-- inteiro só por admin_reveal_contact), a ficha devolve has_phone e
-- abrir a ficha regista view_worker (por isso passa a VOLATILE). A forma
-- do RETURNS TABLE de admin_list_workers não muda.

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
  SELECT f.id, f.full_name, public.admin_mask_phone(f.phone), f.avatar_url, f.location_name,
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



DROP FUNCTION IF EXISTS public.admin_get_worker(uuid);
CREATE FUNCTION public.admin_get_worker(p_worker_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
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

  PERFORM public.admin_log('view_worker', p_worker_id, '{}'::jsonb);

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
    'phone',           public.admin_mask_phone(p.phone),
    'has_phone',       btrim(COALESCE(p.phone, '')) <> '',
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
