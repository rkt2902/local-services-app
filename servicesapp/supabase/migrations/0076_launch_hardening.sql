-- 0076_launch_hardening.sql
-- NOVA, NÃO APLICADA. Aplicar no SQL Editor depois da 0075 (fazer um dump antes).
--
-- Achados da auditoria pré-lançamento de 13/11
-- (docs/audits/2026-11-13/remediation_plan.md):
--
--   AUD-20  profiles.phone passa a ter de parecer um telefone também na BD
--           (a app já valida; pela API aceitava "1"). NOT VALID: os valores
--           antigos não são verificados, só os novos e os que mudarem.
--   AUD-21  índices nas chaves estrangeiras lidas pelos crons e pela
--           eliminação de conta.
--   AUD-29  tira o TRUNCATE dos papéis da API (o PostgREST não o expõe, mas
--           não há razão para o terem).
--
-- Nenhuma função muda. Pode correr duas vezes.

-- ── AUD-20 ──────────────────────────────────────────────────────
-- Mesma regra larga do phone_utils.dart: sem espaços, hífenes, pontos,
-- parênteses e o "+", só dígitos, entre 8 e 15 (E.164). Vazio ou NULL
-- continuam a passar (contas sociais sem telefone, contas eliminadas).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_phone_format'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_phone_format CHECK (
        phone IS NULL
        OR btrim(phone) = ''
        OR regexp_replace(phone, '[\s\-().+]', '', 'g') ~ '^\d{8,15}$'
      ) NOT VALID;
  END IF;
END $$;

-- ── AUD-21 ──────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS job_requests_direct_worker_id_idx
  ON public.job_requests (direct_worker_id) WHERE direct_worker_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS job_requests_direct_card_worker_id_idx
  ON public.job_requests (direct_card_worker_id) WHERE direct_card_worker_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS job_requests_direct_source_job_id_idx
  ON public.job_requests (direct_source_job_id) WHERE direct_source_job_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS job_requests_service_type_id_idx
  ON public.job_requests (service_type_id);
CREATE INDEX IF NOT EXISTS job_requests_reopened_from_idx
  ON public.job_requests (reopened_from) WHERE reopened_from IS NOT NULL;
CREATE INDEX IF NOT EXISTS job_reports_reporter_id_idx
  ON public.job_reports (reporter_id);
CREATE INDEX IF NOT EXISTS worker_card_visits_visitor_id_idx
  ON public.worker_card_visits (visitor_id) WHERE visitor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS client_referrals_visit_id_idx
  ON public.client_referrals (visit_id);

-- ── AUD-29 ──────────────────────────────────────────────────────
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
  LOOP
    EXECUTE format('REVOKE TRUNCATE ON public.%I FROM anon, authenticated', r.relname);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
