-- ══════════════════════════════════════════════════════════════
-- 0079 — Painel de admin para suporte, fase B (Resolver)
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (17/11/2026, Henrique).
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. support_cases e support_case_notes: casos de suporte (ajuda,
--      reporte, denúncia, contestação, reclamação, RGPD, eliminar conta)
--      com prazos de docs/SUPORTE.md, em dias úteis.
--   2. admin_notes: notas internas em qualquer ficha (pedido, pessoa).
--   3. job_reports.status, resolved_at, case_id: o reporte liga-se ao caso.
--   4. Moderação sem apagar: avaliações e fotos ocultas passam para
--      tabelas de arquivo (ratings_hidden, job_photos_hidden). Assim saem
--      de todas as médias, vistas e RPCs da app sem mexer em nenhuma, e
--      voltam com admin_restore_rating. Um trigger impede avaliar outra vez
--      o mesmo trabalho enquanto a avaliação estiver oculta.
--   5. Ações sobre pedidos: admin_cancel_job, admin_reopen_job,
--      admin_set_job_status. Avisam as pessoas com os tipos de aviso que a
--      app já conhece.
--   6. Leituras: admin_list_cases, admin_get_case, admin_list_reports,
--      admin_list_ratings, admin_list_actions, admin_list_notes.
--
-- Regras de sempre: cada admin_* chama assert_verified_admin() (admin_users
-- + aal2); nenhuma recebe o id do admin, quem chama é auth.uid(); toda a
-- mudança fica em admin_actions com motivo (lista fixa) e nota. Tabelas
-- novas com RLS ligada e sem policies.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Ajudas ───────────────────────────────────────────────────

-- Soma n dias úteis (segunda a sexta, hora de Lisboa) a um instante.
-- Feriados não contam como exceção: o prazo fica um pouco mais apertado,
-- nunca mais largo.
CREATE OR REPLACE FUNCTION public.add_business_days(p_from timestamptz, p_days integer)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_ts   timestamp := p_from AT TIME ZONE 'Europe/Lisbon';
  v_left integer   := GREATEST(COALESCE(p_days, 0), 0);
BEGIN
  WHILE v_left > 0 LOOP
    v_ts := v_ts + interval '1 day';
    IF extract(isodow FROM v_ts) < 6 THEN
      v_left := v_left - 1;
    END IF;
  END LOOP;
  RETURN v_ts AT TIME ZONE 'Europe/Lisbon';
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.add_business_days(timestamptz, integer) FROM PUBLIC, anon, authenticated;

