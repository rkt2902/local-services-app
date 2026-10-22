-- ══════════════════════════════════════════════════════════════
-- 0058 — Propostas por hora ou valor total, validade e dias de trabalho
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, DEPOIS da 0057
-- (redefine get_worker_job_board a partir da versão da 0056 e usa
-- today_pt() da 0054). Pode correr-se mais do que uma vez sem erro.
--
-- Design A6 (22/10):
--
-- 1. Uma proposta é por hora (como até agora) ou de valor total fechado.
--    O tipo vive em job_proposals.pricing_mode; não é estado da proposta
--    nem do pedido. No valor total, `total_price` é o que o cliente paga,
--    mesmo que o trabalho demore mais. `hourly_rate` continua NOT NULL:
--    nas propostas de valor total guarda uma hora de referência (a do
--    perfil do jardineiro ou o total a dividir pelas horas estimadas da
--    equipa), só para a sugestão de pagamento aos ajudantes. O cliente
--    nunca a vê.
-- 2. "O que inclui": lista de opções na tabela proposal_include_options
--    (a app não as tem fixas) e o texto livre em `notes`.
-- 3. Duração em horas (estimated_hours_*) ou em dias (estimated_days_*).
-- 4. Validade do orçamento (`valid_until`, até 60 dias). Aceitar uma
--    proposta expirada falha na BD (trigger), mesmo que a app deixe.
--    get_pending_proposals_for_job devolve `is_expired` calculado aqui.
-- 5. Trabalho de vários dias: job_work_days guarda o início e o fim de
--    cada dia. O dia 1 nasce com start_job; finish_work_day e
--    start_work_day fecham e abrem os seguintes; mark_job_done fecha o dia
--    aberto. O tempo registado é a soma dos dias.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Opções de "O que inclui" ─────────────────────────────────

CREATE TABLE IF NOT EXISTS public.proposal_include_options (
  slug       text    PRIMARY KEY,
  label      text    NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  active     boolean NOT NULL DEFAULT true
);

ALTER TABLE public.proposal_include_options ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Opcoes de inclui visiveis" ON public.proposal_include_options;
CREATE POLICY "Opcoes de inclui visiveis"
  ON public.proposal_include_options FOR SELECT TO authenticated
  USING (true);

INSERT INTO public.proposal_include_options (slug, label, sort_order) VALUES
  ('material',      'Material',            10),
  ('waste_removal', 'Remoção de resíduos', 20),
  ('travel',        'Deslocação',          30),
  ('machinery',     'Máquinas',            40)
ON CONFLICT (slug) DO NOTHING;


-- ── 2. Colunas novas em job_proposals ───────────────────────────

ALTER TABLE public.job_proposals
  ADD COLUMN IF NOT EXISTS pricing_mode        text    NOT NULL DEFAULT 'hourly',
  ADD COLUMN IF NOT EXISTS total_price         numeric,
  ADD COLUMN IF NOT EXISTS includes            text[]  NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS estimated_days_min  integer,
  ADD COLUMN IF NOT EXISTS estimated_days_max  integer,
  ADD COLUMN IF NOT EXISTS valid_until         date;

ALTER TABLE public.job_proposals
  DROP CONSTRAINT IF EXISTS job_proposals_pricing_mode_check,
  DROP CONSTRAINT IF EXISTS job_proposals_total_price_check,
  DROP CONSTRAINT IF EXISTS job_proposals_days_check;

ALTER TABLE public.job_proposals
  ADD CONSTRAINT job_proposals_pricing_mode_check
    CHECK (pricing_mode IN ('hourly', 'fixed_total')),
  ADD CONSTRAINT job_proposals_total_price_check
    CHECK (pricing_mode <> 'fixed_total' OR (total_price IS NOT NULL AND total_price > 0)),
  ADD CONSTRAINT job_proposals_days_check
    CHECK ((estimated_days_min IS NULL OR estimated_days_min >= 1)
       AND (estimated_days_max IS NULL OR estimated_days_max >= COALESCE(estimated_days_min, 1)));


