-- ══════════════════════════════════════════════════════════════
-- 0072 · Lembretes de início do trabalho
-- NOVA, NÃO APLICADA. Aplicar depois da 0071.
-- ══════════════════════════════════════════════════════════════
-- Pedido do Henrique (12/11): no dia do trabalho, o jardineiro recebe
--   1. um aviso 1 hora antes da hora combinada (é também quando o
--      "Iniciar" fica disponível, ver start_job da 0052);
--   2. um aviso 30 minutos depois da hora, se ainda não carregou em
--      Iniciar.
-- Só para trabalhos com hora marcada (sem "horário flexível"); os outros
-- continuam só com o lembrete da manhã (send_job_reminders, 0046/0069).
-- Cada aviso guarda a hora a que se refere: numa remarcação a hora muda
-- e os avisos voltam a sair para a hora nova.
-- Corre de 5 em 5 minutos; um aviso perdido (cron parado) deixa de sair
-- 6 horas depois da hora, para não chegar fora de contexto.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE public.job_requests
  ADD COLUMN IF NOT EXISTS start_reminder_for       timestamptz,
  ADD COLUMN IF NOT EXISTS late_start_reminder_for  timestamptz;

CREATE OR REPLACE FUNCTION public.send_start_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       record;
  v_worker_id uuid;
  v_hour      text;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 1. Uma hora antes.
  FOR v_job IN
    SELECT jr.id, jr.accepted_proposal_id, jr.confirmed_time, jr.location_area, s.starts_at
    FROM   job_requests jr
    CROSS  JOIN LATERAL (
             SELECT (jr.confirmed_date + jr.confirmed_time)
                      AT TIME ZONE 'Europe/Lisbon' AS starts_at) s
    WHERE  jr.status = 'confirmed'
      AND  jr.started_at IS NULL
      AND  jr.confirmed_date IS NOT NULL
      AND  jr.confirmed_time IS NOT NULL
      AND  NOT COALESCE(jr.confirmed_flexible, false)
      AND  now() >= s.starts_at - INTERVAL '1 hour'
      AND  now() <  s.starts_at
      AND  jr.start_reminder_for IS DISTINCT FROM s.starts_at
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    v_hour := to_char(v_job.confirmed_time, 'HH24:MI');
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'O trabalho começa daqui a 1 hora',
        'Está marcado para as ' || v_hour
          || COALESCE(', em ' || NULLIF(v_job.location_area, ''), '')
          || '. Quando chegares, carrega em Iniciar para o cliente saber.',
        v_job.id, 'job_request');
    END IF;

    UPDATE job_requests SET start_reminder_for = v_job.starts_at WHERE id = v_job.id;
  END LOOP;

  -- 2. Trinta minutos depois, sem "Iniciar".
  FOR v_job IN
    SELECT jr.id, jr.accepted_proposal_id, jr.confirmed_time, s.starts_at
    FROM   job_requests jr
    CROSS  JOIN LATERAL (
             SELECT (jr.confirmed_date + jr.confirmed_time)
                      AT TIME ZONE 'Europe/Lisbon' AS starts_at) s
    WHERE  jr.status = 'confirmed'
      AND  jr.started_at IS NULL
      AND  jr.confirmed_date IS NOT NULL
      AND  jr.confirmed_time IS NOT NULL
      AND  NOT COALESCE(jr.confirmed_flexible, false)
      AND  now() >= s.starts_at + INTERVAL '30 minutes'
      AND  now() <  s.starts_at + INTERVAL '6 hours'
      AND  jr.late_start_reminder_for IS DISTINCT FROM s.starts_at
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    v_hour := to_char(v_job.confirmed_time, 'HH24:MI');
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Ainda não iniciaste o trabalho',
        'Estava marcado para as ' || v_hour
          || '. Se já estás lá, carrega em Iniciar. Se te atrasaste, avisa o cliente por WhatsApp.',
        v_job.id, 'job_request');
    END IF;

    UPDATE job_requests SET late_start_reminder_for = v_job.starts_at WHERE id = v_job.id;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_start_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_start_reminders() TO service_role;

-- cron.schedule faz upsert pelo nome. Verificar depois de aplicar:
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'job-start-reminders';
SELECT cron.schedule(
  'job-start-reminders',
  '*/5 * * * *',
  'SELECT send_start_reminders()'
);

NOTIFY pgrst, 'reload schema';
