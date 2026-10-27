-- ══════════════════════════════════════════════════════════════
-- 0046 — Regras do dia do trabalho: concluir, expirar e lembrar
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0044
-- (redefine get_jobs_in_radius com a assinatura de 3 parâmetros da 0044).
-- Pode ser aplicada várias vezes sem erro.
--
-- Pedido do Henrique a 2026-10-16:
--
-- 1. "Marcar como concluído" só a partir do dia do trabalho, com foto
--    opcional do worker. O cliente continua a confirmar (fluxo que já
--    existia: confirmed → awaiting_confirmation → completed).
--    mark_job_done ganha p_photo_path (opcional) e recusa antes do dia.
--
-- 2. Pedidos abertos com data fixa que já passou deixam de aparecer aos
--    workers (filtro em get_jobs_in_radius, efeito imediato) e passam a
--    `no_response` pelo cron (propostas pendentes ficam `rejected`).
--
-- 3. Trabalho confirmado cuja data passou sem ninguém marcar concluído:
--    no dia seguinte notifica cliente e worker; 3 dias depois da data
--    expira (status `cancelled`, cancel_reason `expired`, sem
--    reabertura) e avisa os dois e os ajudantes aceites.
--
-- 4. Trabalho marcado como concluído e o cliente não confirma: lembrete ao
--    cliente ao fim de 1 dia; ao fim de 3 dias confirma automaticamente
--    (regra que já existia, agora contada a partir de marked_done_at em
--    vez de updated_at).
--
-- 5. Lembrete na manhã do dia do trabalho (07:30 UTC, ou seja 07:30 no
--    inverno e 08:30 no verão em Portugal) ao cliente e ao worker.
--    Tipo de notificação novo: `job_reminder` (também usado nos lembretes
--    dos pontos 3 e 4). Se o push da 0041 estiver configurado, o trigger
--    de notifications envia-o sozinho.
--
-- Datas: "hoje" é sempre a data em Portugal (Europe/Lisbon), via
-- public.today_pt(), para o dia não mudar à meia-noite UTC.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Colunas novas em job_requests ────────────────────────────

ALTER TABLE public.job_requests
  ADD COLUMN IF NOT EXISTS completion_photo_path         text,
  ADD COLUMN IF NOT EXISTS marked_done_at                timestamptz,
  ADD COLUMN IF NOT EXISTS day_reminder_sent_on          date,
  ADD COLUMN IF NOT EXISTS overdue_notified_at           timestamptz,
  ADD COLUMN IF NOT EXISTS confirmation_reminder_sent_at timestamptz;


-- ── 2. Data de hoje em Portugal ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.today_pt()
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date;
$function$;

REVOKE EXECUTE ON FUNCTION public.today_pt() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.today_pt() TO authenticated, service_role;


-- ── 3. mark_job_done: só a partir do dia, com foto opcional ─────
-- A assinatura muda (novo parâmetro), por isso DROP explícito da antiga
-- para não ficar um overload. A app antiga (só p_job_id) continua a
-- funcionar porque p_photo_path tem DEFAULT.

DROP FUNCTION IF EXISTS public.mark_job_done(uuid);