-- ── 3. create_proposal com tipo de preço, inclui, dias e validade ──
-- Parâmetros novos no fim, todos com DEFAULT: a app antiga continua a
-- funcionar. A assinatura muda, por isso DROP explícito da versão 0044.

DROP FUNCTION IF EXISTS public.create_proposal(
  uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean
);

CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_hourly_rate                numeric  DEFAULT NULL,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false,
  p_pricing_mode               text     DEFAULT 'hourly',
  p_total_price                numeric  DEFAULT NULL,
  p_includes                   text[]   DEFAULT '{}',
  p_estimated_days_min         integer  DEFAULT NULL,
  p_estimated_days_max         integer  DEFAULT NULL,
  p_valid_until                date     DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job         job_requests%ROWTYPE;
  v_mode        text := COALESCE(p_pricing_mode, 'hourly');
  v_rate        numeric;
  v_includes    text[];
  v_hours       numeric;
  v_team        numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM worker_profiles WHERE profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Só jardineiros podem enviar propostas.';
  END IF;

  IF v_mode NOT IN ('hourly', 'fixed_total') THEN
    RAISE EXCEPTION 'Tipo de preço inválido.';
  END IF;

  IF p_people_needed IS NULL OR p_people_needed < 1 THEN
    RAISE EXCEPTION 'Número de pessoas inválido.';
  END IF;

  IF p_estimated_days_min IS NOT NULL AND p_estimated_days_min < 1
     OR p_estimated_days_max IS NOT NULL
        AND p_estimated_days_max < COALESCE(p_estimated_days_min, 1) THEN
    RAISE EXCEPTION 'Duração em dias inválida.';
  END IF;

  IF p_valid_until IS NOT NULL
     AND (p_valid_until < today_pt() OR p_valid_until > today_pt() + 60) THEN
    RAISE EXCEPTION 'A validade do orçamento tem de ser entre hoje e daqui a 60 dias.';
  END IF;

  -- Só opções ativas, sem repetidas.
  SELECT COALESCE(array_agg(DISTINCT o.slug), '{}')
  INTO   v_includes
  FROM   unnest(COALESCE(p_includes, '{}')) AS s(slug)
  JOIN   proposal_include_options o ON o.slug = s.slug AND o.active;

  IF cardinality(v_includes) <> cardinality(ARRAY(
       SELECT DISTINCT s FROM unnest(COALESCE(p_includes, '{}')) AS s)) THEN
    RAISE EXCEPTION 'Opção de "o que inclui" inválida.';
  END IF;

  IF v_mode = 'hourly' THEN
    IF p_hourly_rate IS NULL OR p_hourly_rate <= 0 THEN
      RAISE EXCEPTION 'O preço por hora tem de ser maior que zero.';
    END IF;
    v_rate := p_hourly_rate;
  ELSE
    IF p_total_price IS NULL OR p_total_price <= 0 THEN
      RAISE EXCEPTION 'Indica o valor total da proposta.';
    END IF;
    -- Hora de referência, só para a sugestão aos ajudantes: a do perfil
    -- ou o total a dividir pelas horas da equipa (8 h por dia).
    SELECT NULLIF(default_hourly_rate, 0) INTO v_rate
    FROM   worker_profiles WHERE profile_id = auth.uid();
    IF v_rate IS NULL OR v_rate <= 0 THEN
      v_hours := COALESCE(p_estimated_hours_max, p_estimated_hours_min,
                          p_estimated_days_max * 8, p_estimated_days_min * 8, 8);
      v_team  := 1 + (p_people_needed - 1)
                     * CASE WHEN COALESCE(p_helpers_equipment_required, false)
                            THEN 1 ELSE 0.75 END;
      v_rate  := GREATEST(round(p_total_price / (v_hours * v_team), 2), 0.01);
    END IF;
  END IF;

  SELECT * INTO v_job
  FROM   job_requests
  WHERE  id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;
  IF v_job.client_id = auth.uid() THEN
    RAISE EXCEPTION 'Não podes enviar proposta para o teu próprio pedido.';
  END IF;
  IF auth.uid() = ANY(v_job.excluded_worker_ids) THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    pricing_mode, total_price, includes,
    estimated_days_min, estimated_days_max, valid_until,
    status
  ) VALUES (
    p_job_id, auth.uid(), v_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
    v_mode,
    CASE WHEN v_mode = 'fixed_total' THEN p_total_price END,
    v_includes,
    p_estimated_days_min, p_estimated_days_max, p_valid_until,
    'pending'
  )
  RETURNING id INTO v_proposal_id;

  UPDATE job_requests
  SET proposal_count = proposal_count + 1,
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'proposal_received',
    'Nova proposta recebida',
    'Um jardineiro enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_proposal(
  uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean,
  text, numeric, text[], integer, integer, date
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_proposal(
  uuid, numeric, numeric, numeric, integer, text, date, text, boolean, boolean,
  text, numeric, text[], integer, integer, date
) TO authenticated, service_role;


