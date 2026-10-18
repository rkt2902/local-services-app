-- ══════════════════════════════════════════════════════════════
-- 0048 — Correções aos fluxos do jardineiro e dos ajudantes
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0047.
-- Pode correr-se mais do que uma vez sem erro. A app nova precisa dela
-- para: candidatar-se de novo, retirar candidatura pendente, contacto
-- dos ajudantes no lobby e estado do trabalho na aba Trabalhos. A app
-- antiga continua a funcionar com ela aplicada (só ganha colunas novas e
-- notificações que já sabe abrir ou ignora).
--
-- Vem da revisão dos fluxos de 18/10 (ver decisions_log.md):
--   1. Candidatar-se por RPC (apply_to_help_request): quem foi recusado
--      ou desistiu pode voltar a candidatar-se (antes o UNIQUE e a
--      descoberta impediam, e a notificação "Vaga disponível novamente"
--      não levava a lado nenhum). Avisa o jardineiro responsável.
--   2. Descoberta de pedidos de ajuda só esconde candidaturas ativas.
--   3. Só se aceitam candidaturas com o trabalho ainda por fazer.
--   4. withdraw_help_acceptance: retira candidatura pendente (sem avisos)
--      e só deixa desistir de uma aceite com o trabalho por fazer.
--   5. Quando o trabalho é dado como feito, fecham-se os pedidos de ajuda
--      abertos e as candidaturas pendentes, com aviso a quem esperava.
--   6. Propostas pendentes de um pedido cancelado ou expirado passam a
--      ser avisadas (antes desapareciam sem aviso).
--   7. Um só pedido de ajuda à espera de cada vez por trabalho.
--   8. O cliente é avisado quando há um pedido de ajudantes para aprovar.
--   9. get_candidates_for_help_request devolve o telefone só dos
--      ajudantes já aceites (contacto por WhatsApp no lobby).
--  10. get_worker_job_board devolve job_status e um separador "closed"
--      (propostas não escolhidas, retiradas, trabalhos cancelados).
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ── 1. apply_to_help_request ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.apply_to_help_request(
  p_help_request_id   uuid,
  p_brought_equipment boolean,
  p_message           text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_id           uuid;
  v_principal_id uuid;
  v_name         text;
  v_message      text := NULLIF(btrim(p_message), '');
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM profiles WHERE id = v_uid AND role = 'worker'
  ) THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT help_request_open_for_candidate(p_help_request_id) THEN
    RAISE EXCEPTION 'Este pedido de ajuda já não está aberto.';
  END IF;

  IF v_message IS NOT NULL AND length(v_message) > 500 THEN
    RAISE EXCEPTION 'A mensagem pode ter no máximo 500 caracteres.';
  END IF;

  INSERT INTO help_acceptances (
    help_request_id, worker_id, status, agreed_rate, brought_equipment, message
  ) VALUES (
    p_help_request_id, v_uid, 'pending', 0, COALESCE(p_brought_equipment, false), v_message
  )
  ON CONFLICT (help_request_id, worker_id) DO UPDATE
    SET status            = 'pending',
        agreed_rate       = 0,
        brought_equipment = EXCLUDED.brought_equipment,
        message           = EXCLUDED.message,
        created_at        = now()
    WHERE help_acceptances.status IN ('rejected', 'cancelled')
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Já te candidataste a este pedido de ajuda.';
  END IF;

  SELECT jp.worker_id INTO v_principal_id
  FROM   help_requests hr
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  WHERE  hr.id = p_help_request_id;

  SELECT full_name INTO v_name FROM profiles WHERE id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_principal_id, 'help_candidate_applied', 'Novo candidato a ajudante',
    COALESCE(NULLIF(btrim(v_name), ''), 'Um jardineiro')
      || ' candidatou-se para te ajudar. Vê a equipa para aceitar ou recusar.',
    p_help_request_id, 'help_request');

  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.apply_to_help_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.apply_to_help_request(uuid, boolean, text) TO authenticated, service_role;


