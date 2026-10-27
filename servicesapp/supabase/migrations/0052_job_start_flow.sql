-- ══════════════════════════════════════════════════════════════
-- 0052 — Iniciar trabalho, fotos de antes e depois, tempo e 48h
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0049
-- (redefine send_job_reminders e auto_confirm_completed_jobs da 0049) e da
-- 0051. A 0050 ficou reservada para outra thread; não depende dela.
-- Pode correr-se mais do que uma vez sem erro.
--
-- Design de 2026-10-19 (fluxo 3B do jardineiro):
--
-- 1. "Iniciar trabalho": o jardineiro responsável marca o início, a partir
--    de 1h antes da hora combinada (sem hora: a partir do dia; sem data:
--    sempre). Fotos de "antes" opcionais (até 3). O cliente é avisado
--    (tipo novo `job_started`). O trabalho continua `confirmed`; "Em curso"
--    é `confirmed` com `started_at` preenchido, sem estado novo.
--
-- 2. "Marcar como concluído" passa a exigir o início e aceita até 3 fotos
--    de "depois". O tempo registado é `marked_done_at - started_at`.
--    `completion_photo_path` (0046) continua a ser a primeira foto de
--    depois, para a app antiga e para o ecrã do cliente.
--
-- 3. Confirmação automática em 48h (antes 3 dias) se o cliente não
--    confirmar nem reportar problema. Lembrete ao cliente às 24h. Os dois
--    passam para auto_confirm_completed_jobs, que corre de hora a hora
--    (antes de 3 em 3 horas), e o lembrete sai do send_job_reminders
--    diário (07:30), que só corria uma vez por dia.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Colunas novas em job_requests ────────────────────────────

ALTER TABLE public.job_requests
  ADD COLUMN IF NOT EXISTS started_at         timestamptz,
  ADD COLUMN IF NOT EXISTS before_photo_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS after_photo_paths  text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.job_requests
  DROP CONSTRAINT IF EXISTS job_requests_before_photos_max,
  DROP CONSTRAINT IF EXISTS job_requests_after_photos_max;

ALTER TABLE public.job_requests
  ADD CONSTRAINT job_requests_before_photos_max
    CHECK (cardinality(before_photo_paths) <= 3),
  ADD CONSTRAINT job_requests_after_photos_max
    CHECK (cardinality(after_photo_paths) <= 3);


-- ── 2. Validação das fotos do jardineiro ────────────────────────
-- Cada foto tem de ser do próprio, deste trabalho, e já estar no bucket
-- (o upload é feito pela app antes de chamar a RPC). Devolve o array sem
-- vazios. Uso interno das RPCs abaixo.

CREATE OR REPLACE FUNCTION public.validated_job_photo_paths(
  p_job_id uuid,
  p_paths  text[]
)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_paths text[];
  v_path  text;
BEGIN
  SELECT COALESCE(array_agg(btrim(p)) FILTER (WHERE NULLIF(btrim(p), '') IS NOT NULL), '{}')
  INTO   v_paths
  FROM   unnest(COALESCE(p_paths, '{}')) AS p;

  IF cardinality(v_paths) > 3 THEN
    RAISE EXCEPTION 'No máximo 3 fotos.';
  END IF;

  FOREACH v_path IN ARRAY v_paths LOOP
    IF v_path NOT LIKE auth.uid()::text || '/' || p_job_id::text || '/%'
       OR NOT EXISTS (
         SELECT 1 FROM storage.objects
         WHERE  bucket_id = 'job-photos' AND name = v_path
       )
    THEN
      RAISE EXCEPTION 'Foto inválida.';
    END IF;
  END LOOP;

  RETURN v_paths;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.validated_job_photo_paths(uuid, text[]) FROM PUBLIC, anon, authenticated;