-- Motivos fixos das ações de moderação (o painel mostra os rótulos).
CREATE OR REPLACE FUNCTION public.admin_assert_reason(p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN (
       'user_request', 'app_error', 'terms_violation', 'illegal_content',
       'personal_data', 'duplicate', 'other') THEN
    RAISE EXCEPTION 'Escolhe um motivo da lista.';
  END IF;
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreve uma nota com o que aconteceu (5 carateres ou mais).';
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_assert_reason(text, text) FROM PUBLIC, anon, authenticated;

-- Prazos por tipo de caso (docs/SUPORTE.md): (dias, úteis?).
CREATE OR REPLACE FUNCTION public.support_case_due(p_kind text, p_from timestamptz)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $function$
  SELECT CASE p_kind
    WHEN 'help'           THEN public.add_business_days(p_from, 1)
    WHEN 'report'         THEN public.add_business_days(p_from, 2)
    WHEN 'abuse'          THEN p_from + interval '7 days'
    WHEN 'appeal'         THEN public.add_business_days(p_from, 15)
    WHEN 'complaint'      THEN public.add_business_days(p_from, 15)
    WHEN 'gdpr'           THEN p_from + interval '1 month'
    WHEN 'delete_account' THEN p_from + interval '30 days'
  END
$function$;
REVOKE EXECUTE ON FUNCTION public.support_case_due(text, timestamptz) FROM PUBLIC, anon, authenticated;


-- ── 2. Casos de suporte ─────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS public.support_case_number_seq;

CREATE TABLE IF NOT EXISTS public.support_cases (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  number           integer     NOT NULL UNIQUE DEFAULT nextval('public.support_case_number_seq'),
  kind             text        NOT NULL,
  status           text        NOT NULL DEFAULT 'open',
  person_id        uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  job_id           uuid        REFERENCES public.job_requests(id) ON DELETE SET NULL,
  contact_email    text,
  summary          text        NOT NULL,
  decision         text,
  ack_due_at       timestamptz NOT NULL,
  due_at           timestamptz NOT NULL,
  first_reply_at   timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  closed_at        timestamptz,
  closed_by        uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER SEQUENCE public.support_case_number_seq OWNED BY public.support_cases.number;
ALTER TABLE public.support_cases DROP CONSTRAINT IF EXISTS support_cases_kind_check;
ALTER TABLE public.support_cases ADD CONSTRAINT support_cases_kind_check
  CHECK (kind IN ('help', 'report', 'abuse', 'appeal', 'complaint', 'gdpr', 'delete_account'));
ALTER TABLE public.support_cases DROP CONSTRAINT IF EXISTS support_cases_status_check;
ALTER TABLE public.support_cases ADD CONSTRAINT support_cases_status_check
  CHECK (status IN ('open', 'waiting_user', 'resolved'));
ALTER TABLE public.support_cases DROP CONSTRAINT IF EXISTS support_cases_text_check;
ALTER TABLE public.support_cases ADD CONSTRAINT support_cases_text_check
  CHECK (char_length(summary) <= 2000 AND char_length(COALESCE(decision, '')) <= 4000
         AND char_length(COALESCE(contact_email, '')) <= 320);
CREATE INDEX IF NOT EXISTS support_cases_open_idx
  ON public.support_cases (status, due_at);
CREATE INDEX IF NOT EXISTS support_cases_person_idx ON public.support_cases (person_id);
CREATE INDEX IF NOT EXISTS support_cases_job_idx ON public.support_cases (job_id);
ALTER TABLE public.support_cases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.support_case_notes (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id    uuid        NOT NULL REFERENCES public.support_cases(id) ON DELETE CASCADE,
  kind       text        NOT NULL DEFAULT 'internal',
  body       text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.support_case_notes DROP CONSTRAINT IF EXISTS support_case_notes_check;
ALTER TABLE public.support_case_notes ADD CONSTRAINT support_case_notes_check
  CHECK (kind IN ('internal', 'reply') AND char_length(body) BETWEEN 1 AND 8000);
CREATE INDEX IF NOT EXISTS support_case_notes_case_idx
  ON public.support_case_notes (case_id, created_at);
ALTER TABLE public.support_case_notes ENABLE ROW LEVEL SECURITY;

-- Notas internas em qualquer ficha (pedido, cliente, jardineiro).
CREATE TABLE IF NOT EXISTS public.admin_notes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id   uuid        NOT NULL,
  body        text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.admin_notes DROP CONSTRAINT IF EXISTS admin_notes_body_check;
ALTER TABLE public.admin_notes ADD CONSTRAINT admin_notes_body_check
  CHECK (char_length(body) BETWEEN 1 AND 4000);
CREATE INDEX IF NOT EXISTS admin_notes_target_idx ON public.admin_notes (target_id, created_at);
ALTER TABLE public.admin_notes ENABLE ROW LEVEL SECURITY;

-- Reporte ligado ao caso.
ALTER TABLE public.job_reports ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'new';
ALTER TABLE public.job_reports ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
ALTER TABLE public.job_reports ADD COLUMN IF NOT EXISTS case_id uuid
  REFERENCES public.support_cases(id) ON DELETE SET NULL;
ALTER TABLE public.job_reports DROP CONSTRAINT IF EXISTS job_reports_status_check;
ALTER TABLE public.job_reports ADD CONSTRAINT job_reports_status_check
  CHECK (status IN ('new', 'in_review', 'resolved', 'dismissed'));
CREATE INDEX IF NOT EXISTS job_reports_status_idx ON public.job_reports (status, created_at);

-- Quem usa a app não mexe nestas colunas (a policy de INSERT deixa o
-- utilizador escrever na linha que cria; aqui só valem os valores de
-- omissão).
CREATE OR REPLACE FUNCTION public.job_reports_lock_support_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.status      := 'new';
    NEW.resolved_at := NULL;
    NEW.case_id     := NULL;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_job_reports_lock_support_fields ON public.job_reports;
CREATE TRIGGER trg_job_reports_lock_support_fields
  BEFORE INSERT ON public.job_reports
  FOR EACH ROW EXECUTE FUNCTION public.job_reports_lock_support_fields();


-- ── 3. Arquivo de moderação ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.ratings_hidden (
  id            uuid        PRIMARY KEY,
  job_id        uuid        REFERENCES public.job_requests(id) ON DELETE CASCADE,
  rater_id      uuid,
  ratee_id      uuid,
  stars         integer     NOT NULL,
  comment       text,
  created_at    timestamptz,
  hidden_at     timestamptz NOT NULL DEFAULT now(),
  hidden_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  hidden_reason text        NOT NULL,
  hidden_note   text
);
CREATE INDEX IF NOT EXISTS ratings_hidden_key_idx
  ON public.ratings_hidden (job_id, rater_id, ratee_id);
ALTER TABLE public.ratings_hidden ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.job_photos_hidden (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id        uuid        NOT NULL REFERENCES public.job_requests(id) ON DELETE CASCADE,
  kind          text        NOT NULL,
  storage_path  text        NOT NULL,
  taken_at      timestamptz,
  hidden_at     timestamptz NOT NULL DEFAULT now(),
  hidden_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  hidden_reason text        NOT NULL,
  hidden_note   text
);
CREATE INDEX IF NOT EXISTS job_photos_hidden_job_idx ON public.job_photos_hidden (job_id);
ALTER TABLE public.job_photos_hidden ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.support_cases, public.support_case_notes, public.admin_notes,
              public.ratings_hidden, public.job_photos_hidden
  FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.support_case_number_seq FROM anon, authenticated;

-- Uma avaliação oculta não se volta a fazer no mesmo trabalho.
CREATE OR REPLACE FUNCTION public.block_rating_while_hidden()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM ratings_hidden h
             WHERE h.job_id = NEW.job_id AND h.rater_id = NEW.rater_id
               AND h.ratee_id = NEW.ratee_id) THEN
    RAISE EXCEPTION 'Já avaliaste este trabalho.';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.block_rating_while_hidden() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_block_rating_while_hidden ON public.ratings;
CREATE TRIGGER trg_block_rating_while_hidden
  BEFORE INSERT ON public.ratings
  FOR EACH ROW EXECUTE FUNCTION public.block_rating_while_hidden();


-- ── 4. Casos: criar, mudar, notas ───────────────────────────────

DROP FUNCTION IF EXISTS public.admin_case_create(text, text, uuid, uuid, uuid, text);
CREATE FUNCTION public.admin_case_create(
  p_kind          text,
  p_summary       text,
  p_person_id     uuid DEFAULT NULL,
  p_job_id        uuid DEFAULT NULL,
  p_report_id     uuid DEFAULT NULL,
  p_contact_email text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id      uuid;
  v_summary text := btrim(COALESCE(p_summary, ''));
  v_job     uuid := p_job_id;
  v_person  uuid := p_person_id;
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_kind IS NULL OR public.support_case_due(p_kind, now()) IS NULL THEN
    RAISE EXCEPTION 'Tipo de caso inválido.';
  END IF;
  IF v_summary = '' THEN
    RAISE EXCEPTION 'Escreve um resumo do caso.';
  END IF;
  IF p_report_id IS NOT NULL THEN
    SELECT COALESCE(v_job, r.job_id), COALESCE(v_person, r.reporter_id)
      INTO v_job, v_person
    FROM job_reports r WHERE r.id = p_report_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Reporte não encontrado.';
    END IF;
  END IF;
  IF v_person IS NOT NULL AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_person) THEN
    RAISE EXCEPTION 'Pessoa não encontrada.';
  END IF;
  IF v_job IS NOT NULL AND NOT EXISTS (SELECT 1 FROM job_requests WHERE id = v_job) THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;

  INSERT INTO support_cases (kind, person_id, job_id, contact_email, summary,
                             ack_due_at, due_at, created_by)
  VALUES (p_kind, v_person, v_job,
          NULLIF(btrim(COALESCE(p_contact_email, '')), ''), left(v_summary, 2000),
          public.add_business_days(now(), 1),
          public.support_case_due(p_kind, now()), auth.uid())
  RETURNING id INTO v_id;

  IF p_report_id IS NOT NULL THEN
    UPDATE job_reports SET status = 'in_review', case_id = v_id WHERE id = p_report_id;
  END IF;

  PERFORM public.admin_log('case_create', v_id, jsonb_strip_nulls(jsonb_build_object(
    'kind', p_kind, 'person_id', v_person, 'job_id', v_job, 'report_id', p_report_id)));
  IF v_job IS NOT NULL THEN
    PERFORM public.admin_log('case_create', v_job, jsonb_build_object('case_id', v_id));
  END IF;
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_case_create(text, text, uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_case_create(text, text, uuid, uuid, uuid, text) TO authenticated, service_role;

-- Muda o estado e/ou guarda a decisão. Fechar (resolved) exige decisão e
-- resolve o reporte ligado.
DROP FUNCTION IF EXISTS public.admin_case_update(uuid, text, text);
CREATE FUNCTION public.admin_case_update(
  p_case_id  uuid,
  p_status   text DEFAULT NULL,
  p_decision text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_case     support_cases;
  v_status   text;
  v_decision text;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT * INTO v_case FROM support_cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Caso não encontrado.';
  END IF;
  v_status   := COALESCE(p_status, v_case.status);
  v_decision := COALESCE(NULLIF(btrim(COALESCE(p_decision, '')), ''), v_case.decision);
  IF v_status NOT IN ('open', 'waiting_user', 'resolved') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;
  IF v_status = 'resolved' AND v_decision IS NULL THEN
    RAISE EXCEPTION 'Escreve a decisão antes de fechar o caso.';
  END IF;

  UPDATE support_cases
  SET status     = v_status,
      decision   = left(v_decision, 4000),
      updated_at = now(),
      closed_at  = CASE WHEN v_status = 'resolved' THEN COALESCE(closed_at, now()) END,
      closed_by  = CASE WHEN v_status = 'resolved' THEN COALESCE(closed_by, auth.uid()) END
  WHERE id = p_case_id;

  IF v_status = 'resolved' THEN
    UPDATE job_reports SET status = 'resolved', resolved_at = COALESCE(resolved_at, now())
    WHERE case_id = p_case_id AND status IN ('new', 'in_review');
  ELSE
    UPDATE job_reports SET status = 'in_review', resolved_at = NULL
    WHERE case_id = p_case_id AND status = 'resolved';
  END IF;

  PERFORM public.admin_log('case_update', p_case_id, jsonb_strip_nulls(jsonb_build_object(
    'from', v_case.status, 'to', v_status,
    'decision_changed', v_decision IS DISTINCT FROM v_case.decision)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_case_update(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_case_update(uuid, text, text) TO authenticated, service_role;

-- p_kind 'reply' = resposta enviada por email (colada aqui para ficar
-- registada); a primeira marca a confirmação de receção.
DROP FUNCTION IF EXISTS public.admin_case_add_note(uuid, text, text);
CREATE FUNCTION public.admin_case_add_note(
  p_case_id uuid,
  p_body    text,
  p_kind    text DEFAULT 'internal'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id   uuid;
  v_body text := btrim(COALESCE(p_body, ''));
BEGIN
  PERFORM public.assert_verified_admin();
  IF NOT EXISTS (SELECT 1 FROM support_cases WHERE id = p_case_id) THEN
    RAISE EXCEPTION 'Caso não encontrado.';
  END IF;
  IF p_kind NOT IN ('internal', 'reply') THEN
    RAISE EXCEPTION 'Tipo de nota inválido.';
  END IF;
  IF v_body = '' THEN
    RAISE EXCEPTION 'A nota está vazia.';
  END IF;

  INSERT INTO support_case_notes (case_id, kind, body, created_by)
  VALUES (p_case_id, p_kind, left(v_body, 8000), auth.uid())
  RETURNING id INTO v_id;

  UPDATE support_cases
  SET updated_at     = now(),
      first_reply_at = CASE WHEN p_kind = 'reply' THEN COALESCE(first_reply_at, now())
                            ELSE first_reply_at END
  WHERE id = p_case_id;

  PERFORM public.admin_log('case_note', p_case_id, jsonb_build_object('kind', p_kind));
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_case_add_note(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_case_add_note(uuid, text, text) TO authenticated, service_role;


-- ── 5. Casos: ler ───────────────────────────────────────────────
-- p_status NULL = abertos e à espera; 'all' = todos. Ordenados pelo prazo.

DROP FUNCTION IF EXISTS public.admin_list_cases(text, text, uuid, integer, integer);
CREATE FUNCTION public.admin_list_cases(
  p_status    text    DEFAULT NULL,
  p_kind      text    DEFAULT NULL,
  p_target_id uuid    DEFAULT NULL,
  p_limit     integer DEFAULT 50,
  p_offset    integer DEFAULT 0
)
RETURNS TABLE (
  case_id        uuid,
  number         integer,
  kind           text,
  status         text,
  summary        text,
  person_id      uuid,
  person_name    text,
  job_id         uuid,
  ack_due_at     timestamptz,
  due_at         timestamptz,
  first_reply_at timestamptz,
  created_at     timestamptz,
  closed_at      timestamptz,
  total_count    integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT c.id, c.number, c.kind, c.status, c.summary, c.person_id, p.full_name,
         c.job_id, c.ack_due_at, c.due_at, c.first_reply_at, c.created_at, c.closed_at,
         (count(*) OVER ())::integer
  FROM support_cases c
  LEFT JOIN profiles p ON p.id = c.person_id
  WHERE (CASE WHEN p_status IS NULL THEN c.status <> 'resolved'
              WHEN p_status = 'all' THEN true
              ELSE c.status = p_status END)
    AND (p_kind IS NULL OR c.kind = p_kind)
    AND (p_target_id IS NULL OR c.person_id = p_target_id OR c.job_id = p_target_id)
  ORDER BY CASE WHEN c.status = 'resolved' THEN 1 ELSE 0 END,
           CASE WHEN c.status = 'resolved' THEN NULL ELSE c.due_at END,
           c.closed_at DESC NULLS LAST
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_cases(text, text, uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_cases(text, text, uuid, integer, integer) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_get_case(uuid);
CREATE FUNCTION public.admin_get_case(p_case_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  IF NOT EXISTS (SELECT 1 FROM support_cases WHERE id = p_case_id) THEN
    RAISE EXCEPTION 'Caso não encontrado.';
  END IF;
  PERFORM public.admin_log('view_case', p_case_id, '{}'::jsonb);

  SELECT jsonb_build_object(
    'case_id',        c.id,
    'number',         c.number,
    'kind',           c.kind,
    'status',         c.status,
    'summary',        c.summary,
    'decision',       c.decision,
    'contact_email',  c.contact_email,
    'person_id',      c.person_id,
    'person_name',    p.full_name,
    'person_role',    p.role,
    'person_email',   u.email,
    'job_id',         c.job_id,
    'job_service',    (SELECT st.name FROM job_requests jr
                       JOIN service_types st ON st.id = jr.service_type_id
                       WHERE jr.id = c.job_id),
    'ack_due_at',     c.ack_due_at,
    'due_at',         c.due_at,
    'first_reply_at', c.first_reply_at,
    'created_at',     c.created_at,
    'closed_at',      c.closed_at,
    'reports',        COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id', r.id, 'description', r.description,
                        'status', r.status, 'created_at', r.created_at)
                        ORDER BY r.created_at)
                      FROM job_reports r WHERE r.case_id = c.id), '[]'::jsonb),
    'notes',          COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'id', n.id, 'kind', n.kind, 'body', n.body,
                        'created_at', n.created_at,
                        'author_email', au.email)
                        ORDER BY n.created_at)
                      FROM support_case_notes n
                      LEFT JOIN auth.users au ON au.id = n.created_by
                      WHERE n.case_id = c.id), '[]'::jsonb)
  ) INTO v_result
  FROM support_cases c
  LEFT JOIN profiles p   ON p.id = c.person_id
  LEFT JOIN auth.users u ON u.id = c.person_id
  WHERE c.id = p_case_id;
  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_case(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_case(uuid) TO authenticated, service_role;


-- ── 6. Reportes ─────────────────────────────────────────────────
-- p_status NULL = novos e em análise; 'all' = todos.

DROP FUNCTION IF EXISTS public.admin_list_reports(text, integer, integer);
CREATE FUNCTION public.admin_list_reports(
  p_status text    DEFAULT NULL,
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  report_id      uuid,
  job_id         uuid,
  service_name   text,
  reporter_id    uuid,
  reporter_name  text,
  reporter_role  text,
  description    text,
  status         text,
  case_id        uuid,
  case_number    integer,
  created_at     timestamptz,
  due_at         timestamptz,
  resolved_at    timestamptz,
  total_count    integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT r.id, r.job_id, st.name, r.reporter_id, p.full_name,
         CASE WHEN r.reporter_id = jr.client_id THEN 'client' ELSE 'worker' END,
         r.description, r.status, r.case_id, c.number, r.created_at,
         COALESCE(c.due_at, public.support_case_due('report', r.created_at)),
         r.resolved_at,
         (count(*) OVER ())::integer
  FROM job_reports r
  JOIN job_requests jr       ON jr.id = r.job_id
  LEFT JOIN service_types st ON st.id = jr.service_type_id
  LEFT JOIN profiles p       ON p.id = r.reporter_id
  LEFT JOIN support_cases c  ON c.id = r.case_id
  WHERE (CASE WHEN p_status IS NULL THEN r.status IN ('new', 'in_review')
              WHEN p_status = 'all' THEN true
              ELSE r.status = p_status END)
  ORDER BY CASE WHEN r.status IN ('new', 'in_review') THEN 0 ELSE 1 END, r.created_at
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_reports(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_reports(text, integer, integer) TO authenticated, service_role;

-- Fechar um reporte sem caso (ex.: sem fundamento). Com caso, fecha-se o caso.
DROP FUNCTION IF EXISTS public.admin_set_report_status(uuid, text, text);
CREATE FUNCTION public.admin_set_report_status(p_report_id uuid, p_status text, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_report job_reports;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT * INTO v_report FROM job_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reporte não encontrado.';
  END IF;
  IF p_status NOT IN ('new', 'in_review', 'resolved', 'dismissed') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;
  IF p_status IN ('resolved', 'dismissed') AND length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreve uma nota com a decisão (5 carateres ou mais).';
  END IF;

  UPDATE job_reports
  SET status = p_status,
      resolved_at = CASE WHEN p_status IN ('resolved', 'dismissed') THEN now() END
  WHERE id = p_report_id;

  PERFORM public.admin_log('report_status', v_report.job_id, jsonb_strip_nulls(jsonb_build_object(
    'report_id', p_report_id, 'from', v_report.status, 'to', p_status,
    'note', NULLIF(btrim(COALESCE(p_note, '')), ''))));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_set_report_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_report_status(uuid, text, text) TO authenticated, service_role;


-- ── 7. Ações sobre pedidos ──────────────────────────────────────

-- O aviso às propostas pendentes dizia sempre "O cliente cancelou". Com o
-- cancelamento pelo suporte passa a dizer quem foi. Resto igual à 0049.
CREATE OR REPLACE FUNCTION public.notify_proposal_closed_with_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_status    text;
  v_cancel_reason text;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
    SELECT status, cancel_reason INTO v_job_status, v_cancel_reason
    FROM job_requests WHERE id = NEW.job_id;

    IF v_job_status = 'cancelled' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido cancelado',
        CASE WHEN v_cancel_reason = 'support'
             THEN 'O suporte da ProJardim cancelou o pedido a que fizeste uma proposta.'
             ELSE 'O cliente cancelou o pedido a que fizeste uma proposta.' END,
        NEW.job_id, 'job_request');
    ELSIF v_job_status = 'no_response' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido fechado',
        'O pedido fechou sem o cliente escolher a tua proposta.',
        NEW.job_id, 'job_request');
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

-- Cancelar pelo suporte. Mesmo efeito do cancel_job (propostas pendentes
-- recusadas, equipa cancelada, avisos), sem as regras das 24 horas nem do
-- trabalho iniciado, e sem reabrir. cancelled_by fica vazio (o admin não
-- é cliente nem jardineiro) e cancel_reason = 'support'.
DROP FUNCTION IF EXISTS public.admin_cancel_job(uuid, text, text, text);
CREATE FUNCTION public.admin_cancel_job(
  p_job_id         uuid,
  p_reason         text,
  p_note           text,
  p_public_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests;
  v_worker uuid;
  v_msg    text := NULLIF(btrim(left(COALESCE(p_public_message, ''), 500)), '');
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed', 'awaiting_confirmation') THEN
    RAISE EXCEPTION 'Este pedido já está fechado.';
  END IF;
  v_worker := public.job_accepted_worker_id(p_job_id);

  UPDATE job_requests
  SET status               = 'cancelled',
      cancelled_by         = NULL,
      cancel_reason        = 'support',
      cancel_reason_detail = v_msg,
      cancelled_worker_id  = NULL,
      updated_at           = now()
  WHERE id = p_job_id;

  UPDATE job_proposals SET status = 'rejected', updated_at = now()
  WHERE job_id = p_job_id AND status = 'pending';

  UPDATE help_requests SET status = 'cancelled'
  WHERE job_id = p_job_id AND status <> 'cancelled';

  UPDATE help_acceptances SET status = 'rejected'
  WHERE help_request_id IN (SELECT id FROM help_requests WHERE job_id = p_job_id)
    AND status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado pelo suporte.', p_job_id, 'job_request'
  FROM help_acceptances ha
  JOIN help_requests hr ON hr.id = ha.help_request_id
  WHERE hr.job_id = p_job_id AND ha.status = 'accepted';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT uid, 'job_cancelled', 'Pedido cancelado pelo suporte',
         COALESCE(v_msg, 'O suporte da ProJardim cancelou este pedido. Se tiveres dúvidas, escreve para suporte@projardim.pt.'),
         p_job_id, 'job_request'
  FROM (SELECT v_job.client_id AS uid UNION SELECT v_worker) s
  WHERE uid IS NOT NULL;

  PERFORM public.admin_log('cancel_job', p_job_id, jsonb_strip_nulls(jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note), 'from', v_job.status,
    'public_message', v_msg)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_cancel_job(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_job(uuid, text, text, text) TO authenticated, service_role;

-- Reabrir um pedido que expirou sem resposta: volta a aberto por 48 horas,
-- visível a todos (um pedido direto deixa de estar reservado). Data fixa
-- já passada passa a flexível, como no cancel_job.
DROP FUNCTION IF EXISTS public.admin_reopen_job(uuid, text, text);
CREATE FUNCTION public.admin_reopen_job(p_job_id uuid, p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'no_response' THEN
    RAISE EXCEPTION 'Só se reabrem pedidos que expiraram sem resposta.';
  END IF;

  UPDATE job_requests
  SET status                   = 'open',
      expires_at               = now() + interval '48 hours',
      proposal_count           = 0,
      date_mode                = CASE WHEN date_mode = 'fixed'
                                       AND (preferred_date IS NULL OR preferred_date < today_pt())
                                      THEN 'flexible' ELSE date_mode END,
      preferred_date           = CASE WHEN date_mode = 'fixed'
                                       AND (preferred_date IS NULL OR preferred_date < today_pt())
                                      THEN NULL ELSE preferred_date END,
      direct_status            = CASE WHEN direct_status IS NULL THEN NULL ELSE 'released' END,
      direct_until             = NULL,
      direct_hold_reason       = NULL,
      followup_stage           = 0,
      no_proposals_nudged_at   = NULL,
      undated_expiry_warned_at = NULL,
      updated_at               = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto pelo suporte',
          'O teu pedido voltou a estar aberto a propostas durante 48 horas.',
          p_job_id, 'job_request');

  PERFORM public.admin_log('reopen_job', p_job_id, jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_reopen_job(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reopen_job(uuid, text, text) TO authenticated, service_role;

-- Corrigir o estado quando houve erro:
--   'completed'             a partir de confirmed ou awaiting_confirmation
--                           (o trabalho foi feito e ficou por fechar);
--   'awaiting_confirmation' a partir de completed (anular a confirmação
--                           automática: a cliente volta a ter 7 dias).
DROP FUNCTION IF EXISTS public.admin_set_job_status(uuid, text, text, text);
CREATE FUNCTION public.admin_set_job_status(
  p_job_id uuid,
  p_status text,
  p_reason text,
  p_note   text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests;
  v_worker uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  v_worker := public.job_accepted_worker_id(p_job_id);

  IF p_status = 'completed' THEN
    IF v_job.status NOT IN ('confirmed', 'awaiting_confirmation') THEN
      RAISE EXCEPTION 'Só se marca como concluído um trabalho confirmado ou à espera de confirmação.';
    END IF;
    UPDATE job_requests
    SET status         = 'completed',
        started_at     = COALESCE(started_at, now()),
        marked_done_at = COALESCE(marked_done_at, now()),
        updated_at     = now()
    WHERE id = p_job_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT uid, 'job_completed', 'Trabalho concluído',
           'O suporte da ProJardim marcou este trabalho como concluído.', p_job_id, 'job_request'
    FROM (SELECT v_job.client_id AS uid UNION SELECT v_worker) s
    WHERE uid IS NOT NULL;

  ELSIF p_status = 'awaiting_confirmation' THEN
    IF v_job.status <> 'completed' THEN
      RAISE EXCEPTION 'Só se anula a confirmação de um trabalho concluído.';
    END IF;
    UPDATE job_requests
    SET status                        = 'awaiting_confirmation',
        marked_done_at                = now(),
        confirmation_reminder_sent_at = NULL,
        updated_at                    = now()
    WHERE id = p_job_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_marked_done', 'Confirma o trabalho',
            'O suporte da ProJardim voltou a pôr este trabalho à espera da tua confirmação. Tens 7 dias.',
            p_job_id, 'job_request');
    IF v_worker IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker, 'support_notice', 'Trabalho à espera de confirmação',
              'O suporte da ProJardim voltou a pôr este trabalho à espera da confirmação da cliente.',
              p_job_id, 'job_request');
    END IF;
  ELSE
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  PERFORM public.admin_log('set_job_status', p_job_id, jsonb_build_object(
    'from', v_job.status, 'to', p_status, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text, text) TO authenticated, service_role;


-- ── 8. Moderação ────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_hide_rating(uuid, text, text);
CREATE FUNCTION public.admin_hide_rating(p_rating_id uuid, p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rating ratings;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_rating FROM ratings WHERE id = p_rating_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avaliação não encontrada (pode já estar oculta).';
  END IF;

  INSERT INTO ratings_hidden (id, job_id, rater_id, ratee_id, stars, comment, created_at,
                              hidden_by, hidden_reason, hidden_note)
  VALUES (v_rating.id, v_rating.job_id, v_rating.rater_id, v_rating.ratee_id,
          v_rating.stars, v_rating.comment, v_rating.created_at,
          auth.uid(), p_reason, btrim(p_note));
  DELETE FROM ratings WHERE id = p_rating_id;

  IF v_rating.rater_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_rating.rater_id, 'support_notice', 'Avaliação ocultada',
            'O suporte da ProJardim ocultou uma avaliação tua por ' || CASE p_reason
              WHEN 'terms_violation' THEN 'não cumprir os Termos de Utilização'
              WHEN 'illegal_content' THEN 'conter conteúdo ilegal'
              WHEN 'personal_data'   THEN 'conter dados pessoais'
              WHEN 'user_request'    THEN 'pedido teu'
              ELSE 'decisão do suporte' END
            || '. Se não concordares, responde para suporte@projardim.pt nos próximos 6 meses.',
            v_rating.job_id, 'job_request');
  END IF;

  PERFORM public.admin_log('hide_rating', COALESCE(v_rating.job_id, p_rating_id), jsonb_build_object(
    'rating_id', p_rating_id, 'reason', p_reason, 'note', btrim(p_note),
    'stars', v_rating.stars, 'rater_id', v_rating.rater_id, 'ratee_id', v_rating.ratee_id));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_hide_rating(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_hide_rating(uuid, text, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_restore_rating(uuid, text);
CREATE FUNCTION public.admin_restore_rating(p_rating_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hidden ratings_hidden;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreve uma nota com o motivo (5 carateres ou mais).';
  END IF;
  SELECT * INTO v_hidden FROM ratings_hidden WHERE id = p_rating_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avaliação oculta não encontrada.';
  END IF;

  DELETE FROM ratings_hidden WHERE id = p_rating_id;
  INSERT INTO ratings (id, job_id, rater_id, ratee_id, stars, comment, created_at)
  VALUES (v_hidden.id, v_hidden.job_id, v_hidden.rater_id, v_hidden.ratee_id,
          v_hidden.stars, v_hidden.comment, v_hidden.created_at);

  PERFORM public.admin_log('restore_rating', COALESCE(v_hidden.job_id, p_rating_id), jsonb_build_object(
    'rating_id', p_rating_id, 'note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_restore_rating(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_restore_rating(uuid, text) TO authenticated, service_role;

-- Ocultar uma foto do pedido (do cliente) ou de antes/depois/conclusão
-- (do jardineiro). O ficheiro fica no Storage; só deixa de aparecer na app.
DROP FUNCTION IF EXISTS public.admin_hide_photo(uuid, text, text, text);
CREATE FUNCTION public.admin_hide_photo(
  p_job_id       uuid,
  p_storage_path text,
  p_reason       text,
  p_note         text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job   job_requests;
  v_kind  text;
  v_taken timestamptz;
  v_owner uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;

  IF EXISTS (SELECT 1 FROM job_photos WHERE job_id = p_job_id AND storage_path = p_storage_path) THEN
    v_kind := 'request';
    SELECT min(created_at) INTO v_taken FROM job_photos
    WHERE job_id = p_job_id AND storage_path = p_storage_path;
    DELETE FROM job_photos WHERE job_id = p_job_id AND storage_path = p_storage_path;
    v_owner := v_job.client_id;
  ELSIF p_storage_path = ANY (COALESCE(v_job.before_photo_paths, '{}')) THEN
    v_kind := 'before';
    v_taken := v_job.started_at;
    UPDATE job_requests SET before_photo_paths = array_remove(before_photo_paths, p_storage_path)
    WHERE id = p_job_id;
  ELSIF p_storage_path = ANY (COALESCE(v_job.after_photo_paths, '{}')) THEN
    v_kind := 'after';
    v_taken := v_job.marked_done_at;
    UPDATE job_requests SET after_photo_paths = array_remove(after_photo_paths, p_storage_path)
    WHERE id = p_job_id;
  ELSIF v_job.completion_photo_path = p_storage_path THEN
    v_kind := 'completion';
    v_taken := v_job.marked_done_at;
    UPDATE job_requests SET completion_photo_path = NULL WHERE id = p_job_id;
  ELSE
    RAISE EXCEPTION 'Foto não encontrada neste pedido.';
  END IF;
  v_owner := COALESCE(v_owner, public.job_accepted_worker_id(p_job_id));

  INSERT INTO job_photos_hidden (job_id, kind, storage_path, taken_at,
                                 hidden_by, hidden_reason, hidden_note)
  VALUES (p_job_id, v_kind, p_storage_path, v_taken, auth.uid(), p_reason, btrim(p_note));

  IF v_owner IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_owner, 'support_notice', 'Foto ocultada',
            'O suporte da ProJardim ocultou uma foto deste pedido. Se não concordares, responde para suporte@projardim.pt nos próximos 6 meses.',
            p_job_id, 'job_request');
  END IF;

  PERFORM public.admin_log('hide_photo', p_job_id, jsonb_build_object(
    'kind', v_kind, 'path', p_storage_path, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_hide_photo(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_hide_photo(uuid, text, text, text) TO authenticated, service_role;

-- Avaliações para moderar: as visíveis e as ocultas.
DROP FUNCTION IF EXISTS public.admin_list_ratings(integer, boolean, boolean, integer, integer);
CREATE FUNCTION public.admin_list_ratings(
  p_stars        integer DEFAULT NULL,
  p_hidden       boolean DEFAULT false,
  p_with_comment boolean DEFAULT NULL,
  p_limit        integer DEFAULT 50,
  p_offset       integer DEFAULT 0
)
RETURNS TABLE (
  rating_id     uuid,
  job_id        uuid,
  rater_id      uuid,
  rater_name    text,
  ratee_id      uuid,
  ratee_name    text,
  stars         integer,
  comment       text,
  created_at    timestamptz,
  hidden        boolean,
  hidden_at     timestamptz,
  hidden_reason text,
  total_count   integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  WITH rows AS (
    SELECT r.id, r.job_id, r.rater_id, r.ratee_id, r.stars, r.comment, r.created_at,
           false AS is_hidden, NULL::timestamptz AS h_at, NULL::text AS h_reason
    FROM ratings r WHERE NOT COALESCE(p_hidden, false)
    UNION ALL
    SELECT h.id, h.job_id, h.rater_id, h.ratee_id, h.stars, h.comment, h.created_at,
           true, h.hidden_at, h.hidden_reason
    FROM ratings_hidden h WHERE COALESCE(p_hidden, false)
  )
  SELECT x.id, x.job_id, x.rater_id, a.full_name, x.ratee_id, b.full_name,
         x.stars, x.comment, x.created_at, x.is_hidden, x.h_at, x.h_reason,
         (count(*) OVER ())::integer
  FROM rows x
  LEFT JOIN profiles a ON a.id = x.rater_id
  LEFT JOIN profiles b ON b.id = x.ratee_id
  WHERE (p_stars IS NULL OR x.stars = p_stars)
    AND (p_with_comment IS NULL
         OR (btrim(COALESCE(x.comment, '')) <> '') = p_with_comment)
  ORDER BY COALESCE(x.h_at, x.created_at) DESC
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_ratings(integer, boolean, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_ratings(integer, boolean, boolean, integer, integer) TO authenticated, service_role;


-- ── 9. Notas internas ───────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_add_note(uuid, text);
CREATE FUNCTION public.admin_add_note(p_target_id uuid, p_body text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id   uuid;
  v_body text := btrim(COALESCE(p_body, ''));
BEGIN
  PERFORM public.assert_verified_admin();
  IF v_body = '' THEN
    RAISE EXCEPTION 'A nota está vazia.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM job_requests WHERE id = p_target_id)
     AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Ficha não encontrada.';
  END IF;
  INSERT INTO admin_notes (target_id, body, created_by)
  VALUES (p_target_id, left(v_body, 4000), auth.uid())
  RETURNING id INTO v_id;
  PERFORM public.admin_log('add_note', p_target_id, '{}'::jsonb);
  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_add_note(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_add_note(uuid, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_list_notes(uuid);
CREATE FUNCTION public.admin_list_notes(p_target_id uuid)
RETURNS TABLE (note_id uuid, body text, created_at timestamptz, author_email text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT n.id, n.body, n.created_at, u.email::text
  FROM admin_notes n
  LEFT JOIN auth.users u ON u.id = n.created_by
  WHERE n.target_id = p_target_id
  ORDER BY n.created_at DESC;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_notes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_notes(uuid) TO authenticated, service_role;


-- ── 10. Registo ─────────────────────────────────────────────────
-- Todas as admin_actions, mais recentes primeiro. p_include_reads = false
-- esconde as consultas (pesquisas, fichas abertas) e deixa só as mudanças.

DROP FUNCTION IF EXISTS public.admin_list_actions(text, uuid, boolean, integer, integer);
CREATE FUNCTION public.admin_list_actions(
  p_action        text    DEFAULT NULL,
  p_target_id     uuid    DEFAULT NULL,
  p_include_reads boolean DEFAULT true,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0
)
RETURNS TABLE (
  action_id   uuid,
  admin_email text,
  action      text,
  target_id   uuid,
  details     jsonb,
  created_at  timestamptz,
  total_count integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT a.id, u.email::text, a.action, a.target_id, a.details, a.created_at,
         (count(*) OVER ())::integer
  FROM admin_actions a
  LEFT JOIN auth.users u ON u.id = a.admin_id
  WHERE (p_action IS NULL OR a.action = p_action)
    AND (p_target_id IS NULL OR a.target_id = p_target_id)
    AND (COALESCE(p_include_reads, true)
         OR NOT (a.action LIKE 'view\_%' OR a.action IN ('search', 'reveal_phone', 'reveal_address')))
  ORDER BY a.created_at DESC
  LIMIT  LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_actions(text, uuid, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_actions(text, uuid, boolean, integer, integer) TO authenticated, service_role;