-- ── 2. Descoberta: só esconde candidaturas ativas ───────────────
-- Mesma definição da 0044, só muda o NOT EXISTS (status pendente ou
-- aceite). RETURNS TABLE igual, por isso CREATE OR REPLACE chega.

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  proposal_id               uuid,
  slots_needed              integer,
  status                    text,
  equipment_required        boolean,
  created_post_confirmation boolean,
  created_at                timestamptz,
  location_lat              double precision,
  location_lng              double precision,
  service_type_id           uuid,
  principal_name            text,
  principal_avatar_url      text,
  payment_per_helper        numeric,
  confirmed_date            date,
  confirmed_time            time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT id, job_id, proposal_id, slots_needed, status, equipment_required,
         created_post_confirmation, created_at,
         round(location_lat::numeric, 2)::double precision,
         round(location_lng::numeric, 2)::double precision,
         service_type_id, principal_name, principal_avatar_url,
         payment_per_helper, confirmed_date, confirmed_time
  FROM (
    SELECT
      hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
      hr.equipment_required, hr.created_post_confirmation, hr.created_at,
      jr.location_lat::double precision AS location_lat,
      jr.location_lng::double precision AS location_lng,
      jr.service_type_id, p.full_name AS principal_name,
      p.avatar_url AS principal_avatar_url,
      CASE WHEN hr.equipment_required THEN jp.hourly_rate
           ELSE jp.hourly_rate * 0.7
      END AS payment_per_helper,
      jr.confirmed_date, jr.confirmed_time,
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))) AS distance_km,
      LEAST(GREATEST(radius_km, 1), 50)::double precision AS r
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    WHERE  hr.status = 'open'
      AND  jr.status = 'confirmed'
      AND  jr.location_lat BETWEEN worker_lat - 50 / 111.0 AND worker_lat + 50 / 111.0
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id
          AND ha.worker_id = auth.uid()
          AND ha.status IN ('pending', 'accepted')
      )
  ) t
  WHERE t.distance_km <= t.r
  ORDER BY t.distance_km ASC;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) TO authenticated, service_role;


-- ── 3. Candidaturas só com o trabalho por fazer ─────────────────

CREATE OR REPLACE FUNCTION public.help_request_open_for_candidate(
  p_help_request_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    JOIN   job_requests  jr ON jr.id = hr.job_id
    WHERE  hr.id        = p_help_request_id
      AND  hr.status    = 'open'
      AND  jr.status    = 'confirmed'
      AND  jp.worker_id <> auth.uid()
      AND  jr.client_id <> auth.uid()
  );
$function$;


-- ── 4. withdraw_help_acceptance ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.withdraw_help_acceptance(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id           uuid;
  v_help_request_id     uuid;
  v_help_request_status text;
  v_principal_worker_id uuid;
  v_current_status      text;
  v_job_status          text;
  v_name                text;
BEGIN
  SELECT ha.worker_id, ha.help_request_id, ha.status,
         hr.status, jp.worker_id, jr.status
  INTO   v_worker_id, v_help_request_id, v_current_status,
         v_help_request_status, v_principal_worker_id, v_job_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  JOIN   job_requests     jr ON jr.id = hr.job_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Só podes retirar a tua própria candidatura.';
  END IF;

  -- Candidatura ainda por decidir: retira-se sem mais nada.
  IF v_current_status = 'pending' THEN
    UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;
    RETURN;
  END IF;

  IF v_current_status <> 'accepted' THEN
    RAISE EXCEPTION 'Esta candidatura já não está ativa.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Não é possível desistir: o trabalho já não está por fazer.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  IF v_help_request_status = 'filled' THEN
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga de ajudante a que te candidataste voltou a abrir. Podes candidatar-te outra vez.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  SELECT full_name INTO v_name FROM profiles WHERE id = v_worker_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_principal_worker_id, 'help_withdrew', 'Ajudante desistiu',
    COALESCE(NULLIF(btrim(v_name), ''), 'Um ajudante')
      || ' desistiu de te ajudar. A vaga voltou a abrir.',
    v_help_request_id, 'help_request');
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.withdraw_help_acceptance(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.withdraw_help_acceptance(uuid) TO authenticated, service_role;


-- ── 5. Trabalho feito: fecha pedidos de ajuda e candidaturas ────
-- Trigger em vez de mexer em mark_job_done/confirm/auto-confirm: cobre
-- todos os caminhos para awaiting_confirmation/completed.

CREATE OR REPLACE FUNCTION public.close_help_on_job_done()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('awaiting_confirmation', 'completed')
     AND OLD.status IS DISTINCT FROM NEW.status THEN

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O trabalho a que te candidataste já foi feito sem precisar de mais ajudantes.',
           NEW.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id = NEW.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  status = 'pending'
      AND  help_request_id IN (SELECT id FROM help_requests WHERE job_id = NEW.id);

    UPDATE help_requests
    SET    status = 'cancelled'
    WHERE  job_id = NEW.id AND status IN ('pending_approval', 'open');
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.close_help_on_job_done() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_close_help_on_job_done ON job_requests;
CREATE TRIGGER trg_close_help_on_job_done
  AFTER UPDATE OF status ON job_requests
  FOR EACH ROW EXECUTE FUNCTION public.close_help_on_job_done();


-- ── 6. Aviso às propostas pendentes de um pedido fechado ────────
-- cancel_job e auto_expire_jobs (5.2) põem o pedido em cancelled /
-- no_response ANTES de rejeitar as propostas, por isso o estado do pedido
-- já está certo quando este trigger corre. accept_proposal rejeita as
-- outras com o pedido em confirmed e já envia o seu próprio aviso, por
-- isso fica de fora.

CREATE OR REPLACE FUNCTION public.notify_proposal_closed_with_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_status text;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
    SELECT status INTO v_job_status FROM job_requests WHERE id = NEW.job_id;

    IF v_job_status = 'cancelled' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido cancelado',
        'O cliente cancelou o pedido a que fizeste uma proposta.',
        NEW.job_id, 'job_request');
    ELSIF v_job_status = 'no_response' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido expirado',
        'A data do pedido a que fizeste uma proposta passou sem o cliente escolher.',
        NEW.job_id, 'job_request');
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notify_proposal_closed_with_job() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_proposal_closed_with_job ON job_proposals;
CREATE TRIGGER trg_notify_proposal_closed_with_job
  AFTER UPDATE OF status ON job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.notify_proposal_closed_with_job();


