-- ══════════════════════════════════════════════════════════════
-- 0054 — Pedidos de ajuda fecham no dia do trabalho, avisos de
--        trabalhos e ajudas novas, foto dos ajudantes da equipa
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0053
-- (usa today_pt() da 0046, help_request_open_for_candidate e
-- get_help_requests_in_radius da 0048). Pode correr-se mais do que uma
-- vez sem erro.
--
-- Pedido do Henrique a 2026-10-21:
--
-- 1. No dia do trabalho o pedido de ajuda tem de desaparecer. A partir da
--    data confirmada (dia em Portugal, today_pt()):
--    - deixa de aparecer na descoberta de ajudas e já não aceita
--      candidaturas (efeito imediato, sem esperar pelo cron);
--    - o jardineiro responsável já não pode pedir ajudantes, o cliente já
--      não pode aprovar um pedido pendente e o responsável já não pode
--      aceitar candidatos;
--    - de hora a hora, o cron fecha os pedidos que ficaram abertos:
--      candidaturas pendentes recusadas e avisadas; se já há ajudantes
--      aceites, a equipa fica com esses (filled, vagas = aceites); se não
--      há, o pedido é cancelado. O responsável é avisado.
--    Trabalhos sem data confirmada (confirmed_date null) não mudam.
--
-- 2. Avisos de trabalho novo e de pedido de ajuda novo a quem faz o
--    serviço: só jardineiros dentro do raio que oferecem esse serviço (ou
--    que ainda não escolheram serviços). O pedido de ajuda avisa quando
--    abre (criado já aberto ao aceitar a proposta, ou aprovado pelo
--    cliente). Tipo novo: `new_help_request_in_radius`. O contexto
--    " (Serviço, DD/MM)" continua a ser acrescentado pelo trigger da 0049.
--
-- 3. get_accepted_helpers_for_job devolve também a foto (avatar_url) para
--    o cartão "Equipa" do responsável. RETURNS TABLE muda de forma: DROP
--    explícito antes de recriar.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ── 1. O dia do trabalho já chegou? ─────────────────────────────

CREATE OR REPLACE FUNCTION public.job_day_reached(p_job_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT confirmed_date <= today_pt() FROM job_requests WHERE id = p_job_id),
    false
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.job_day_reached(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.job_day_reached(uuid) TO authenticated, service_role;


-- ── 2. Candidaturas só antes do dia ─────────────────────────────
-- Mesma definição da 0048 mais a data. Usada por apply_to_help_request e
-- pela policy de INSERT em help_acceptances.

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
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
      AND  jp.worker_id <> auth.uid()
      AND  jr.client_id <> auth.uid()
  );
$function$;


-- ── 3. Descoberta: esconde os pedidos de ajuda a partir do dia ──
-- Mesma definição da 0048 mais a data. RETURNS TABLE igual, por isso
-- CREATE OR REPLACE chega.

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
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
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


-- ── 4. Pedir ajudantes só antes do dia ──────────────────────────
-- Mesma regra da 0048 (um pedido ativo por trabalho) mais a data, só
-- para os pedidos que a app cria (pending_approval). Os que nascem já
-- abertos em accept_proposal não podem fazer falhar a aceitação da
-- proposta: ficam escondidos pela descoberta e o cron fecha-os.

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

  IF NEW.status = 'pending_approval' AND job_day_reached(NEW.job_id) THEN
    RAISE EXCEPTION 'Os ajudantes têm de ser pedidos até à véspera do trabalho.';
  END IF;

  RETURN NEW;
END;
$function$;


-- ── 5. Aprovar o pedido e aceitar candidatos só antes do dia ────
-- Triggers em vez de reescrever approve_help_request e
-- accept_help_candidate: cobrem as duas RPCs e qualquer caminho futuro.
-- Só bloqueiam a aprovação (pending_approval → open) e a aceitação
-- (pending → accepted); fechar, recusar e cancelar continuam possíveis.

