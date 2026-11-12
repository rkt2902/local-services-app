-- ══════════════════════════════════════════════════════════════
-- 0071 · Trabalho por dias, relatos e Agenda (revisão, parte 4)
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-11-12). Aplicar depois da 0070.
-- ══════════════════════════════════════════════════════════════
-- 1. Trabalho por dias (proposta com duração em dias): sem relógio nem
--    "Começar/Terminar o dia" na app. O aviso de concluído diz os dias
--    ("3 dias, de 09/11 a 11/11"); o último dia previsto conta a partir
--    do dia em que começou; os ganhos usam a estimativa em vez das horas.
-- 2. Aviso de concluído num trabalho à hora: soma os dias registados em
--    vez de "agora menos o início" (que contava as noites).
-- 3. Relatos: só os da cliente travam a confirmação automática, que passa
--    a acontecer aos 7 dias em vez de nunca. O jardineiro é avisado do
--    relato e o lembrete das 24h deixa de prometer um prazo errado.
-- 4. Agenda: um trabalho "a combinar" aparece a partir do dia em que
--    começou.
-- ══════════════════════════════════════════════════════════════


-- ── Auxiliares ─────────────────────────────────────────────────
-- Mesma regra que isMultiDayWork na app (proposal_price_labels.dart).
CREATE OR REPLACE FUNCTION public.proposal_is_day_based(p_days_min integer, p_days_max integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_days_max IS NOT NULL THEN p_days_max > 1
              ELSE p_days_min IS NOT NULL END;
$function$;

CREATE OR REPLACE FUNCTION public.job_has_client_report(p_job_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   job_reports  rp
    JOIN   job_requests jr ON jr.id = rp.job_id
    WHERE  rp.job_id      = p_job_id
      AND  rp.reporter_id = jr.client_id
      AND  rp.created_at >= COALESCE(jr.marked_done_at, jr.updated_at)
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.job_has_client_report(uuid) FROM PUBLIC, anon, authenticated;


-- ── 1 e 2. Concluir ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_job_done(p_job_id uuid, p_photo_paths text[] DEFAULT '{}'::text[])
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
  v_prop     job_proposals%ROWTYPE;
  v_start_d  date;
  v_days     integer;
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

  -- 0071: trabalho por dias mostra os dias (sem horas); à hora, a soma
  -- dos dias registados, sem contar as noites.
  SELECT * INTO v_prop FROM job_proposals WHERE id = v_job.accepted_proposal_id;
  IF proposal_is_day_based(v_prop.estimated_days_min, v_prop.estimated_days_max) THEN
    v_start_d  := (v_job.started_at AT TIME ZONE 'Europe/Lisbon')::date;
    v_days     := today_pt() - v_start_d + 1;
    v_duration := CASE WHEN v_days <= 1 THEN '1 dia'
                       ELSE v_days || ' dias, de ' || to_char(v_start_d, 'DD/MM')
                            || ' a ' || to_char(today_pt(), 'DD/MM') END;
  ELSE
    SELECT COALESCE(sum(extract(epoch FROM (COALESCE(wd.ended_at, now()) - wd.started_at))), 0)
    INTO   v_minutes
    FROM   job_work_days wd
    WHERE  wd.job_id = p_job_id;
    v_minutes := GREATEST(0, floor(COALESCE(NULLIF(v_minutes, 0),
                   extract(epoch FROM now() - v_job.started_at)) / 60))::integer;
    v_duration := CASE
      WHEN v_minutes < 60 THEN v_minutes || 'min'
      ELSE (v_minutes / 60) || 'h' || CASE WHEN v_minutes % 60 > 0
                                           THEN ' ' || (v_minutes % 60) || 'min'
                                           ELSE '' END
    END;
  END IF;

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

CREATE OR REPLACE FUNCTION public.job_expected_end_date(p_job_id uuid)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 0071: conta a partir do dia em que começou, se foi depois do marcado.
  SELECT GREATEST(
    GREATEST(jr.confirmed_date, (jr.started_at AT TIME ZONE 'Europe/Lisbon')::date)
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

REVOKE EXECUTE ON FUNCTION public.job_expected_end_date(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_earnings(p_from date, p_to date)
 RETURNS TABLE(job_id uuid, role text, service_type_name text, done_on date, job_status text, pricing_mode text, rate numeric, total_price numeric, worked_minutes integer, estimated_hours_min numeric, estimated_hours_max numeric, helpers_cost numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'Intervalo de datas inválido.';
  END IF;

  IF worker_active_tier(v_uid) = 'free' THEN
    RAISE EXCEPTION 'O painel de ganhos é do plano Pro.'
      USING ERRCODE = 'P0001', HINT = 'plan_required';
  END IF;

  RETURN QUERY
  WITH done_jobs AS (
    SELECT jr.id,
           jr.status,
           jr.service_type_id,
           jr.accepted_proposal_id,
           jr.started_at,
           jr.marked_done_at,
           (COALESCE(jr.marked_done_at, jr.updated_at)
              AT TIME ZONE 'Europe/Lisbon')::date AS done_on
    FROM   job_requests jr
    WHERE  jr.status IN ('completed', 'awaiting_confirmation')
      AND  jr.accepted_proposal_id IS NOT NULL
  ),
  minutes AS (
    SELECT dj.id AS job_id,
           -- 0071: trabalho por dias não tem relógio; fica a estimativa.
           CASE WHEN proposal_is_day_based(jp0.estimated_days_min, jp0.estimated_days_max)
                THEN NULL ELSE
           COALESCE(
             (SELECT (sum(extract(epoch FROM (wd.ended_at - wd.started_at))) / 60)::integer
              FROM   job_work_days wd
              WHERE  wd.job_id = dj.id AND wd.ended_at IS NOT NULL
              HAVING count(*) > 0),
             CASE WHEN dj.started_at IS NOT NULL
                       AND dj.marked_done_at IS NOT NULL
                       AND dj.marked_done_at > dj.started_at
                  THEN (extract(epoch FROM (dj.marked_done_at - dj.started_at)) / 60)::integer
             END
           ) END AS worked_minutes
    FROM   done_jobs dj
    JOIN   job_proposals jp0 ON jp0.id = dj.accepted_proposal_id
    WHERE  dj.done_on BETWEEN p_from AND p_to
  )
  -- Responsável
  SELECT dj.id,
         'principal'::text,
         st.name,
         dj.done_on,
         dj.status,
         jp.pricing_mode,
         jp.hourly_rate,
         jp.total_price,
         m.worked_minutes,
         jp.estimated_hours_min,
         jp.estimated_hours_max,
         CASE WHEN m.worked_minutes IS NULL
                   AND NOT proposal_is_day_based(jp.estimated_days_min, jp.estimated_days_max)
              THEN NULL ELSE
           COALESCE((
             SELECT sum(ha.agreed_rate)
             FROM   help_requests hr
             JOIN   help_acceptances ha ON ha.help_request_id = hr.id
             WHERE  hr.job_id = dj.id AND ha.status = 'accepted'
           ), 0) * COALESCE(m.worked_minutes / 60.0,
                            (COALESCE(jp.estimated_hours_min, jp.estimated_hours_max, 0)
                             + COALESCE(jp.estimated_hours_max, jp.estimated_hours_min, 0)) / 2.0)
         END
  FROM   done_jobs dj
  JOIN   minutes m        ON m.job_id = dj.id
  JOIN   job_proposals jp ON jp.id = dj.accepted_proposal_id
  LEFT JOIN service_types st ON st.id = dj.service_type_id
  WHERE  jp.worker_id = v_uid

  UNION ALL

  -- Ajudante
  SELECT dj.id,
         'helper'::text,
         st.name,
         dj.done_on,
         dj.status,
         'hourly'::text,
         ha.agreed_rate,
         NULL::numeric,
         m.worked_minutes,
         jp.estimated_hours_min,
         jp.estimated_hours_max,
         NULL::numeric
  FROM   done_jobs dj
  JOIN   minutes m          ON m.job_id = dj.id
  JOIN   job_proposals jp   ON jp.id = dj.accepted_proposal_id
  JOIN   help_requests hr   ON hr.job_id = dj.id
  JOIN   help_acceptances ha ON ha.help_request_id = hr.id
  LEFT JOIN service_types st ON st.id = dj.service_type_id
  WHERE  ha.worker_id = v_uid
    AND  ha.status = 'accepted'

  ORDER BY 4 DESC, 1;
END;
$function$;


-- ── 3. Relatos ─────────────────────────────────────────────────
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
      -- 0071: com relato da cliente o prazo é outro e ela já foi avisada.
      AND  NOT job_has_client_report(jr.id)
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
      -- 0071: 48h; com relato da cliente, 7 dias. Só os relatos dela
      -- contam (antes um relato do jardineiro também travava) e o
      -- trabalho já não fica preso para sempre.
      AND  COALESCE(jr.marked_done_at, jr.updated_at)
             < now() - CASE WHEN job_has_client_report(jr.id)
                            THEN INTERVAL '7 days' ELSE INTERVAL '48 hours' END
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
        CASE WHEN job_has_client_report(v_job.id)
          THEN 'Passaram 7 dias desde o relato da cliente sem ela confirmar. O trabalho foi confirmado automaticamente.'
          ELSE 'Passaram 48 horas sem confirmação. O trabalho foi confirmado automaticamente.' END,
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_completed', 'Trabalho confirmado automaticamente',
      CASE WHEN job_has_client_report(v_job.id)
        THEN 'Passaram 7 dias desde o teu relato. O trabalho foi confirmado automaticamente.'
        ELSE 'Passaram 48 horas sem resposta. O trabalho foi confirmado automaticamente.' END,
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_job_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = NEW.job_id;
  IF NOT FOUND OR v_job.status <> 'awaiting_confirmation'
     OR NEW.reporter_id <> v_job.client_id THEN
    RETURN NEW;
  END IF;

  SELECT worker_id INTO v_worker_id
  FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

  IF v_worker_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_worker_id, 'job_reminder', 'O cliente reportou um problema',
      'Fala com o cliente por WhatsApp para resolver. Se não confirmar antes, o trabalho fica confirmado a '
        || to_char((COALESCE(v_job.marked_done_at, now()) + interval '7 days')
                   AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '.',
      v_job.id, 'job_request');
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_job_report() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_job_report ON public.job_reports;
CREATE TRIGGER trg_notify_job_report
  AFTER INSERT ON public.job_reports
  FOR EACH ROW EXECUTE FUNCTION public.notify_job_report();


-- ── 4. Agenda ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_worker_agenda(p_from date, p_to date)
 RETURNS TABLE(entry_kind text, source_id uuid, job_id uuid, occurrence_date date, series_date date, start_time time without time zone, end_time time without time zone, day_index integer, day_count integer, title text, service_type_id uuid, location_label text, person_name text, person_phone text, status text, is_tentative boolean, amount_min numeric, amount_max numeric, recurrence text, is_exception boolean, notes text, proposal_id uuid, location_lat numeric, location_lng numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida' USING ERRCODE = '42501';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 62 THEN
    RAISE EXCEPTION 'Intervalo inválido (máximo 62 dias)' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH
  -- Trabalhos da app: base comum a responsável e ajudante. Duração em horas
  -- ou, se a proposta for em dias, um bloco de dias inteiros.
  app_base AS (
    SELECT j.id                              AS job_id,
           j.status                          AS job_status,
           j.started_at,
           -- 0071: "a combinar" já começado entra a partir do dia em que começou.
           COALESCE(j.confirmed_date,
                    (j.started_at AT TIME ZONE 'Europe/Lisbon')::date) AS day0,
           j.confirmed_time                  AS t0,
           j.service_type_id,
           j.address_text,
           j.location_area,
           j.client_id,
           pr.worker_id                      AS principal_id,
           pr.estimated_hours_max,
           GREATEST(COALESCE(pr.estimated_days_max, 1), 1) AS days,
           pr.pricing_mode,
           pr.total_price,
           pr.hourly_rate,
           pr.estimated_hours_min,
           j.reschedule_status,
           j.reschedule_proposed_date,
           j.reschedule_proposed_time,
           pr.id                             AS proposal_id,
           j.location_lat,
           j.location_lng
    FROM   job_requests  j
    JOIN   job_proposals pr ON pr.id = j.accepted_proposal_id
    WHERE  j.status IN ('confirmed', 'awaiting_confirmation', 'completed')
      AND  COALESCE(j.confirmed_date, (j.started_at AT TIME ZONE 'Europe/Lisbon')::date) IS NOT NULL
      AND  COALESCE(j.confirmed_date, (j.started_at AT TIME ZONE 'Europe/Lisbon')::date) <= p_to
      AND  COALESCE(j.confirmed_date, (j.started_at AT TIME ZONE 'Europe/Lisbon')::date) + 30 >= p_from
  ),
  rows_app AS (
    SELECT 'app_job'::text, b.job_id, b.job_id, b.day0, b.t0, b.days,
           b.estimated_hours_max, b.service_type_id,
           COALESCE(b.address_text, b.location_area),
           cp.full_name, cp.phone,
           CASE WHEN b.job_status = 'confirmed' AND b.started_at IS NOT NULL
                THEN 'in_progress' ELSE b.job_status END,
           false,
           CASE WHEN b.pricing_mode = 'fixed_total' THEN b.total_price
                ELSE b.hourly_rate * b.estimated_hours_min END,
           CASE WHEN b.pricing_mode = 'fixed_total' THEN b.total_price
                ELSE b.hourly_rate * b.estimated_hours_max END,
           b.proposal_id, b.location_lat, b.location_lng
    FROM   app_base b
    LEFT   JOIN profiles cp ON cp.id = b.client_id
    WHERE  b.principal_id = v_uid
  ),
  rows_reschedule AS (
    SELECT 'reschedule'::text, b.job_id, b.job_id, b.reschedule_proposed_date,
           b.reschedule_proposed_time, b.days, b.estimated_hours_max,
           b.service_type_id, COALESCE(b.address_text, b.location_area),
           cp.full_name, cp.phone, 'pending'::text, true,
           NULL::numeric, NULL::numeric,
           b.proposal_id, b.location_lat, b.location_lng
    FROM   app_base b
    LEFT   JOIN profiles cp ON cp.id = b.client_id
    WHERE  b.principal_id = v_uid
      AND  b.job_status = 'confirmed'
      AND  b.reschedule_status = 'pending'
      AND  b.reschedule_proposed_date IS NOT NULL
  ),
  rows_helper AS (
    SELECT 'helper_job'::text, ha.id, b.job_id, b.day0, b.t0, b.days,
           b.estimated_hours_max, b.service_type_id, b.location_area,
           pp.full_name, pp.phone,
           CASE WHEN b.job_status = 'confirmed' AND b.started_at IS NOT NULL
                THEN 'in_progress' ELSE b.job_status END,
           false,
           ha.agreed_rate * b.estimated_hours_min,
           ha.agreed_rate * b.estimated_hours_max,
           NULL::uuid, b.location_lat, b.location_lng
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    JOIN   app_base         b  ON b.job_id = hr.job_id
    LEFT   JOIN profiles    pp ON pp.id = b.principal_id
    WHERE  ha.worker_id = v_uid
      AND  ha.status = 'accepted'
      AND  hr.status <> 'cancelled'
  ),
  rows_proposal AS (
    SELECT 'proposal'::text, pr.id, j.id, pr.scheduled_date, pr.scheduled_time,
           GREATEST(COALESCE(pr.estimated_days_max, 1), 1),
           pr.estimated_hours_max, j.service_type_id, j.location_area,
           NULL::text, NULL::text, 'pending'::text, true,
           CASE WHEN pr.pricing_mode = 'fixed_total' THEN pr.total_price
                ELSE pr.hourly_rate * pr.estimated_hours_min END,
           CASE WHEN pr.pricing_mode = 'fixed_total' THEN pr.total_price
                ELSE pr.hourly_rate * pr.estimated_hours_max END,
           pr.id, NULL::numeric, NULL::numeric
    FROM   job_proposals pr
    JOIN   job_requests  j ON j.id = pr.job_id
    WHERE  pr.worker_id = v_uid
      AND  pr.status = 'pending'
      AND  j.status = 'open'
      AND  pr.scheduled_date IS NOT NULL
      AND  pr.scheduled_date <= p_to
      AND  pr.scheduled_date + 30 >= p_from
  ),
  -- Linhas da app expandidas por dia. A duração em horas só conta num
  -- trabalho de um dia; em vários dias cada dia fica "dia todo".
  app_days AS (
    SELECT r.*, d.n
    FROM (
      SELECT * FROM rows_app
      UNION ALL SELECT * FROM rows_reschedule
      UNION ALL SELECT * FROM rows_helper
      UNION ALL SELECT * FROM rows_proposal
    ) AS r(kind, src, jid, day0, t0, days, hours_max, stype, loc, pname,
           pphone, st, tentative, amin, amax, prop, lat, lng)
    CROSS JOIN LATERAL generate_series(1, r.days) AS d(n)
  ),
  -- Séries de fora da app: ocorrências que tocam no intervalo, mais as que
  -- foram mudadas para dentro dele a partir de fora.
  series AS (
    SELECT e.*,
           COALESCE(e.ends_on - e.starts_on, 0) AS span,
           COALESCE(e.recurrence_until, p_to)   AS last_day
    FROM   worker_calendar_entries e
    WHERE  e.worker_id = v_uid
      AND  e.starts_on <= p_to
      AND  (e.recurrence <> 'none' OR COALESCE(e.ends_on, e.starts_on) >= p_from
            OR EXISTS (SELECT 1 FROM worker_calendar_exceptions x
                       WHERE x.entry_id = e.id AND x.action = 'moved'
                         AND x.new_date BETWEEN p_from AND p_to))
      AND  (e.recurrence = 'none' OR COALESCE(e.recurrence_until, p_to) >= p_from - 6
            OR EXISTS (SELECT 1 FROM worker_calendar_exceptions x
                       WHERE x.entry_id = e.id AND x.action = 'moved'
                         AND x.new_date BETWEEN p_from AND p_to))
  ),
  occurrences AS (
    -- Não repete
    SELECT s.id, s.starts_on AS occ
    FROM   series s WHERE s.recurrence = 'none'
    UNION
    -- Semanal e quinzenal: só os passos que podem tocar no intervalo
    SELECT s.id, (s.starts_on + k * st.step)::date
    FROM   series s
    CROSS  JOIN LATERAL (SELECT CASE s.recurrence WHEN 'weekly' THEN 7 ELSE 14 END AS step) st
    CROSS  JOIN LATERAL generate_series(
             GREATEST(0, (p_from - s.span - s.starts_on) / st.step),
             (LEAST(s.last_day, p_to) - s.starts_on) / st.step) AS k
    WHERE  s.recurrence IN ('weekly', 'biweekly')
    UNION
    -- Mensal: sempre a partir de starts_on (o dia 31 cai no último dia)
    SELECT s.id, (s.starts_on + make_interval(months => m))::date
    FROM   series s
    CROSS  JOIN LATERAL generate_series(
             GREATEST(0, ((date_part('year', p_from)::int - date_part('year', s.starts_on)::int) * 12
                         + date_part('month', p_from)::int - date_part('month', s.starts_on)::int) - 1),
             (date_part('year', LEAST(s.last_day, p_to))::int - date_part('year', s.starts_on)::int) * 12
               + date_part('month', LEAST(s.last_day, p_to))::int - date_part('month', s.starts_on)::int
           ) AS m
    WHERE  s.recurrence = 'monthly'
    UNION
    -- Ocorrências mudadas para dentro do intervalo
    SELECT x.entry_id, x.occurrence_date
    FROM   worker_calendar_exceptions x
    JOIN   series s ON s.id = x.entry_id
    WHERE  x.action = 'moved' AND x.new_date BETWEEN p_from AND p_to
  ),
  ext AS (
    SELECT s.kind, s.id, o.occ,
           CASE WHEN x.action = 'moved' THEN x.new_date ELSE o.occ END AS day0,
           CASE WHEN x.action IN ('moved', 'changed') AND x.new_all_day THEN NULL
                WHEN x.action IN ('moved', 'changed') AND x.new_time IS NOT NULL THEN x.new_time
                ELSE s.start_time END AS t0,
           COALESCE(CASE WHEN x.action IN ('moved', 'changed') THEN x.new_duration_minutes END,
                    s.duration_minutes) AS dur,
           s.span + 1 AS days,
           COALESCE(CASE WHEN x.action IN ('moved', 'changed') THEN x.new_title END, s.title) AS title,
           s.service_type_id, s.location_label, s.person_name, s.person_phone,
           s.location_lat, s.location_lng,
           COALESCE(x.status, s.status) AS st,
           s.amount, s.recurrence,
           COALESCE(x.action IN ('moved', 'changed'), false) AS is_exc,
           COALESCE(CASE WHEN x.action IN ('moved', 'changed') THEN x.new_notes END, s.notes) AS notes
    FROM   occurrences o
    JOIN   series s ON s.id = o.id
    LEFT   JOIN worker_calendar_exceptions x
           ON x.entry_id = s.id AND x.occurrence_date = o.occ
    WHERE  o.occ >= s.starts_on
      AND  o.occ <= s.last_day
      AND  COALESCE(x.action, '') <> 'skipped'
  )
  SELECT a.kind,
         a.src,
         a.jid,
         (a.day0 + (a.n - 1))::date,
         a.day0,
         CASE WHEN a.days = 1 THEN a.t0 END,
         CASE WHEN a.days = 1 AND a.t0 IS NOT NULL AND a.hours_max IS NOT NULL
              THEN CASE WHEN extract(epoch FROM a.t0) / 60 + a.hours_max * 60 >= 1439
                        THEN time '23:59'
                        ELSE a.t0 + make_interval(mins => (a.hours_max * 60)::int) END
         END,
         a.n,
         a.days,
         NULL::text,
         a.stype,
         a.loc,
         a.pname,
         a.pphone,
         a.st,
         a.tentative,
         a.amin,
         a.amax,
         'none'::text,
         false,
         NULL::text,
         a.prop,
         a.lat,
         a.lng
  FROM   app_days a
  WHERE  (a.day0 + (a.n - 1)) BETWEEN p_from AND p_to

  UNION ALL

  SELECT CASE WHEN e.kind = 'block' THEN 'block' ELSE 'external' END,
         e.id,
         NULL::uuid,
         (e.day0 + (d.n - 1))::date,
         e.occ,
         CASE WHEN e.days = 1 THEN e.t0 END,
         CASE WHEN e.days = 1 AND e.t0 IS NOT NULL AND e.dur IS NOT NULL
              THEN CASE WHEN extract(epoch FROM e.t0) / 60 + e.dur >= 1439
                        THEN time '23:59'
                        ELSE e.t0 + make_interval(mins => e.dur) END
         END,
         d.n,
         e.days,
         e.title,
         e.service_type_id,
         e.location_label,
         e.person_name,
         e.person_phone,
         e.st,
         false,
         e.amount,
         e.amount,
         e.recurrence,
         e.is_exc,
         e.notes,
         NULL::uuid,
         e.location_lat,
         e.location_lng
  FROM   ext e
  CROSS  JOIN LATERAL generate_series(1, e.days) AS d(n)
  WHERE  (e.day0 + (d.n - 1)) BETWEEN p_from AND p_to

  ORDER  BY 4, 6 NULLS FIRST, 1;
END;
$function$;

NOTIFY pgrst, 'reload schema';
