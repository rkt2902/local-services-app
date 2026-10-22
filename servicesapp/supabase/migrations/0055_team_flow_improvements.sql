-- ══════════════════════════════════════════════════════════════
-- 0055 — Ligação entre cliente, jardineiro e ajudantes
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0054
-- (usa job_day_reached, help_request_before_update_job_day e
-- get_accepted_helpers_for_job da 0054). Pode correr-se mais do que uma
-- vez sem erro.
--
-- Melhorias pedidas pelo Henrique a 2026-10-21 (documento "Fluxos e
-- regras de tempo do ProJardim"):
--
-- 1. O cliente vê a equipa: get_accepted_helpers_for_job passa a
--    responder também ao cliente do trabalho (nome e foto). Mesma forma,
--    por isso CREATE OR REPLACE chega.
-- 2. Um ajudante aceite só pode desistir até à véspera. No dia, só o
--    responsável o retira, e a vaga não reabre (o pedido já fechou): a
--    equipa fica com quem resta.
-- 3. Na véspera, a partir das 18h (Portugal), aviso ao responsável quando
--    ainda há vagas ou candidatos por decidir, e ao cliente quando ainda
--    não aprovou os ajudantes. Uma vez por pedido.
-- 5. Os ajudantes aceites recebem "O trabalho começou" quando o
--    responsável inicia o trabalho (tipo novo `help_job_started`).
-- 7. Aprovação automática: um pedido de ajudantes por aprovar há 24h fica
--    aprovado sozinho (se o dia do trabalho ainda não chegou). Avisa o
--    responsável e o cliente (tipo novo `help_request_auto_approved`).
--
-- Tipos novos de notificação: `help_job_started`,
-- `help_request_closing_soon`, `help_request_auto_approved`.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Equipa visível para o cliente ────────────────────────────

CREATE OR REPLACE FUNCTION public.get_accepted_helpers_for_job(p_job_id uuid)
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
  WHERE  jr.id = p_job_id
    AND  (jp.worker_id = auth.uid() OR jr.client_id = auth.uid())
  ORDER BY ha.created_at ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_accepted_helpers_for_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_accepted_helpers_for_job(uuid) TO authenticated, service_role;


-- ── 2a. Desistir só até à véspera ───────────────────────────────
-- Igual à 0048 mais a data, só para quem já foi aceite. Uma candidatura
-- pendente continua a poder ser retirada (no dia já foi fechada pelo
-- cron da 0054).

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
  v_job_id              uuid;
  v_job_status          text;
  v_name                text;
BEGIN
  SELECT ha.worker_id, ha.help_request_id, ha.status,
         hr.status, jp.worker_id, jr.id, jr.status
  INTO   v_worker_id, v_help_request_id, v_current_status,
         v_help_request_status, v_principal_worker_id, v_job_id, v_job_status
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
  IF job_day_reached(v_job_id) THEN
    RAISE EXCEPTION 'No dia do trabalho já não podes desistir. Fala com o jardineiro responsável pelo WhatsApp.';
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


-- ── 2b. Retirar um ajudante no dia: a vaga não reabre ───────────
-- Igual à 0049 até ao dia do trabalho. A partir do dia o pedido já
-- fechou (0054), por isso reabrir a vaga e avisar os recusados não serve
-- de nada: a equipa fica com quem resta (vagas = aceites) ou, sem
-- ninguém, o pedido é cancelado.

CREATE OR REPLACE FUNCTION public.remove_help_helper(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal       uuid;
  v_helper          uuid;
  v_help_request_id uuid;
  v_ha_status       text;
  v_hr_status       text;
  v_job_id          uuid;
  v_job_status      text;
  v_left            integer;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status, hr.status,
         jr.id, jr.status
  INTO   v_principal, v_helper, v_help_request_id, v_ha_status, v_hr_status,
         v_job_id, v_job_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  JOIN   job_requests     jr ON jr.id = hr.job_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha, hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Só o jardineiro responsável pode gerir a equipa.';
  END IF;
  IF v_ha_status <> 'accepted' THEN
    RAISE EXCEPTION 'Este ajudante já não está na equipa.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só podes mudar a equipa com o trabalho por fazer.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  IF job_day_reached(v_job_id) THEN
    IF v_hr_status = 'filled' THEN
      SELECT count(*) INTO v_left
      FROM   help_acceptances
      WHERE  help_request_id = v_help_request_id AND status = 'accepted';

      IF v_left > 0 THEN
        UPDATE help_requests SET slots_needed = v_left WHERE id = v_help_request_id;
      ELSE
        UPDATE help_requests SET status = 'cancelled' WHERE id = v_help_request_id;
      END IF;
    END IF;
  ELSIF v_hr_status = 'filled' THEN
    -- Vaga volta a abrir; quem tinha sido recusado fica a saber (como em
    -- withdraw_help_acceptance).
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga de ajudante a que te candidataste voltou a abrir. Podes candidatar-te outra vez.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_helper, 'help_removed', 'Já não fazes parte da equipa',
    'O jardineiro responsável tirou-te da equipa deste trabalho.',
    v_help_request_id, 'help_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.remove_help_helper(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.remove_help_helper(uuid) TO authenticated, service_role;


-- ── 5. Ajudantes avisados quando o trabalho começa ──────────────
-- Igual à 0049 mais o ramo do início (started_at passa a ter valor, em
-- start_job da 0052). O trigger passa a olhar também para started_at.

CREATE OR REPLACE FUNCTION public.notify_helpers_on_job_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type  text;
  v_title text;
  v_body  text;
BEGIN
  IF NEW.accepted_proposal_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'confirmed' AND OLD.started_at IS NULL
     AND NEW.started_at IS NOT NULL THEN
    v_type  := 'help_job_started';
    v_title := 'O trabalho começou';
    v_body  := 'O jardineiro responsável iniciou o trabalho em que vais ajudar.';
  ELSIF OLD.status = 'confirmed' AND NEW.status = 'confirmed'
     AND (OLD.confirmed_date IS DISTINCT FROM NEW.confirmed_date
          OR OLD.confirmed_time IS DISTINCT FROM NEW.confirmed_time) THEN
    v_type  := 'help_job_rescheduled';
    v_title := 'Data do trabalho mudou';
    v_body  := CASE
      WHEN NEW.confirmed_date IS NULL THEN
        'O trabalho em que vais ajudar mudou de data. Abre a app para ver a nova data.'
      WHEN NEW.confirmed_flexible OR NEW.confirmed_time IS NULL THEN
        'O trabalho em que vais ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM') || '.'
      ELSE
        'O trabalho em que vais ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM')
          || ' às ' || to_char(NEW.confirmed_time, 'HH24:MI') || '.'
    END;
  ELSIF NEW.status = 'awaiting_confirmation' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_done';
    v_title := 'Trabalho marcado como concluído';
    v_body  := 'O jardineiro responsável marcou como concluído o trabalho em que ajudaste.';
  ELSIF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_completed';
    v_title := 'Trabalho concluído';
    v_body  := 'O trabalho em que ajudaste ficou confirmado. Já podes avaliar o jardineiro responsável.';
  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT DISTINCT ha.worker_id, v_type, v_title, v_body, NEW.id, 'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id      = NEW.id
    AND  hr.proposal_id = NEW.accepted_proposal_id
    AND  ha.status      = 'accepted';

  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_helpers_on_job_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_helpers_on_job_change ON job_requests;
