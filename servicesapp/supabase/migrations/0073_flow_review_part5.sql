-- ══════════════════════════════════════════════════════════════
-- 0073 · Revisão dos fluxos, parte 5
-- NOVA, NÃO APLICADA. Aplicar depois da 0072.
-- ══════════════════════════════════════════════════════════════
-- 1. Pedido direto: a reserva de 24h já não acaba quando o jardineiro
--    escolhido respondeu com uma proposta (a cliente ouvia "não respondeu
--    a tempo"). O fecho do pedido parado (5.1b) recusa as propostas
--    pendentes, e accept_proposal só aceita num pedido aberto (antes
--    passava um pedido fechado a confirmado).
-- 2. Trabalho "a combinar" já iniciado: o lembrete "Marca como
--    concluído" e a expiração passam a contar a partir do dia em que
--    começou (job_expected_end_date já o faz desde a 0071). Antes ficava
--    em curso para sempre. O "a combinar" nunca iniciado fica como está.
-- Só CREATE OR REPLACE com a mesma assinatura: as permissões mantêm-se.
-- ══════════════════════════════════════════════════════════════

-- ── 1. Pedido direto ───────────────────────────────────────────
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
      -- 0073: o jardineiro escolhido já respondeu com uma proposta; a
      -- reserva cumpriu-se. Se ele a retirar ou a cliente a recusar, o
      -- trigger da 0057 (job_proposal_direct_after_update) trata do resto.
      AND  NOT EXISTS (
             SELECT 1 FROM job_proposals jp
             WHERE  jp.job_id    = job_requests.id
               AND  jp.worker_id = job_requests.direct_worker_id
               AND  jp.status    = 'pending')
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM end_direct_reservation(v_job_id, 'expired');
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_proposal(p_proposal_id uuid, p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id          uuid;
  v_scheduled_date     date;
  v_scheduled_time     time;
  v_scheduled_flexible boolean;
  v_people_needed      int;
  v_equipment_required boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM job_requests
    WHERE  id = p_job_id AND client_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode aceitar propostas.';
  END IF;

  -- 0073: só num pedido aberto. Antes, uma proposta esquecida num pedido
  -- fechado (no_response) passava o pedido a confirmado.
  PERFORM 1 FROM job_requests WHERE id = p_job_id AND status = 'open' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Este pedido já não está aberto.';
  END IF;

  SELECT worker_id, scheduled_date, scheduled_time, scheduled_flexible,
         people_needed, helpers_equipment_required
  INTO   v_worker_id, v_scheduled_date, v_scheduled_time, v_scheduled_flexible,
         v_people_needed, v_equipment_required
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'accepted', updated_at = now()
  WHERE id = p_proposal_id;

  WITH rejected AS (
    UPDATE job_proposals
    SET status = 'rejected', updated_at = now()
    WHERE job_id = p_job_id
      AND id    <> p_proposal_id
      AND status = 'pending'
    RETURNING worker_id
  )
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    worker_id,
    'proposal_rejected',
    'Proposta não selecionada',
    'O cliente escolheu outra proposta.',
    p_job_id,
    'job_request'
  FROM rejected;

  UPDATE job_requests
  SET status               = 'confirmed',
      accepted_proposal_id = p_proposal_id,
      confirmed_date       = v_scheduled_date,
      confirmed_time       = v_scheduled_time,
      confirmed_flexible   = COALESCE(v_scheduled_flexible, false),
      proposal_count       = 0,
      updated_at           = now()
  WHERE id = p_job_id;

  IF v_people_needed > 1 THEN
    INSERT INTO help_requests (
      job_id, proposal_id, slots_needed,
      equipment_required, created_post_confirmation, status
    ) VALUES (
      p_job_id, p_proposal_id, v_people_needed - 1,
      COALESCE(v_equipment_required, false), false, 'open'
    );
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id,
    'proposal_accepted',
    'Proposta aceite!',
    'O cliente aceitou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$function$;

-- ── 1 e 2. Expiração ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_expire_jobs()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 5.1 Regra antiga: 48h sem nenhuma proposta.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  expires_at     < now()
      AND  proposal_count = 0
      -- 0069: o pedido direto parado tem a regra 5.1b.
      AND  direct_status IS DISTINCT FROM 'on_hold'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Sem resposta',
      'O teu pedido não recebeu propostas em 48h.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.1b (0069) Pedido direto parado (a cliente desligou "mostrar a outros")
  -- que ficou 48h à espera da decisão dela. Nenhum outro jardineiro o viu,
  -- por isso o texto não fala em "sem propostas".
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  direct_status  = 'on_hold'
      AND  expires_at     < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    -- 0073: como nas outras regras de fecho, nenhuma proposta fica pendente
    -- num pedido fechado (o trigger da 0048 avisa cada jardineiro).
    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido fechado',
      'O pedido ficou parado 48h sem ser mostrado a outros jardineiros e foi fechado. Podes fazer um pedido novo quando quiseres.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.2 Pedido aberto com data fixa que já passou, com ou sem propostas.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  date_mode      = 'fixed'
      AND  preferred_date < today_pt()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    UPDATE job_proposals
    SET    status = 'rejected'
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido expirado',
      'A data do teu pedido passou sem nenhuma proposta aceite. Podes criar um novo pedido.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.3 Trabalho confirmado, 3 dias depois da data, sem ninguém marcar
  -- como concluído: expira.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      -- 0073: "a combinar" já iniciado conta a partir do dia em que começou.
      AND  (confirmed_date IS NOT NULL OR started_at IS NOT NULL)
      -- 0069: a contar do último dia previsto (trabalho em vários dias).
      AND  job_expected_end_date(id) < today_pt() - 3
      -- Remarcação pendente: dá tempo à outra parte para responder, a não
      -- ser que a data proposta também já tenha passado (0069).
      AND  (reschedule_status IS DISTINCT FROM 'pending'
            OR reschedule_proposed_date < today_pt())
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status        = 'cancelled',
           cancel_reason = 'expired',
           updated_at    = now()
    WHERE  id = v_job.id;

    -- Mesma cascata que cancel_job faz à equipa de ajudantes.
    UPDATE help_requests
    SET    status = 'cancelled'
    WHERE  job_id = v_job.id AND status <> 'cancelled';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = v_job.id)
      AND  status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho expirado',
           'O trabalho em que ias ajudar expirou sem ser concluído.',
           v_job.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id = v_job.id AND ha.status = 'accepted';

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_cancelled', 'Trabalho expirado',
      'Passaram 3 dias da data combinada sem o trabalho ser marcado como concluído. O pedido foi fechado.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_cancelled', 'Trabalho expirado',
        'Passaram 3 dias da data combinada sem marcares o trabalho como concluído. O pedido foi fechado.',
        v_job.id, 'job_request');
    END IF;
  END LOOP;

  -- 5.4 Pedido sem data fixa, com propostas, aberto há mais de 14 dias
  -- sem o cliente escolher: fecha. O pedido passa a no_response antes de
  -- rejeitar as propostas, para o trigger da 0048 (secção 11 desta)
  -- avisar cada jardineiro.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  date_mode     <> 'fixed'
      AND  proposal_count > 0
      AND  accepted_proposal_id IS NULL
      AND  created_at     < now() - INTERVAL '14 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido fechado',
      'O teu pedido esteve 14 dias sem escolheres uma proposta e foi fechado. Podes publicá-lo de novo.',
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

