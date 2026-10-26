-- ══════════════════════════════════════════════════════════════
-- 0064 — Agenda do jardineiro: trabalhos fora da app e leitura única
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, depois da 0058
-- (usa job_proposals.pricing_mode/total_price/estimated_days_*) e da 0043
-- (job_requests.location_area). Pode correr-se mais do que uma vez.
--
-- Decisões de 26/10 (projardim/design/2026-10-26-plano-agenda-jardineiro.md):
--
-- 1. `worker_calendar_entries`: trabalhos que não vieram pela app
--    (kind = 'job') e indisponibilidades (kind = 'block'). Só o dono lê e
--    escreve. `worker_id` nunca vem da app: DEFAULT auth.uid() e a policy
--    confirma-o.
-- 2. Repetição completa: semanal, quinzenal, mensal, com fim opcional.
--    "Só este dia" = linha em `worker_calendar_exceptions`; "Este e os
--    seguintes" = `split_calendar_series`; "Todos" = UPDATE da série.
--    Mensal conta sempre a partir de `starts_on` (31/01 + 1 mês = 28/02,
--    31/01 + 2 meses = 31/03).
-- 3. `get_worker_agenda(p_from, p_to)`: uma linha por dia ocupado, juntando
--    trabalhos da app (responsável e ajudante), propostas pendentes com data
--    e remarcações por aceitar (tentativas), trabalhos de fora e
--    indisponibilidades. A deteção de sobreposições é feita na app sobre
--    esta leitura.
--
-- Datas e horas em hora de Portugal (date + time), como confirmed_date/time.

-- ── 1. Trabalhos fora da app e indisponibilidades ───────────────

CREATE TABLE IF NOT EXISTS public.worker_calendar_entries (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id        uuid        NOT NULL DEFAULT auth.uid()
                     REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind             text        NOT NULL DEFAULT 'job'
                     CHECK (kind IN ('job', 'block')),
  title            text        NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  service_type_id  uuid        REFERENCES public.service_types(id) ON DELETE SET NULL,
  person_name      text        CHECK (person_name IS NULL OR char_length(person_name) <= 80),
  person_phone     text        CHECK (person_phone IS NULL OR person_phone ~ '^\+?[0-9 ]{6,20}$'),
  location_label   text        CHECK (location_label IS NULL OR char_length(location_label) <= 160),
  location_lat     numeric,
  location_lng     numeric,
  starts_on        date        NOT NULL,
  start_time       time,
  duration_minutes integer     CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 15 AND 1440),
  ends_on          date,
  recurrence       text        NOT NULL DEFAULT 'none'
                     CHECK (recurrence IN ('none', 'weekly', 'biweekly', 'monthly')),
  recurrence_until date,
  amount           numeric     CHECK (amount IS NULL OR amount >= 0),
  notes            text        CHECK (notes IS NULL OR char_length(notes) <= 500),
  status           text        NOT NULL DEFAULT 'scheduled'
                     CHECK (status IN ('scheduled', 'done', 'cancelled')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT worker_calendar_entries_ends_check
    CHECK (ends_on IS NULL OR ends_on >= starts_on),
  CONSTRAINT worker_calendar_entries_until_check
    CHECK (recurrence_until IS NULL OR recurrence_until >= starts_on),
  -- Vários dias seguidos não se repetem (evita séries a sobrepor-se a si
  -- próprias): no máximo 6 dias para uma série semanal.
  CONSTRAINT worker_calendar_entries_span_check
    CHECK (ends_on IS NULL OR recurrence = 'none' OR ends_on - starts_on <= 6),
  -- Uma indisponibilidade não leva cliente, valor nem serviço.
  CONSTRAINT worker_calendar_entries_block_check
    CHECK (kind = 'job' OR (person_name IS NULL AND person_phone IS NULL
                            AND amount IS NULL AND service_type_id IS NULL))
);

CREATE INDEX IF NOT EXISTS worker_calendar_entries_worker_idx
  ON public.worker_calendar_entries (worker_id, starts_on);