-- ── 4. Proposta expirada não pode ser aceite ────────────────────
-- Trigger em vez de redefinir accept_proposal: cobre qualquer caminho que
-- passe a proposta a `accepted`.

CREATE OR REPLACE FUNCTION public.block_expired_proposal_accept()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'accepted'
     AND NEW.valid_until IS NOT NULL AND NEW.valid_until < today_pt() THEN
    RAISE EXCEPTION 'Este orçamento expirou e já não pode ser aceite.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_proposal_block_expired_accept ON public.job_proposals;
CREATE TRIGGER trg_job_proposal_block_expired_accept
  BEFORE UPDATE OF status ON public.job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.block_expired_proposal_accept();


-- ── 5. get_pending_proposals_for_job com os campos novos ─────────
-- RETURNS TABLE muda de forma: DROP explícito antes de recriar.

DROP FUNCTION IF EXISTS public.get_pending_proposals_for_job(uuid);

CREATE FUNCTION public.get_pending_proposals_for_job(p_job_id uuid)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  worker_id                 uuid,
  hourly_rate               numeric,
  estimated_hours_min       numeric,
  estimated_hours_max       numeric,
  people_needed             integer,
  helpers_equipment_required boolean,
  notes                     text,
  status                    text,
  scheduled_date            date,
  scheduled_time            time,
  scheduled_flexible        boolean,
  created_at                timestamptz,
  worker_name               text,
  worker_avatar_url         text,
  pricing_mode              text,
  total_price               numeric,
  includes                  text[],
  estimated_days_min        integer,
  estimated_days_max        integer,
  valid_until               date,
  is_expired                boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    jp.id, jp.job_id, jp.worker_id, jp.hourly_rate, jp.estimated_hours_min,
    jp.estimated_hours_max, jp.people_needed, jp.helpers_equipment_required,
    jp.notes, jp.status, jp.scheduled_date, jp.scheduled_time,
    jp.scheduled_flexible, jp.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url,
    jp.pricing_mode, jp.total_price, jp.includes,
    jp.estimated_days_min, jp.estimated_days_max, jp.valid_until,
    (jp.valid_until IS NOT NULL AND jp.valid_until < today_pt()) AS is_expired
  FROM   job_proposals jp
  JOIN   profiles      p ON p.id = jp.worker_id
  WHERE  jp.job_id = p_job_id
    AND  jp.status = 'pending'
    AND  EXISTS (
      SELECT 1 FROM job_requests jr
      WHERE jr.id = jp.job_id AND jr.client_id = auth.uid()
    )
  ORDER BY jp.created_at ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_pending_proposals_for_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_pending_proposals_for_job(uuid) TO authenticated, service_role;