-- ── 7 e 8. Pedido de ajuda novo: um de cada vez e aviso ao cliente ─

CREATE OR REPLACE FUNCTION public.help_request_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM help_requests
    WHERE  job_id = NEW.job_id AND status IN ('pending_approval', 'open')
  ) THEN
    RAISE EXCEPTION 'Já tens um pedido de ajudantes ativo para este trabalho.';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.help_request_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_help_request_before_insert ON help_requests;
CREATE TRIGGER trg_help_request_before_insert
  BEFORE INSERT ON help_requests
  FOR EACH ROW EXECUTE FUNCTION public.help_request_before_insert();

CREATE OR REPLACE FUNCTION public.notify_client_help_request_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  IF NEW.status = 'pending_approval' THEN
    SELECT client_id INTO v_client_id FROM job_requests WHERE id = NEW.job_id;
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_client_id, 'help_request_pending_approval', 'Pedido de ajudantes',
      'O jardineiro quer levar ' || NEW.slots_needed
        || CASE WHEN NEW.slots_needed = 1 THEN ' ajudante' ELSE ' ajudantes' END
        || ' para o teu trabalho. Abre o pedido para aprovar.',
      NEW.job_id, 'job_request');
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notify_client_help_request_pending() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_client_help_request_pending ON help_requests;
CREATE TRIGGER trg_notify_client_help_request_pending
  AFTER INSERT ON help_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_client_help_request_pending();


-- ── 9. Candidatos com telefone dos ajudantes aceites ────────────
-- RETURNS TABLE muda de forma: DROP explícito antes de recriar.

DROP FUNCTION IF EXISTS public.get_candidates_for_help_request(uuid);

CREATE FUNCTION public.get_candidates_for_help_request(p_help_request_id uuid)
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  worker_id         uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  worker_name       text,
  worker_avatar_url text,
  message           text,
  worker_phone      text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.worker_id, ha.status, ha.agreed_rate,
    ha.brought_equipment, ha.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url,
    ha.message,
    CASE WHEN ha.status = 'accepted' THEN p.phone END AS worker_phone
  FROM   help_acceptances ha
  JOIN   profiles         p ON p.id = ha.worker_id
  WHERE  ha.help_request_id = p_help_request_id
    AND  is_principal_worker_for_help_request(p_help_request_id)
  ORDER BY ha.created_at ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_candidates_for_help_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_candidates_for_help_request(uuid) TO authenticated, service_role;