CREATE OR REPLACE FUNCTION public.mark_job_done(
  p_job_id     uuid,
  p_photo_path text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id      uuid;
  v_confirmed_date date;
  v_photo          text := NULLIF(btrim(p_photo_path), '');
BEGIN
  SELECT jr.client_id, jr.confirmed_date
  INTO   v_client_id, v_confirmed_date
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  -- Sem data confirmada (horário flexível) não há dia a esperar.
  IF v_confirmed_date IS NOT NULL AND v_confirmed_date > today_pt() THEN
    RAISE EXCEPTION 'Só podes marcar como concluído a partir do dia do trabalho (%).',
      to_char(v_confirmed_date, 'DD/MM');
  END IF;

  -- A foto tem de ser do próprio worker, deste trabalho, e já estar no
  -- bucket (o upload é feito pela app antes de chamar esta função).
  IF v_photo IS NOT NULL THEN
    IF v_photo NOT LIKE auth.uid()::text || '/' || p_job_id::text || '/%'
       OR NOT EXISTS (
         SELECT 1 FROM storage.objects
         WHERE  bucket_id = 'job-photos' AND name = v_photo
       )
    THEN
      RAISE EXCEPTION 'Foto de conclusão inválida.';
    END IF;
  END IF;

  UPDATE public.job_requests
  SET    status                = 'awaiting_confirmation',
         completion_photo_path = v_photo,
         marked_done_at        = now(),
         updated_at            = now()
  WHERE  id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_client_id, 'job_marked_done', 'Trabalho concluído!',
    CASE WHEN v_photo IS NOT NULL
      THEN 'O jardineiro marcou o trabalho como concluído e juntou uma foto. Confirma se está tudo bem.'
      ELSE 'O jardineiro marcou o trabalho como concluído. Confirma se está tudo bem.'
    END,
    p_job_id, 'job_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.mark_job_done(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_job_done(uuid, text) TO authenticated, service_role;


-- ── 4. get_jobs_in_radius: esconde pedidos com data fixa passada ──
-- Igual à 0044, mais o filtro de data. Efeito imediato, sem esperar pelo
-- cron que muda o estado.

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
   AND   jr.location_lat BETWEEN b.lat - b.r / 111.0 AND b.lat + b.r / 111.0
   AND   jr.location_lng BETWEEN b.lng - b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
                             AND b.lng + b.r / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((jr.location_lat::double precision - b.lat) / 2)), 2)
      + cos(radians(b.lat))
        * cos(radians(jr.location_lat::double precision))
        * power(sin(radians((jr.location_lng::double precision - b.lng) / 2)), 2)
    ))) AS distance_km
  ) d
  WHERE  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT (jr.date_mode = 'fixed' AND jr.preferred_date < today_pt())
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  d.distance_km <= b.r
  ORDER BY d.distance_km ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;


-- ── 5. auto_expire_jobs: 48h sem propostas + datas passadas ─────

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
      AND  confirmed_date < today_pt() - 3
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
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.auto_expire_jobs() FROM PUBLIC, anon, authenticated;


-- ── 6. auto_confirm_completed_jobs: conta a partir de marked_done_at ──

CREATE OR REPLACE FUNCTION public.auto_confirm_completed_jobs()
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

  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status = 'awaiting_confirmation'
      AND  COALESCE(marked_done_at, updated_at) < now() - INTERVAL '3 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'completed', updated_at = now()
    WHERE  id = v_job.id;

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_completed', 'Trabalho confirmado automaticamente',
        'Passaram 3 dias sem confirmação. O trabalho foi confirmado automaticamente.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_completed', 'Trabalho confirmado automaticamente',
      'Passaram 3 dias sem resposta. O trabalho foi confirmado automaticamente.',
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.auto_confirm_completed_jobs() FROM PUBLIC, anon, authenticated;


-- ── 7. send_job_reminders: manhã do dia + atrasos ───────────────

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

  -- 7.1 Manhã do dia do trabalho, ao cliente e ao worker.
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

    UPDATE job_requests SET day_reminder_sent_on = v_today WHERE id = v_job.id;
  END LOOP;

  -- 7.2 A data passou e ninguém marcou como concluído (uma vez só).
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      AND  confirmed_date IS NOT NULL
      AND  confirmed_date < v_today
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

  -- 7.3 Marcado como concluído há mais de 1 dia e o cliente não confirmou.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status = 'awaiting_confirmation'
      AND  COALESCE(marked_done_at, updated_at) < now() - INTERVAL '1 day'
      AND  confirmation_reminder_sent_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'Confirma o trabalho',
      'O jardineiro marcou o trabalho como concluído. Confirma ou reporta um problema. Sem resposta, fica confirmado automaticamente 3 dias depois.',
      v_job.id, 'job_request');

    UPDATE job_requests SET confirmation_reminder_sent_at = now() WHERE id = v_job.id;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_job_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_job_reminders() TO service_role;


-- ── 8. pg_cron ──────────────────────────────────────────────────
-- cron.schedule faz upsert pelo nome. 07:30 UTC = 07:30 (inverno) ou
-- 08:30 (verão) em Portugal. Verificar depois de aplicar:
--   SELECT jobname, schedule, active FROM cron.job
--   WHERE jobname IN ('job-reminders', 'auto-expire-jobs',
--                     'auto-confirm-completed-jobs');

SELECT cron.schedule(
  'job-reminders',
  '30 7 * * *',
  'SELECT send_job_reminders()'
);