-- ── 6. get_worker_job_board com o tipo de preço ─────────────────
-- Igual à 0056, com pricing_mode e total_price no fim (o cartão mostra
-- "450 €" em vez de "25 €/h"). RETURNS TABLE muda: DROP explícito.

DROP FUNCTION IF EXISTS public.get_worker_job_board(text, integer, integer);

CREATE FUNCTION public.get_worker_job_board(
  p_tab       text,
  p_page      integer DEFAULT 0,
  p_page_size integer DEFAULT 20
)
RETURNS TABLE(
  entry_id             uuid,
  role                 text,
  job_id               uuid,
  service_type_name    text,
  person_name          text,
  address_text         text,
  preferred_date       date,
  confirmed_date       date,
  confirmed_time       time,
  confirmed_flexible   boolean,
  hourly_rate          numeric,
  estimated_hours_min  numeric,
  estimated_hours_max  numeric,
  agreed_rate          numeric,
  status               text,
  created_at           timestamptz,
  job_status           text,
  total_count          bigint,
  service_type_id      uuid,
  location_area        text,
  marked_done_at       timestamptz,
  cancel_reason        text,
  cancelled_by_client  boolean,
  cancelled_by_me      boolean,
  job_updated_at       timestamptz,
  started_at           timestamptz,
  people_needed        integer,
  helpers_equipment_required boolean,
  pricing_mode         text,
  total_price          numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH combined AS (
    -- Fonte A: papel de responsável (job_proposals)
    SELECT
      jp.id                    AS entry_id,
      'responsible'::text      AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      cp.full_name             AS person_name,
      CASE WHEN jp.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      jr.preferred_date        AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      jp.hourly_rate           AS hourly_rate,
      jp.estimated_hours_min   AS estimated_hours_min,
      jp.estimated_hours_max   AS estimated_hours_max,
      NULL::numeric            AS agreed_rate,
      jp.status                AS status,
      jp.created_at            AS created_at,
      jr.status                AS job_status,
      GREATEST(jr.updated_at, jp.updated_at) AS job_updated_at,
      jr.service_type_id       AS service_type_id,
      public.job_area_label(jr.location_area) AS location_area,
      jr.marked_done_at        AS marked_done_at,
      jr.cancel_reason         AS cancel_reason,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = jr.client_id) AS cancelled_by_client,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = auth.uid())   AS cancelled_by_me,
      jr.started_at            AS started_at,
      jp.people_needed         AS people_needed,
      jp.helpers_equipment_required AS helpers_equipment_required,
      jp.pricing_mode          AS pricing_mode,
      jp.total_price           AS total_price,
      CASE
        WHEN jp.status = 'pending' AND jr.status = 'open' THEN 'pending'
        WHEN jp.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN jp.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'completed'
      END AS bucket
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    JOIN   service_types st ON st.id = jr.service_type_id
    JOIN   profiles      cp ON cp.id = jr.client_id
    WHERE  jp.worker_id = auth.uid()

    UNION ALL

    -- Fonte B: papel de ajudante (help_acceptances)
    SELECT
      ha.id                    AS entry_id,
      'helper'::text           AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      pp.full_name             AS person_name,
      CASE WHEN ha.status = 'accepted' THEN jr.address_text
           ELSE public.job_area_label(jr.location_area)
      END                      AS address_text,
      NULL::date               AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      NULL::numeric            AS hourly_rate,
      NULL::numeric            AS estimated_hours_min,
      NULL::numeric            AS estimated_hours_max,
      ha.agreed_rate           AS agreed_rate,
      ha.status                AS status,
      ha.created_at            AS created_at,
      jr.status                AS job_status,
      jr.updated_at            AS job_updated_at,
      jr.service_type_id       AS service_type_id,
      public.job_area_label(jr.location_area) AS location_area,
      jr.marked_done_at        AS marked_done_at,
      jr.cancel_reason         AS cancel_reason,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = jr.client_id) AS cancelled_by_client,
      (jr.cancelled_by IS NOT NULL AND jr.cancelled_by = auth.uid())   AS cancelled_by_me,
      jr.started_at            AS started_at,
      1                        AS people_needed,
      false                    AS helpers_equipment_required,
      'hourly'::text           AS pricing_mode,
      NULL::numeric            AS total_price,
      CASE
        WHEN ha.status = 'pending' THEN 'pending'
        WHEN ha.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN ha.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE 'completed'
      END AS bucket
    FROM   help_acceptances ha
    JOIN   help_requests hr  ON hr.id = ha.help_request_id
    JOIN   job_requests  jr  ON jr.id = hr.job_id
    JOIN   service_types st  ON st.id = jr.service_type_id
    JOIN   job_proposals jpp ON jpp.id = hr.proposal_id
    JOIN   profiles      pp  ON pp.id  = jpp.worker_id
    WHERE  ha.worker_id = auth.uid()
  )
  SELECT
    entry_id, role, job_id, service_type_name, person_name, address_text,
    preferred_date, confirmed_date, confirmed_time, confirmed_flexible,
    hourly_rate, estimated_hours_min, estimated_hours_max, agreed_rate,
    status, created_at, job_status,
    COUNT(*) OVER ()::bigint AS total_count,
    service_type_id, location_area, marked_done_at, cancel_reason,
    cancelled_by_client, cancelled_by_me, job_updated_at, started_at,
    people_needed, helpers_equipment_required, pricing_mode, total_price
  FROM combined
  WHERE bucket = p_tab
  ORDER BY
    CASE WHEN p_tab = 'scheduled' THEN confirmed_date END ASC NULLS LAST,
    CASE WHEN p_tab = 'scheduled' THEN confirmed_time END ASC NULLS LAST,
    CASE WHEN p_tab = 'completed' THEN job_updated_at END DESC NULLS LAST,
    CASE WHEN p_tab = 'pending'   THEN created_at     END DESC NULLS LAST,
    entry_id
  LIMIT p_page_size OFFSET (p_page * p_page_size);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_worker_job_board(text, integer, integer) TO authenticated, service_role;