CREATE OR REPLACE FUNCTION public.help_request_before_update_job_day()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'pending_approval' AND NEW.status = 'open'
     AND job_day_reached(NEW.job_id) THEN
    RAISE EXCEPTION 'O trabalho já é hoje: o pedido de ajudantes fechou.';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.help_request_before_update_job_day() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_help_request_before_update_job_day ON help_requests;
CREATE TRIGGER trg_help_request_before_update_job_day
  BEFORE UPDATE OF status ON help_requests
  FOR EACH ROW EXECUTE FUNCTION public.help_request_before_update_job_day();

CREATE OR REPLACE FUNCTION public.help_acceptance_before_update_job_day()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_id uuid;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    SELECT job_id INTO v_job_id FROM help_requests WHERE id = NEW.help_request_id;
    IF job_day_reached(v_job_id) THEN
      RAISE EXCEPTION 'O trabalho já é hoje: o pedido de ajudantes fechou.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.help_acceptance_before_update_job_day() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_help_acceptance_before_update_job_day ON help_acceptances;
CREATE TRIGGER trg_help_acceptance_before_update_job_day
  BEFORE UPDATE OF status ON help_acceptances
  FOR EACH ROW EXECUTE FUNCTION public.help_acceptance_before_update_job_day();


-- ── 6. Cron: fechar os pedidos de ajuda no dia do trabalho ──────

CREATE OR REPLACE FUNCTION public.close_help_requests_on_job_day()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hr        RECORD;
  v_accepted  integer;
BEGIN
  FOR v_hr IN
    SELECT hr.id, hr.status, jp.worker_id AS principal_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status IN ('pending_approval', 'open')
      AND  jr.status = 'confirmed'
      AND  jr.confirmed_date IS NOT NULL
      AND  jr.confirmed_date <= today_pt()
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O dia do trabalho chegou e o pedido de ajuda fechou sem a tua candidatura ser aceite.',
           v_hr.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_hr.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = v_hr.id AND status = 'pending';

    SELECT count(*) INTO v_accepted
    FROM   help_acceptances
    WHERE  help_request_id = v_hr.id AND status = 'accepted';

    IF v_accepted > 0 THEN
      UPDATE help_requests
      SET    status = 'filled', slots_needed = v_accepted
      WHERE  id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        'O trabalho é hoje, por isso o pedido de ajudantes fechou. A tua equipa fica com '
          || v_accepted
          || CASE WHEN v_accepted = 1 THEN ' ajudante.' ELSE ' ajudantes.' END,
        v_hr.id, 'help_request');
    ELSE
      UPDATE help_requests SET status = 'cancelled' WHERE id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        CASE WHEN v_hr.status = 'pending_approval'
          THEN 'O trabalho é hoje e o cliente não chegou a aprovar os ajudantes. O pedido fechou.'
          ELSE 'O trabalho é hoje e ninguém foi aceite como ajudante. O pedido fechou.'
        END,
        v_hr.id, 'help_request');
    END IF;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.close_help_requests_on_job_day() FROM PUBLIC, anon, authenticated;

-- De hora a hora, pouco depois da meia-noite em Portugal o primeiro.
-- A descoberta e as candidaturas já fecham à meia-noite sem esperar.
SELECT cron.schedule(
  'close-help-requests-on-job-day',
  '5 * * * *',
  'SELECT close_help_requests_on_job_day()'
);


-- ── 7. Aviso de trabalho novo só a quem faz o serviço ───────────
-- Mesma função do baseline (o trigger chama-se on_job_created na BD viva
-- e trigger_notify_workers_new_job no ficheiro; os dois apontam para esta
-- função, por isso basta redefini-la). Agora:
--   - só jardineiros que oferecem o serviço, ou que ainda não escolheram
--     nenhum (para não ficarem sem avisos);
--   - nunca o próprio cliente;
--   - texto na mesma voz da app ("ti", não "si").