-- ── 2. Lembrete "Marca como concluído" ─────────────────────────
CREATE OR REPLACE FUNCTION public.send_job_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today     date := today_pt();
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
  v_when      text;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 7.1 Manhã do dia do trabalho, ao cliente, ao worker e aos ajudantes.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      AND  confirmed_date = v_today
      AND  day_reminder_sent_on IS DISTINCT FROM v_today
    FOR UPDATE SKIP LOCKED
  LOOP
    v_when := CASE
      WHEN v_job.confirmed_flexible OR v_job.confirmed_time IS NULL THEN 'hoje'
      ELSE 'hoje às ' || to_char(v_job.confirmed_time, 'HH24:MI')
    END;

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'O trabalho é hoje',
      'Lembrete: o jardineiro vem ' || v_when || '.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Tens um trabalho hoje',
        'Lembrete: trabalho marcado para ' || v_when || '. Abre a app para ver a morada.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT DISTINCT ha.worker_id, 'job_reminder', 'Vais ajudar num trabalho hoje',
           'Lembrete: trabalho marcado para ' || v_when || '. Abre a app para ver a morada.',
           v_job.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id      = v_job.id
      AND  hr.proposal_id = v_job.accepted_proposal_id
      AND  ha.status      = 'accepted';

    UPDATE job_requests SET day_reminder_sent_on = v_today WHERE id = v_job.id;
  END LOOP;

  -- 7.2 A data passou e ninguém marcou como concluído (uma vez só).
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      -- 0073: "a combinar" já iniciado conta a partir do dia em que começou.
      AND  (confirmed_date IS NOT NULL OR started_at IS NOT NULL)
      -- 0069: a contar do último dia previsto (trabalho em vários dias).
      AND  job_expected_end_date(id) < v_today
      AND  overdue_notified_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Marca o trabalho como concluído',
        'A data do trabalho já passou. Se já o fizeste, marca-o como concluído. Sem isso, o pedido expira 3 dias depois da data.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'O trabalho foi feito?',
      'A data do trabalho já passou e o jardineiro ainda não o marcou como concluído. Fala com ele pelo WhatsApp ou remarca. O pedido expira 3 dias depois da data.',
      v_job.id, 'job_request');

    UPDATE job_requests SET overdue_notified_at = now() WHERE id = v_job.id;
  END LOOP;
END;
$function$;

NOTIFY pgrst, 'reload schema';