-- ── 10. get_worker_job_board: job_status e separador "closed" ───
-- RETURNS TABLE muda de forma: DROP explícito antes de recriar.

DROP FUNCTION IF EXISTS public.get_worker_job_board(text, integer, integer);

CREATE FUNCTION public.get_worker_job_board(
  p_tab       text,
  p_page      integer DEFAULT 0,
  p_page_size integer DEFAULT 20
)
RETURNS TABLE(
  entry_id             uuid,
  role                 text,
  job_id               uuid,
  service_type_name    text,
  person_name          text,
  address_text         text,
  preferred_date       date,
  confirmed_date       date,
  confirmed_time       time,
  confirmed_flexible   boolean,
  hourly_rate          numeric,
  estimated_hours_min  numeric,
  estimated_hours_max  numeric,
  agreed_rate          numeric,
  status               text,
  created_at           timestamptz,
  job_status           text,
  total_count          bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH combined AS (
    -- Fonte A: papel de responsável (job_proposals)
    SELECT
      jp.id                    AS entry_id,
      'responsible'::text      AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      cp.full_name             AS person_name,
      CASE WHEN jp.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      jr.preferred_date        AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      jp.hourly_rate           AS hourly_rate,
      jp.estimated_hours_min   AS estimated_hours_min,
      jp.estimated_hours_max   AS estimated_hours_max,
      NULL::numeric            AS agreed_rate,
      jp.status                AS status,
      jp.created_at            AS created_at,
      jr.status                AS job_status,
      GREATEST(jr.updated_at, jp.updated_at) AS job_updated_at,
      CASE
        WHEN jp.status = 'pending' AND jr.status = 'open' THEN 'pending'
        WHEN jp.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN jp.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'closed'
      END AS bucket
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    JOIN   service_types st ON st.id = jr.service_type_id
    JOIN   profiles      cp ON cp.id = jr.client_id
    WHERE  jp.worker_id = auth.uid()

    UNION ALL

    -- Fonte B: papel de ajudante (help_acceptances)
    SELECT
      ha.id                    AS entry_id,
      'helper'::text           AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      pp.full_name             AS person_name,
      CASE WHEN ha.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      NULL::date               AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      NULL::numeric            AS hourly_rate,
      NULL::numeric            AS estimated_hours_min,
      NULL::numeric            AS estimated_hours_max,
      ha.agreed_rate           AS agreed_rate,
      ha.status                AS status,
      ha.created_at            AS created_at,
      jr.status                AS job_status,
      jr.updated_at            AS job_updated_at,
      CASE
        WHEN ha.status = 'pending' THEN 'pending'
        WHEN ha.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN ha.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'closed'
      END AS bucket
    FROM   help_acceptances ha
    JOIN   help_requests hr  ON hr.id = ha.help_request_id
    JOIN   job_requests  jr  ON jr.id = hr.job_id
    JOIN   service_types st  ON st.id = jr.service_type_id
    JOIN   job_proposals jpp ON jpp.id = hr.proposal_id
    JOIN   profiles      pp  ON pp.id  = jpp.worker_id
    WHERE  ha.worker_id = auth.uid()
  )
  SELECT
    entry_id, role, job_id, service_type_name, person_name, address_text,
    preferred_date, confirmed_date, confirmed_time, confirmed_flexible,
    hourly_rate, estimated_hours_min, estimated_hours_max, agreed_rate,
    status, created_at, job_status,
    COUNT(*) OVER ()::bigint AS total_count
  FROM combined
  WHERE bucket = p_tab
  ORDER BY
    CASE WHEN p_tab = 'scheduled' THEN confirmed_date END ASC NULLS LAST,
    CASE WHEN p_tab = 'scheduled' THEN confirmed_time END ASC NULLS LAST,
    CASE WHEN p_tab IN ('completed', 'closed') THEN job_updated_at END DESC NULLS LAST,
    CASE WHEN p_tab = 'pending'   THEN created_at     END DESC NULLS LAST,
    entry_id
  LIMIT p_page_size OFFSET (p_page * p_page_size);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) TO authenticated, service_role;


NOTIFY pgrst, 'reload schema';