-- ── 3. start_job ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.start_job(
  p_job_id      uuid,
  p_photo_paths text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests%ROWTYPE;
  v_opens  timestamptz;
  v_photos text[];
BEGIN
  SELECT jr.* INTO v_job
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já foi iniciado.';
  END IF;

  -- Janela: 1h antes da hora combinada (hora de Portugal). Sem hora, a
  -- partir do dia; sem data, sempre.
  IF v_job.confirmed_date IS NOT NULL THEN
    IF v_job.confirmed_time IS NOT NULL AND NOT COALESCE(v_job.confirmed_flexible, false) THEN
      v_opens := ((v_job.confirmed_date + v_job.confirmed_time) AT TIME ZONE 'Europe/Lisbon')
                 - INTERVAL '1 hour';
      IF now() < v_opens THEN
        RAISE EXCEPTION 'Só podes iniciar o trabalho a partir das % de %.',
          to_char(v_opens AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'),
          to_char(v_opens AT TIME ZONE 'Europe/Lisbon', 'DD/MM');
      END IF;
    ELSIF v_job.confirmed_date > today_pt() THEN
      RAISE EXCEPTION 'Só podes iniciar o trabalho a partir do dia do trabalho (%).',
        to_char(v_job.confirmed_date, 'DD/MM');
    END IF;
  END IF;

  v_photos := validated_job_photo_paths(p_job_id, p_photo_paths);

  UPDATE public.job_requests
  SET    started_at         = now(),
         before_photo_paths = v_photos,
         updated_at         = now()
  WHERE  id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_started', 'O trabalho começou',
    'O jardineiro começou o trabalho.', p_job_id, 'job_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.start_job(uuid, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.start_job(uuid, text[]) TO authenticated, service_role;


-- ── 4. mark_job_done: exige início, até 3 fotos de depois ────────
-- A assinatura muda (text → text[]), por isso DROP explícito da 0046 para
-- não ficar um overload.

DROP FUNCTION IF EXISTS public.mark_job_done(uuid, text);
DROP FUNCTION IF EXISTS public.mark_job_done(uuid);

CREATE OR REPLACE FUNCTION public.mark_job_done(
  p_job_id      uuid,
  p_photo_paths text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job      job_requests%ROWTYPE;
  v_photos   text[];
  v_minutes  integer;
  v_duration text;
BEGIN
  SELECT jr.* INTO v_job
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  IF v_job.started_at IS NULL THEN
    RAISE EXCEPTION 'Inicia o trabalho antes de o marcar como concluído.';
  END IF;

  -- Mesma regra da 0046: só a partir do dia do trabalho.
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date > today_pt() THEN
    RAISE EXCEPTION 'Só podes marcar como concluído a partir do dia do trabalho (%).',
      to_char(v_job.confirmed_date, 'DD/MM');
  END IF;

  v_photos := validated_job_photo_paths(p_job_id, p_photo_paths);

  v_minutes  := GREATEST(0, floor(extract(epoch FROM now() - v_job.started_at) / 60))::integer;
  v_duration := CASE
    WHEN v_minutes < 60 THEN v_minutes || 'min'
    ELSE (v_minutes / 60) || 'h' || CASE WHEN v_minutes % 60 > 0
                                         THEN ' ' || (v_minutes % 60) || 'min'
                                         ELSE '' END
  END;

  UPDATE public.job_requests
  SET    status                = 'awaiting_confirmation',
         after_photo_paths     = v_photos,
         completion_photo_path = v_photos[1],
         marked_done_at        = now(),
         updated_at            = now()
  WHERE  id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_marked_done', 'Trabalho concluído!',
    'O jardineiro terminou o trabalho (' || v_duration || ')'
    || CASE WHEN cardinality(v_photos) > 0 THEN ' e juntou fotos' ELSE '' END
    || '. Confirma se está tudo bem. Sem resposta, fica confirmado em 48 horas.',
    p_job_id, 'job_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.mark_job_done(uuid, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_job_done(uuid, text[]) TO authenticated, service_role;


-- ── 5. auto_confirm_completed_jobs: lembrete às 24h, confirma às 48h ──
-- Igual à 0049 (um problema reportado depois de marcado como concluído
-- suspende), com 48h em vez de 3 dias e o lembrete ao cliente aqui.

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

  -- 5.1 Lembrete ao cliente 24h depois (uma vez só).
  FOR v_job IN
    SELECT * FROM job_requests jr
    WHERE  jr.status = 'awaiting_confirmation'
      AND  COALESCE(jr.marked_done_at, jr.updated_at) < now() - INTERVAL '24 hours'
      AND  jr.confirmation_reminder_sent_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'Confirma o trabalho',
      'O jardineiro marcou o trabalho como concluído. Confirma ou reporta um problema. Sem resposta, fica confirmado automaticamente dentro de 24 horas.',
      v_job.id, 'job_request');

    UPDATE job_requests SET confirmation_reminder_sent_at = now() WHERE id = v_job.id;
  END LOOP;

  -- 5.2 Confirmação automática às 48h.
  FOR v_job IN
    SELECT * FROM job_requests jr
    WHERE  jr.status = 'awaiting_confirmation'
      AND  COALESCE(jr.marked_done_at, jr.updated_at) < now() - INTERVAL '48 hours'
      AND  NOT EXISTS (
        SELECT 1 FROM job_reports rp
        WHERE  rp.job_id     = jr.id
          AND  rp.created_at >= COALESCE(jr.marked_done_at, jr.updated_at)
      )
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
        'Passaram 48 horas sem confirmação. O trabalho foi confirmado automaticamente.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_completed', 'Trabalho confirmado automaticamente',
      'Passaram 48 horas sem resposta. O trabalho foi confirmado automaticamente.',
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.auto_confirm_completed_jobs() FROM PUBLIC, anon, authenticated;

-- De hora a hora (upsert pelo nome), para o lembrete e a confirmação
-- saírem perto das 24h e das 48h.
SELECT cron.schedule(
  'auto-confirm-completed-jobs',
  '15 * * * *',
  'SELECT auto_confirm_completed_jobs()'
);


-- ── 6. send_job_reminders: sem o lembrete de confirmação ─────────
-- Igual à 0049 nas secções 7.1 e 7.2. A 7.3 (lembrete de confirmação)
-- passou para auto_confirm_completed_jobs (secção 5).

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
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_job_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_job_reminders() TO service_role;


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select column_name from information_schema.columns
--   where table_name = 'job_requests'
--     and column_name in ('started_at', 'before_photo_paths', 'after_photo_paths');
-- select oid::regprocedure from pg_proc
--   where proname in ('start_job', 'mark_job_done');   -- 1 linha cada
-- select jobname, schedule from cron.job
--   where jobname = 'auto-confirm-completed-jobs';      -- '15 * * * *'