CREATE OR REPLACE FUNCTION public.notify_workers_new_job()
RETURNS trigger
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
    NEW.id,
    'job_request'
  FROM worker_profiles wp
  WHERE wp.profile_id <> NEW.client_id
    AND NOT (wp.profile_id = ANY(COALESCE(NEW.excluded_worker_ids, '{}'::uuid[])))
    AND (
      EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
          AND  wst.service_type_id = NEW.service_type_id
      )
      OR NOT EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
      )
    )
    AND (
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((NEW.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
        + cos(radians(wp.base_lat::double precision))
          * cos(radians(NEW.location_lat::double precision))
          * power(sin(radians((NEW.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
      )))
    ) <= wp.radius_km;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_new_job() FROM PUBLIC, anon, authenticated;


-- ── 8. Aviso de pedido de ajuda novo ────────────────────────────
-- Quando um pedido de ajuda abre: criado já aberto (accept_proposal com
-- mais de uma pessoa) ou aprovado pelo cliente (pending_approval → open).
-- Reaberturas (filled → open, quando um ajudante sai) já avisam os
-- candidatos anteriores e não voltam a avisar toda a zona.

CREATE OR REPLACE FUNCTION public.notify_workers_new_help_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests;
  v_principal uuid;
BEGIN
  IF NEW.status <> 'open' THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM 'pending_approval' THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = NEW.job_id;
  IF v_job.id IS NULL OR v_job.status <> 'confirmed'
     OR (v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date <= today_pt()) THEN
    RETURN NULL;
  END IF;

  SELECT worker_id INTO v_principal FROM job_proposals WHERE id = NEW.proposal_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    wp.profile_id,
    'new_help_request_in_radius',
    'Pedido de ajuda perto de ti',
    'Um jardineiro procura '
      || NEW.slots_needed
      || CASE WHEN NEW.slots_needed = 1 THEN ' ajudante' ELSE ' ajudantes' END
      || ' na tua zona. Vê o valor e candidata-te.',
    NEW.id,
    'help_request'
  FROM worker_profiles wp
  WHERE wp.profile_id <> v_principal
    AND wp.profile_id <> v_job.client_id
    AND (
      EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
          AND  wst.service_type_id = v_job.service_type_id
      )
      OR NOT EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
      )
    )
    AND NOT EXISTS (
      SELECT 1 FROM help_acceptances ha
      WHERE  ha.help_request_id = NEW.id
        AND  ha.worker_id = wp.profile_id
        AND  ha.status IN ('pending', 'accepted')
    )
    AND (
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((v_job.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
        + cos(radians(wp.base_lat::double precision))
          * cos(radians(v_job.location_lat::double precision))
          * power(sin(radians((v_job.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
      )))
    ) <= wp.radius_km;

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_workers_new_help_request() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_workers_new_help_request ON help_requests;
CREATE TRIGGER trg_notify_workers_new_help_request
  AFTER INSERT OR UPDATE OF status ON help_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_workers_new_help_request();


-- ── 9. Equipa do responsável com foto ───────────────────────────
-- RETURNS TABLE muda de forma (avatar_url novo): DROP explícito.

DROP FUNCTION IF EXISTS public.get_accepted_helpers_for_job(uuid);

CREATE FUNCTION public.get_accepted_helpers_for_job(p_job_id uuid)
RETURNS TABLE(worker_id uuid, full_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT ha.worker_id, p.full_name, p.avatar_url
  FROM   job_requests     jr
  JOIN   job_proposals    jp ON jp.id  = jr.accepted_proposal_id
  JOIN   help_requests    hr ON hr.proposal_id = jp.id
  JOIN   help_acceptances ha ON ha.help_request_id = hr.id AND ha.status = 'accepted'
  JOIN   profiles          p ON p.id  = ha.worker_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid();
$function$;

REVOKE EXECUTE ON FUNCTION public.get_accepted_helpers_for_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_accepted_helpers_for_job(uuid) TO authenticated, service_role;


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select jobname, schedule, active from cron.job
--  where jobname = 'close-help-requests-on-job-day';
-- select tgname from pg_trigger
--  where tgname in ('trg_notify_workers_new_help_request',
--                   'trg_help_request_before_update_job_day',
--                   'trg_help_acceptance_before_update_job_day');
-- select pg_get_function_result('public.get_accepted_helpers_for_job(uuid)'::regprocedure);
