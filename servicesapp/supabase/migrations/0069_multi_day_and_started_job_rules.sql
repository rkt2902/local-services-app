-- ══════════════════════════════════════════════════════════════
-- 0069 — Trabalho em vários dias, remarcações fora de prazo e
--        trabalho já iniciado (revisão de fluxos, parte 2)
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0068
-- (esta volta a mudar o cancel_job da 0068). Pode correr-se mais do que
-- uma vez.
--
-- 1. `job_expected_end_date(job_id)`: último dia previsto do trabalho, o
--    maior entre o dia marcado + dias estimados - 1 (proposta aceite) e o
--    dia do último "Começar o dia". O `auto_expire_jobs` (regra 5.3) e o
--    lembrete "Marca o trabalho como concluído" (`send_job_reminders`,
--    7.2) passam a contar a partir daqui em vez do `confirmed_date`. Antes
--    um trabalho de 5 a 7 dias era fechado como "expirado" ao 4.º dia, com
--    o jardineiro a trabalhar. Num trabalho de um dia nada muda.
-- 2. Remarcação cuja data já passou: `accept_reschedule` recusa-a (antes o
--    trabalho ficava marcado no passado); `propose_reschedule` deixa
--    propor outra por cima dela; a regra 5.3 deixa de esperar por ela.
-- 3. Trabalho já iniciado (`started_at`): `cancel_job`,
--    `propose_reschedule` e `accept_reschedule` recusam. Antes, com data
--    "a combinar" ou depois de uma remarcação, dava para cancelar a meio.
-- ══════════════════════════════════════════════════════════════

-- ── 1) Último dia previsto do trabalho ─────────────────────────

CREATE OR REPLACE FUNCTION public.job_expected_end_date(p_job_id uuid)
 RETURNS date
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT GREATEST(
    jr.confirmed_date
      + GREATEST(COALESCE(jp.estimated_days_max, jp.estimated_days_min, 1), 1)
      - 1,
    (SELECT max((wd.started_at AT TIME ZONE 'Europe/Lisbon')::date)
     FROM   job_work_days wd
     WHERE  wd.job_id = jr.id)
  )
  FROM   job_requests  jr
  LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id = p_job_id;
$function$;

REVOKE ALL ON FUNCTION public.job_expected_end_date(uuid) FROM PUBLIC, anon, authenticated;

-- ── 1b) auto_expire_jobs (só muda a regra 5.3) ────────────────

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
      AND  confirmed_date IS NOT NULL
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

-- ── 1c) send_job_reminders (só muda a regra 7.2) ──────────────

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
      AND  confirmed_date IS NOT NULL
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

-- ── 2) propose_reschedule ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.propose_reschedule(p_job_id uuid, p_new_date date, p_new_time time without time zone DEFAULT NULL::time without time zone, p_new_flexible boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id       uuid := auth.uid();
  v_today         date := today_pt();
  v_job           public.job_requests;
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.status != 'confirmed' THEN
    RAISE EXCEPTION 'Só jobs confirmados podem ser remarcados';
  END IF;
  -- 0069: trabalho já iniciado.
  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já começou e já não pode ser cancelado nem remarcado.';
  END IF;
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date = v_today THEN
    RAISE EXCEPTION 'Não pode remarcar com menos de 24h de antecedência';
  END IF;
  IF p_new_date IS NULL OR p_new_date - v_today < 1 THEN
    RAISE EXCEPTION 'A nova data tem de ser pelo menos amanhã';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  -- 0069: uma remarcação pendente cuja data já passou pode ser substituída.
  IF v_job.reschedule_status = 'pending'
     AND v_job.reschedule_proposed_date >= v_today THEN
    RAISE EXCEPTION 'Já existe uma remarcação pendente';
  END IF;

  UPDATE public.job_requests
    SET reschedule_proposed_date     = p_new_date,
        reschedule_proposed_time     = p_new_time,
        reschedule_proposed_flexible = p_new_flexible,
        reschedule_proposed_by       = v_user_id,
        reschedule_status            = 'pending',
        updated_at                   = now()
    WHERE id = p_job_id;

  IF v_is_client THEN
    SELECT worker_id INTO v_other_user_id
    FROM   public.job_proposals WHERE id = v_job.accepted_proposal_id;
  ELSE
    v_other_user_id := v_job.client_id;
  END IF;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_other_user_id, 'reschedule_proposed', 'Pedido de remarcação',
    'A outra parte propôs uma nova data para o trabalho.',
    p_job_id, 'job_request');
END;
$function$;

-- ── 2b) accept_reschedule ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.accept_reschedule(p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id   uuid := auth.uid();
  v_job       public.job_requests;
  v_is_client boolean;
  v_is_worker boolean;
  v_proposer_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.reschedule_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Sem remarcação pendente';
  END IF;
  IF v_job.status <> 'confirmed' THEN
    RAISE EXCEPTION 'O trabalho já não está confirmado';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF v_job.reschedule_proposed_by = v_user_id THEN
    RAISE EXCEPTION 'Não pode aceitar a sua própria remarcação';
  END IF;
  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  -- 0069: trabalho já iniciado, ou data proposta que entretanto passou.
  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já começou e já não pode ser cancelado nem remarcado.';
  END IF;
  IF v_job.reschedule_proposed_date < today_pt() THEN
    RAISE EXCEPTION 'A data proposta já passou. Recusa esta remarcação e propõe outra.';
  END IF;

  v_proposer_id := v_job.reschedule_proposed_by;

  UPDATE public.job_requests
    SET confirmed_date           = reschedule_proposed_date,
        confirmed_time           = reschedule_proposed_time,
        confirmed_flexible       = reschedule_proposed_flexible,
        reschedule_proposed_date = null,
        reschedule_proposed_time = null,
        reschedule_proposed_flexible = null,
        reschedule_proposed_by   = null,
        reschedule_status        = 'accepted',
        overdue_notified_at      = null,
        updated_at               = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_accepted', 'Remarcação aceite',
    'A nova data foi aceite.', p_job_id, 'job_request');