ALTER TABLE public.worker_calendar_entries ENABLE ROW LEVEL SECURITY;

-- Sem acesso anónimo; o resto fica nas policies.
REVOKE ALL ON public.worker_calendar_entries FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.worker_calendar_entries TO authenticated;

DROP POLICY IF EXISTS worker_calendar_entries_select ON public.worker_calendar_entries;
CREATE POLICY worker_calendar_entries_select ON public.worker_calendar_entries
  FOR SELECT TO authenticated
  USING (worker_id = (SELECT auth.uid()));

-- Só quem tem papel de worker cria entradas (RETURNING precisa também do
-- SELECT acima).
DROP POLICY IF EXISTS worker_calendar_entries_insert ON public.worker_calendar_entries;
CREATE POLICY worker_calendar_entries_insert ON public.worker_calendar_entries
  FOR INSERT TO authenticated
  WITH CHECK (
    worker_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = (SELECT auth.uid()) AND p.role = 'worker')
  );

DROP POLICY IF EXISTS worker_calendar_entries_update ON public.worker_calendar_entries;
CREATE POLICY worker_calendar_entries_update ON public.worker_calendar_entries
  FOR UPDATE TO authenticated
  USING (worker_id = (SELECT auth.uid()))
  WITH CHECK (worker_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS worker_calendar_entries_delete ON public.worker_calendar_entries;
CREATE POLICY worker_calendar_entries_delete ON public.worker_calendar_entries
  FOR DELETE TO authenticated
  USING (worker_id = (SELECT auth.uid()));

-- ── 2. Exceções de uma série ("Só este dia") ────────────────────

CREATE TABLE IF NOT EXISTS public.worker_calendar_exceptions (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id             uuid        NOT NULL
                         REFERENCES public.worker_calendar_entries(id) ON DELETE CASCADE,
  worker_id            uuid        NOT NULL DEFAULT auth.uid()
                         REFERENCES public.profiles(id) ON DELETE CASCADE,
  occurrence_date      date        NOT NULL,
  action               text        NOT NULL
                         CHECK (action IN ('cancelled', 'moved', 'changed', 'done')),
  new_date             date,
  new_time             time,
  new_all_day          boolean     NOT NULL DEFAULT false,
  new_duration_minutes integer     CHECK (new_duration_minutes IS NULL
                                          OR new_duration_minutes BETWEEN 15 AND 1440),
  new_title            text        CHECK (new_title IS NULL OR char_length(btrim(new_title)) BETWEEN 1 AND 80),
  new_notes            text        CHECK (new_notes IS NULL OR char_length(new_notes) <= 500),
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entry_id, occurrence_date),
  CONSTRAINT worker_calendar_exceptions_moved_check
    CHECK (action <> 'moved' OR new_date IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS worker_calendar_exceptions_worker_idx
  ON public.worker_calendar_exceptions (worker_id, new_date);

ALTER TABLE public.worker_calendar_exceptions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.worker_calendar_exceptions FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.worker_calendar_exceptions TO authenticated;

DROP POLICY IF EXISTS worker_calendar_exceptions_select ON public.worker_calendar_exceptions;
CREATE POLICY worker_calendar_exceptions_select ON public.worker_calendar_exceptions
  FOR SELECT TO authenticated
  USING (worker_id = (SELECT auth.uid()));

-- A série tem de ser do próprio: sem isto dava para pendurar exceções em
-- entradas de outra pessoa (não as via, mas ocupava a chave única).
DROP POLICY IF EXISTS worker_calendar_exceptions_insert ON public.worker_calendar_exceptions;
CREATE POLICY worker_calendar_exceptions_insert ON public.worker_calendar_exceptions
  FOR INSERT TO authenticated
  WITH CHECK (
    worker_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.worker_calendar_entries e
                WHERE e.id = entry_id AND e.worker_id = (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS worker_calendar_exceptions_update ON public.worker_calendar_exceptions;
CREATE POLICY worker_calendar_exceptions_update ON public.worker_calendar_exceptions
  FOR UPDATE TO authenticated
  USING (worker_id = (SELECT auth.uid()))
  WITH CHECK (
    worker_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.worker_calendar_entries e
                WHERE e.id = entry_id AND e.worker_id = (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS worker_calendar_exceptions_delete ON public.worker_calendar_exceptions;
CREATE POLICY worker_calendar_exceptions_delete ON public.worker_calendar_exceptions
  FOR DELETE TO authenticated
  USING (worker_id = (SELECT auth.uid()));

-- updated_at da série
CREATE OR REPLACE FUNCTION public.touch_worker_calendar_entry()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_worker_calendar_entry ON public.worker_calendar_entries;
CREATE TRIGGER trg_touch_worker_calendar_entry
  BEFORE UPDATE ON public.worker_calendar_entries
  FOR EACH ROW EXECUTE FUNCTION public.touch_worker_calendar_entry();

-- ── 3. "Este e os seguintes": dividir uma série ─────────────────
--
-- A série antiga acaba na véspera de p_from_date; a nova começa em
-- p_from_date com os mesmos dados e herda as exceções a partir desse dia.
-- A app aplica depois as mudanças à série nova com um UPDATE normal.
-- Devolve o id da série nova.

DROP FUNCTION IF EXISTS public.split_calendar_series(uuid, date);

CREATE FUNCTION public.split_calendar_series(p_entry_id uuid, p_from_date date)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_entry worker_calendar_entries%ROWTYPE;
  v_new   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry
  FROM   worker_calendar_entries
  WHERE  id = p_entry_id AND worker_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrada não encontrada' USING ERRCODE = 'P0002';
  END IF;
  IF v_entry.recurrence = 'none' THEN
    RAISE EXCEPTION 'Esta entrada não se repete' USING ERRCODE = '22023';
  END IF;
  IF p_from_date <= v_entry.starts_on THEN
    RAISE EXCEPTION 'Para mudar a série toda, edita a entrada' USING ERRCODE = '22023';
  END IF;
  IF v_entry.recurrence_until IS NOT NULL AND p_from_date > v_entry.recurrence_until THEN
    RAISE EXCEPTION 'A série já acabou nesse dia' USING ERRCODE = '22023';
  END IF;

  INSERT INTO worker_calendar_entries (
    worker_id, kind, title, service_type_id, person_name, person_phone,
    location_label, location_lat, location_lng, starts_on, start_time,
    duration_minutes, ends_on, recurrence, recurrence_until, amount, notes, status
  ) VALUES (
    v_uid, v_entry.kind, v_entry.title, v_entry.service_type_id,
    v_entry.person_name, v_entry.person_phone, v_entry.location_label,
    v_entry.location_lat, v_entry.location_lng, p_from_date, v_entry.start_time,
    v_entry.duration_minutes,
    CASE WHEN v_entry.ends_on IS NULL THEN NULL
         ELSE p_from_date + (v_entry.ends_on - v_entry.starts_on) END,
    v_entry.recurrence, v_entry.recurrence_until, v_entry.amount, v_entry.notes,
    v_entry.status
  )
  RETURNING id INTO v_new;

  UPDATE worker_calendar_entries
  SET    recurrence_until = p_from_date - 1
  WHERE  id = p_entry_id;

  UPDATE worker_calendar_exceptions
  SET    entry_id = v_new
  WHERE  entry_id = p_entry_id AND occurrence_date >= p_from_date;

  RETURN v_new;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.split_calendar_series(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.split_calendar_series(uuid, date) TO authenticated;

-- ── 4. Leitura única da agenda ──────────────────────────────────
--
-- Uma linha por dia ocupado (um trabalho de 3 dias dá 3 linhas, com
-- day_index 1..3 e day_count 3). Intervalo máximo de 62 dias.
--
-- entry_kind:
--   app_job      sou o responsável (confirmed, awaiting_confirmation, completed)
--   helper_job   sou ajudante aceite
--   proposal     proposta pendente com data, pedido ainda aberto (tentativa)
--   reschedule   nova data pedida numa remarcação por aceitar (tentativa)
--   external     trabalho fora da app
--   block        indisponível
--
-- source_id: id do pedido (app_job, reschedule), da candidatura (helper_job),
-- da proposta (proposal) ou da série (external, block). job_id para abrir o
-- detalhe. occurrence_date é o dia desta linha; series_date é o dia da
-- ocorrência na série (para exceções), igual a occurrence_date fora das séries.
--
-- Fim estimado: hora + duração (estimated_hours_max nas propostas,
-- duration_minutes nos de fora), limitado a 23:59. Sem duração: NULL (a app
-- usa as durações por omissão na deteção).

DROP FUNCTION IF EXISTS public.get_worker_agenda(date, date);

CREATE FUNCTION public.get_worker_agenda(p_from date, p_to date)
RETURNS TABLE(
  entry_kind       text,
  source_id        uuid,
  job_id           uuid,
  occurrence_date  date,
  series_date      date,
  start_time       time,
  end_time         time,
  day_index        integer,
  day_count        integer,
  title            text,
  service_type_id  uuid,
  location_label   text,
  person_name      text,
  person_phone     text,
  status           text,
  is_tentative     boolean,
  amount_min       numeric,
  amount_max       numeric,
  recurrence       text,
  is_exception     boolean,
  notes            text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
           j.confirmed_date                  AS day0,
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
           j.reschedule_proposed_time
    FROM   job_requests  j
    JOIN   job_proposals pr ON pr.id = j.accepted_proposal_id
    WHERE  j.status IN ('confirmed', 'awaiting_confirmation', 'completed')
      AND  j.confirmed_date IS NOT NULL
      AND  j.confirmed_date <= p_to
      AND  j.confirmed_date + 30 >= p_from
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
                ELSE b.hourly_rate * b.estimated_hours_max END
    FROM   app_base b
    LEFT   JOIN profiles cp ON cp.id = b.client_id
    WHERE  b.principal_id = v_uid
  ),
  rows_reschedule AS (
    SELECT 'reschedule'::text, b.job_id, b.job_id, b.reschedule_proposed_date,
           b.reschedule_proposed_time, b.days, b.estimated_hours_max,
           b.service_type_id, COALESCE(b.address_text, b.location_area),
           cp.full_name, cp.phone, 'pending'::text, true,
           NULL::numeric, NULL::numeric
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
           pp.full_name, NULL::text,
           CASE WHEN b.job_status = 'confirmed' AND b.started_at IS NOT NULL
                THEN 'in_progress' ELSE b.job_status END,
           false,
           ha.agreed_rate * b.estimated_hours_min,
           ha.agreed_rate * b.estimated_hours_max
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
                ELSE pr.hourly_rate * pr.estimated_hours_max END
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
           pphone, st, tentative, amin, amax)
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
           CASE WHEN x.action = 'done' THEN 'done' ELSE s.status END AS st,
           s.amount, s.recurrence,
           x.id IS NOT NULL AS is_exc,
           COALESCE(CASE WHEN x.action IN ('moved', 'changed') THEN x.new_notes END, s.notes) AS notes
    FROM   occurrences o
    JOIN   series s ON s.id = o.id
    LEFT   JOIN worker_calendar_exceptions x
           ON x.entry_id = s.id AND x.occurrence_date = o.occ
    WHERE  o.occ >= s.starts_on
      AND  o.occ <= s.last_day
      AND  COALESCE(x.action, '') <> 'cancelled'
      AND  s.status <> 'cancelled'
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
         NULL::text
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
         e.notes
  FROM   ext e
  CROSS  JOIN LATERAL generate_series(1, e.days) AS d(n)
  WHERE  (e.day0 + (d.n - 1)) BETWEEN p_from AND p_to

  ORDER  BY 4, 6 NULLS FIRST, 1;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_worker_agenda(date, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_worker_agenda(date, date) TO authenticated;