CREATE TRIGGER trg_notify_helpers_on_job_change
  AFTER UPDATE OF status, confirmed_date, confirmed_time, started_at ON job_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_helpers_on_job_change();


-- ── 7a. O cliente sabe que o pedido se aprova sozinho ───────────
-- Igual à 0048, com o prazo de 24h no texto.

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
        || ' para o teu trabalho. Abre o pedido para aprovar. Sem resposta, fica aprovado em 24 horas.',
      NEW.job_id, 'job_request');
  END IF;
  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_client_help_request_pending() FROM PUBLIC, anon, authenticated;


-- ── 3 e 7b. Cron: aprovação automática e aviso da véspera ───────

ALTER TABLE public.help_requests
  ADD COLUMN IF NOT EXISTS eve_reminder_sent_at timestamptz;

CREATE OR REPLACE FUNCTION public.process_help_request_deadlines()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hr        RECORD;
  v_accepted  integer;
  v_pending   integer;
  v_free      integer;
BEGIN
  -- 7. Por aprovar há 24h: aprova. O trigger da 0054 avisa a zona.
  -- No dia do trabalho não (o trigger recusaria); o cron da 0054 fecha.
  FOR v_hr IN
    SELECT hr.id, hr.job_id, jp.worker_id AS principal_id, jr.client_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status = 'pending_approval'
      AND  hr.created_at <= now() - INTERVAL '24 hours'
      AND  jr.status = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    UPDATE help_requests SET status = 'open' WHERE id = v_hr.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_hr.principal_id, 'help_request_approved', 'Pedido de equipa aprovado',
      'O cliente não respondeu em 24 horas, por isso o pedido de ajudantes ficou aprovado. Já podes aceitar candidatos.',
      v_hr.id, 'help_request');

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_hr.client_id, 'help_request_auto_approved', 'Ajudantes aprovados',
      'Passaram 24 horas sem resposta, por isso o pedido de ajudantes do jardineiro ficou aprovado.',
      v_hr.job_id, 'job_request');
  END LOOP;

  -- 3. Véspera do trabalho, a partir das 18h em Portugal, uma vez.
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Lisbon') < 18 THEN
    RETURN;
  END IF;

  FOR v_hr IN
    SELECT hr.id, hr.job_id, hr.status, hr.slots_needed,
           jp.worker_id AS principal_id, jr.client_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status IN ('pending_approval', 'open')
      AND  hr.eve_reminder_sent_at IS NULL
      AND  jr.status = 'confirmed'
      AND  jr.confirmed_date = today_pt() + 1
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    IF v_hr.status = 'pending_approval' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.client_id, 'help_request_pending_approval', 'Aprova os ajudantes hoje',
        'O jardineiro pediu ajudantes para o trabalho de amanhã. Se não aprovares hoje, o pedido fecha à meia-noite.',
        v_hr.job_id, 'job_request');
    ELSE
      SELECT count(*) FILTER (WHERE status = 'accepted'),
             count(*) FILTER (WHERE status = 'pending')
      INTO   v_accepted, v_pending
      FROM   help_acceptances
      WHERE  help_request_id = v_hr.id;

      v_free := GREATEST(v_hr.slots_needed - v_accepted, 0);

      IF v_pending > 0 THEN
        INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
        VALUES (v_hr.principal_id, 'help_request_closing_soon', 'O pedido de ajudantes fecha hoje',
          'Tens ' || v_pending
            || CASE WHEN v_pending = 1 THEN ' candidato' ELSE ' candidatos' END
            || ' por decidir. À meia-noite o pedido fecha e quem não aceitares fica de fora.',
          v_hr.id, 'help_request');
      ELSIF v_free > 0 THEN
        INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
        VALUES (v_hr.principal_id, 'help_request_closing_soon', 'O pedido de ajudantes fecha hoje',
          'Ainda tens ' || v_free
            || CASE WHEN v_free = 1 THEN ' vaga' ELSE ' vagas' END
            || ' por preencher. À meia-noite o pedido fecha e o trabalho fica com a equipa que tiveres.',
          v_hr.id, 'help_request');
      END IF;
    END IF;

    UPDATE help_requests SET eve_reminder_sent_at = now() WHERE id = v_hr.id;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_help_request_deadlines() FROM PUBLIC, anon, authenticated;

-- De hora a hora (upsert pelo nome), desfasado dos outros crons.
SELECT cron.schedule(
  'process-help-request-deadlines',
  '10 * * * *',
  'SELECT process_help_request_deadlines()'
);


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select jobname, schedule, active from cron.job
--  where jobname = 'process-help-request-deadlines';
-- select column_name from information_schema.columns
--  where table_name = 'help_requests' and column_name = 'eve_reminder_sent_at';
-- select tgname, pg_get_triggerdef(oid) from pg_trigger
--  where tgname = 'trg_notify_helpers_on_job_change';