END;
$function$;

-- ── 3) cancel_job (mesma assinatura; parte da versão da 0068) ──

CREATE OR REPLACE FUNCTION public.cancel_job(p_job_id uuid, p_reason text, p_reason_detail text DEFAULT NULL::text, p_client_wants_reopen boolean DEFAULT NULL::boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job           job_requests%ROWTYPE;
  v_caller_id     uuid    := auth.uid();
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
  v_can_reopen    boolean := false;
  v_new_excluded  uuid[];
  v_new_job_id    uuid    := NULL;
  v_date_mode     text;
  v_pref_date     date;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed') THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser cancelado no estado atual.';
  END IF;

  v_is_client := (v_job.client_id = v_caller_id);
  v_is_worker := v_job.status = 'confirmed' AND EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  id = v_job.accepted_proposal_id AND worker_id = v_caller_id
  );

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente ou o jardineiro do trabalho podem cancelar.';
  END IF;

  -- 0069: trabalho já iniciado (a regra das 24h não o apanha com data
  -- "a combinar" ou depois de uma remarcação).
  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já começou e já não pode ser cancelado nem remarcado.';
  END IF;

  IF v_job.status = 'confirmed'
     AND v_job.confirmed_date IS NOT NULL
     AND (v_job.confirmed_date - today_pt()) < 1 THEN
    RAISE EXCEPTION 'O cancelamento requer pelo menos 24h de antecedência.';
  END IF;

  IF v_is_worker THEN
    v_other_user_id := v_job.client_id;
  ELSE
    SELECT worker_id INTO v_other_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  END IF;

  IF v_job.status = 'confirmed' THEN
    IF v_is_worker THEN
      IF v_job.reopen_count_worker < 2 THEN
        v_can_reopen := true;
      END IF;
    ELSE
      IF p_client_wants_reopen = true AND v_job.reopen_count_client < 1 THEN
        v_can_reopen := true;
      END IF;
    END IF;
  END IF;

  UPDATE job_requests
  SET status               = 'cancelled',
      cancelled_by         = v_caller_id,
      cancel_reason        = p_reason,
      cancel_reason_detail = p_reason_detail,
      cancelled_worker_id  = CASE WHEN v_is_worker THEN v_caller_id ELSE NULL END,
      updated_at           = now()
  WHERE id = p_job_id;

  UPDATE job_proposals
  SET status = 'rejected', updated_at = now()
  WHERE job_id = p_job_id AND status = 'pending';

  UPDATE help_requests
  SET    status = 'cancelled'
  WHERE  job_id = p_job_id AND status <> 'cancelled';

  UPDATE help_acceptances
  SET    status = 'rejected'
  WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = p_job_id)
    AND  status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado.',
         p_job_id, 'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id = p_job_id AND ha.status = 'accepted';

  IF v_other_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_other_user_id, 'job_cancelled', 'Pedido cancelado',
      'Um pedido foi cancelado.', p_job_id, 'job_request');
  END IF;

  IF v_can_reopen THEN
    v_new_excluded := v_job.excluded_worker_ids;

    -- 0068: data fixa que já passou (o jardineiro propôs outro dia e o
    -- original ficou para trás). Sem isto, auto_expire_jobs passava o
    -- pedido reaberto a no_response na corrida seguinte. Usa o dia que
    -- estava marcado (ainda futuro, o cancelamento exige 24h) ou, sem
    -- ele, passa a data flexível.
    v_date_mode := v_job.date_mode;
    v_pref_date := v_job.preferred_date;
    IF v_date_mode = 'fixed'
       AND (v_pref_date IS NULL OR v_pref_date < today_pt()) THEN
      IF v_job.confirmed_date IS NOT NULL
         AND v_job.confirmed_date >= today_pt() THEN
        v_pref_date := v_job.confirmed_date;
      ELSE
        v_date_mode := 'flexible';
        v_pref_date := NULL;
      END IF;
    END IF;
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id, service_type_id, address_text,
      location_lat, location_lng,
      date_mode, preferred_date, availability_text,
      urgency, size_estimate, description, location_area,
      status, reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id, v_job.service_type_id, v_job.address_text,
      v_job.location_lat, v_job.location_lng,
      v_date_mode, v_pref_date, v_job.availability_text,
      v_job.urgency, v_job.size_estimate, v_job.description, v_job.location_area,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded, now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    -- 0068: as fotos do pedido passam para o reaberto (mesmos ficheiros
    -- no Storage, só as linhas são copiadas).
    INSERT INTO job_photos (job_id, storage_path)
    SELECT v_new_job_id, storage_path
    FROM   job_photos
    WHERE  job_id = p_job_id
    ORDER  BY created_at;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto',
        'O pedido foi reaberto automaticamente.', v_new_job_id, 'job_request');
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$function$;