-- ── 7. Dias de trabalho ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.job_work_days (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id      uuid        NOT NULL REFERENCES public.job_requests(id) ON DELETE CASCADE,
  day_number  integer     NOT NULL CHECK (day_number >= 1),
  started_at  timestamptz NOT NULL,
  ended_at    timestamptz,
  CONSTRAINT job_work_days_unique_day UNIQUE (job_id, day_number),
  CONSTRAINT job_work_days_order CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- Só um dia aberto de cada vez.
CREATE UNIQUE INDEX IF NOT EXISTS job_work_days_one_open
  ON public.job_work_days (job_id) WHERE ended_at IS NULL;

-- Sem policies: leitura e escrita só pelas funções abaixo.
ALTER TABLE public.job_work_days ENABLE ROW LEVEL SECURITY;

-- Dia 1 nasce com start_job (started_at preenchido pela primeira vez) e o
-- dia aberto fecha quando o trabalho passa a awaiting_confirmation.
CREATE OR REPLACE FUNCTION public.sync_job_work_days()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.started_at IS NOT NULL AND OLD.started_at IS NULL THEN
    INSERT INTO job_work_days (job_id, day_number, started_at)
    VALUES (NEW.id, 1, NEW.started_at)
    ON CONFLICT (job_id, day_number) DO NOTHING;
  END IF;

  IF NEW.status <> OLD.status AND NEW.status IN ('awaiting_confirmation', 'completed', 'cancelled') THEN
    UPDATE job_work_days
    SET    ended_at = COALESCE(NEW.marked_done_at, now())
    WHERE  job_id = NEW.id AND ended_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_requests_sync_work_days ON public.job_requests;
CREATE TRIGGER trg_job_requests_sync_work_days
  AFTER UPDATE OF started_at, status ON public.job_requests
  FOR EACH ROW EXECUTE FUNCTION public.sync_job_work_days();

-- Jardineiro responsável de um trabalho em curso (confirmed + started_at).
-- Uso interno das duas RPCs abaixo.
CREATE OR REPLACE FUNCTION public.lock_started_job_for_worker(p_job_id uuid)
RETURNS public.job_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT jr.* INTO v_job
  FROM   job_requests  jr
  JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;
  IF v_job.started_at IS NULL THEN
    RAISE EXCEPTION 'O trabalho ainda não foi iniciado.';
  END IF;

  -- Trabalhos iniciados antes desta migration não têm o dia 1.
  INSERT INTO job_work_days (job_id, day_number, started_at)
  VALUES (p_job_id, 1, v_job.started_at)
  ON CONFLICT (job_id, day_number) DO NOTHING;

  RETURN v_job;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.lock_started_job_for_worker(uuid) FROM PUBLIC, anon, authenticated;

-- "Terminar o dia N".
CREATE OR REPLACE FUNCTION public.finish_work_day(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM lock_started_job_for_worker(p_job_id);

  UPDATE job_work_days
  SET    ended_at = now()
  WHERE  job_id = p_job_id AND ended_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há nenhum dia em curso.';
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.finish_work_day(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.finish_work_day(uuid) TO authenticated, service_role;

-- "Começar o dia N+1".
CREATE OR REPLACE FUNCTION public.start_work_day(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_next integer;
BEGIN
  PERFORM lock_started_job_for_worker(p_job_id);

  IF EXISTS (
    SELECT 1 FROM job_work_days WHERE job_id = p_job_id AND ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Termina primeiro o dia em curso.';
  END IF;

  SELECT COALESCE(max(day_number), 0) + 1 INTO v_next
  FROM   job_work_days WHERE job_id = p_job_id;

  INSERT INTO job_work_days (job_id, day_number, started_at)
  VALUES (p_job_id, v_next, now());
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.start_work_day(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.start_work_day(uuid) TO authenticated, service_role;

-- Dias de um trabalho: para o cliente, o responsável e os ajudantes
-- aceites. Trabalho iniciado antes desta migration e ainda sem linhas:
-- devolve o dia 1 a partir de started_at/marked_done_at.
CREATE OR REPLACE FUNCTION public.get_job_work_days(p_job_id uuid)
RETURNS TABLE(
  day_number  integer,
  started_at  timestamptz,
  ended_at    timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF NOT (
    v_job.client_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM job_proposals jp
      WHERE jp.id = v_job.accepted_proposal_id AND jp.worker_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM help_acceptances ha
      JOIN   help_requests hr ON hr.id = ha.help_request_id
      WHERE  hr.job_id = p_job_id AND ha.worker_id = auth.uid()
        AND  ha.status = 'accepted'
    )
  ) THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF EXISTS (SELECT 1 FROM job_work_days d WHERE d.job_id = p_job_id) THEN
    RETURN QUERY
      SELECT d.day_number, d.started_at, d.ended_at
      FROM   job_work_days d
      WHERE  d.job_id = p_job_id
      ORDER  BY d.day_number;
  ELSIF v_job.started_at IS NOT NULL THEN
    RETURN QUERY SELECT 1, v_job.started_at, v_job.marked_done_at;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_job_work_days(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_job_work_days(uuid) TO authenticated, service_role;


NOTIFY pgrst, 'reload schema';


-- ── Verificação (correr à parte depois de aplicar) ──────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'job_proposals'
--     AND column_name IN ('pricing_mode','total_price','includes',
--                         'estimated_days_min','estimated_days_max','valid_until');
-- SELECT * FROM proposal_include_options ORDER BY sort_order;
-- SELECT proname FROM pg_proc
--   WHERE proname IN ('finish_work_day','start_work_day','get_job_work_days');
