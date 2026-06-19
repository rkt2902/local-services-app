-- ==============================================================
-- supabase/migrations/0001_baseline.sql
-- Baseline migration: complete schema as of 2026-06-19.
-- Generated from docs/database_schema.md + Dart source inspection.
-- Function bodies are reconstructed — verify against a live pg_dump
-- before applying to a production replica.
--
-- Use this file to set up new dev/staging Supabase instances.
-- Do NOT re-run against the existing live DB (tables/functions
-- already exist; idempotent DDL paths are used where possible).
-- ==============================================================

-- ============================================================
-- 1. EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 2. TABLES  (dependency order; accepted_proposal_id FK added
--             after job_proposals exists — see section 2b)
-- ============================================================

CREATE TABLE IF NOT EXISTS profiles (
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text        NOT NULL CHECK (role IN ('client', 'worker')),
  full_name   text        NOT NULL,
  phone       text        NOT NULL,
  avatar_url  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS worker_profiles (
  profile_id          uuid    PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  bio                 text,
  default_hourly_rate numeric,
  radius_km           int     NOT NULL DEFAULT 10,
  base_lat            numeric NOT NULL,
  base_lng            numeric NOT NULL,
  tools               text[]  NOT NULL DEFAULT '{}',
  photos              text[]  NOT NULL DEFAULT '{}',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_categories (
  id     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug   text UNIQUE NOT NULL,
  name   text        NOT NULL,
  icon   text,
  active bool        NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS service_types (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  category_id uuid NOT NULL REFERENCES service_categories(id) ON DELETE CASCADE,
  slug        text NOT NULL,
  name        text NOT NULL,
  active      bool NOT NULL DEFAULT true,
  UNIQUE (category_id, slug)
);

CREATE TABLE IF NOT EXISTS worker_service_types (
  worker_id       uuid NOT NULL REFERENCES worker_profiles(profile_id) ON DELETE CASCADE,
  service_type_id uuid NOT NULL REFERENCES service_types(id)           ON DELETE CASCADE,
  PRIMARY KEY (worker_id, service_type_id)
);

-- accepted_proposal_id is uuid only here; FK added below after job_proposals exists.
CREATE TABLE IF NOT EXISTS job_requests (
  id                         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id                  uuid        NOT NULL REFERENCES profiles(id),
  service_type_id            uuid        NOT NULL REFERENCES service_types(id),
  address_text               text        NOT NULL,
  location_lat               numeric     NOT NULL,
  location_lng               numeric     NOT NULL,
  date_mode                  text        NOT NULL DEFAULT 'flexible'
                               CHECK (date_mode IN ('fixed', 'flexible', 'availability')),
  preferred_date             date,
  availability_text          text,
  urgency                    text        CHECK (urgency IN ('normal', 'urgent')),
  size_estimate              text        CHECK (size_estimate IN ('small', 'medium', 'large')),
  description                text        NOT NULL,
  status                     text        NOT NULL
                               CHECK (status IN (
                                 'open', 'confirmed', 'awaiting_confirmation',
                                 'completed', 'no_response', 'cancelled'
                               )),
  accepted_proposal_id       uuid,
  proposal_count             int         NOT NULL DEFAULT 0,
  confirmed_date             date,
  confirmed_time             time,
  confirmed_flexible         boolean     NOT NULL DEFAULT false,
  cancelled_by               uuid        REFERENCES profiles(id),
  cancel_reason              text,
  cancel_reason_detail       text,
  reopened_from              uuid        REFERENCES job_requests(id),
  reopen_count_client        int         NOT NULL DEFAULT 0,
  reopen_count_worker        int         NOT NULL DEFAULT 0,
  reschedule_proposed_date   date,
  reschedule_proposed_time   time,
  reschedule_proposed_flexible boolean,
  reschedule_proposed_by     uuid        REFERENCES profiles(id),
  reschedule_status          text        CHECK (reschedule_status IN ('pending', 'accepted', 'rejected')),
  cancelled_worker_id        uuid        REFERENCES profiles(id),
  excluded_worker_ids        uuid[]      NOT NULL DEFAULT '{}',
  expires_at                 timestamptz NOT NULL DEFAULT (now() + interval '48 hours'),
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_photos (
  id           uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id       uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  storage_path text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_proposals (
  id                  uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id              uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  worker_id           uuid        NOT NULL REFERENCES worker_profiles(profile_id),
  hourly_rate         numeric     NOT NULL,
  estimated_hours     numeric,
  estimated_hours_min numeric,
  estimated_hours_max numeric,
  people_needed       int         NOT NULL DEFAULT 1,
  notes               text,
  scheduled_date      date,
  scheduled_time      time,
  scheduled_flexible  boolean     NOT NULL DEFAULT false,
  status              text        NOT NULL
                        CHECK (status IN ('pending', 'accepted', 'rejected', 'superseded')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- 2b. Close the circular FK now that job_proposals exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'job_requests'
      AND constraint_name = 'fk_job_requests_accepted_proposal'
  ) THEN
    ALTER TABLE job_requests
      ADD CONSTRAINT fk_job_requests_accepted_proposal
      FOREIGN KEY (accepted_proposal_id) REFERENCES job_proposals(id);
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS notifications (
  id           uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type         text        NOT NULL,
  -- Types: new_job_in_radius, proposal_received, proposal_withdrawn,
  --        proposal_accepted, proposal_rejected, job_cancelled, job_reopened,
  --        job_marked_done, job_completed, job_no_response,
  --        reschedule_proposed, reschedule_accepted, reschedule_rejected
  title        text        NOT NULL,
  body         text        NOT NULL,
  related_id   uuid,
  related_type text,
  read         bool        NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS help_requests (
  id           uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id       uuid        NOT NULL REFERENCES job_requests(id),
  proposal_id  uuid        NOT NULL REFERENCES job_proposals(id),
  slots_needed int         NOT NULL,
  status       text        NOT NULL CHECK (status IN ('open', 'filled', 'cancelled')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS help_acceptances (
  id              uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  help_request_id uuid        NOT NULL REFERENCES help_requests(id),
  worker_id       uuid        NOT NULL REFERENCES worker_profiles(profile_id),
  status          text        NOT NULL CHECK (status IN ('accepted', 'cancelled')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (help_request_id, worker_id)
);

CREATE TABLE IF NOT EXISTS ratings (
  id         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id     uuid        NOT NULL REFERENCES job_requests(id),
  rater_id   uuid        NOT NULL REFERENCES profiles(id),
  ratee_id   uuid        NOT NULL REFERENCES profiles(id),
  stars      int         NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment    text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, rater_id, ratee_id)
);

CREATE TABLE IF NOT EXISTS job_reports (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id      uuid        NOT NULL REFERENCES job_requests(id),
  reporter_id uuid        NOT NULL REFERENCES profiles(id),
  description text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 3. INDEXES
-- ============================================================

-- Race-condition guard: one pending proposal per worker per job
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_proposal_per_worker_per_job
  ON job_proposals (job_id, worker_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_job_requests_client_id  ON job_requests (client_id);
CREATE INDEX IF NOT EXISTS idx_job_requests_status     ON job_requests (status);
CREATE INDEX IF NOT EXISTS idx_job_proposals_worker_id ON job_proposals (worker_id);
CREATE INDEX IF NOT EXISTS idx_job_proposals_job_id    ON job_proposals (job_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id   ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications (user_id, read);

-- ============================================================
-- 4. ENABLE RLS
-- ============================================================

ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_types        ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_service_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_requests         ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_photos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_proposals        ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE help_requests        ENABLE ROW LEVEL SECURITY;
ALTER TABLE help_acceptances     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_reports          ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. RLS POLICIES
-- NOTE: worker_has_proposal_for_job() is used below and is
--       defined in section 6.  Functions must therefore be
--       created before policies are evaluated at runtime —
--       the function definition in section 6 is fine because
--       policies are not evaluated during CREATE POLICY, only
--       at query time.
-- ============================================================

-- ─── profiles ────────────────────────────────────────────────
-- All authenticated users may read all profiles.
-- Dart queries limit column selection (full_name, phone, avatar_url).

CREATE POLICY "Perfis são legíveis por utilizadores autenticados"
  ON profiles FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Utilizador cria o seu próprio perfil"
  ON profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Utilizador atualiza o seu próprio perfil"
  ON profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id);

-- ─── worker_profiles ─────────────────────────────────────────

CREATE POLICY "Worker profiles são públicos"
  ON worker_profiles FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Worker cria o seu próprio worker profile"
  ON worker_profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = profile_id);

CREATE POLICY "Worker atualiza o seu próprio worker profile"
  ON worker_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = profile_id);

-- ─── service_categories ──────────────────────────────────────

CREATE POLICY "Categorias são públicas"
  ON service_categories FOR SELECT TO authenticated
  USING (true);

-- ─── service_types ───────────────────────────────────────────

CREATE POLICY "Tipos de serviço são públicos"
  ON service_types FOR SELECT TO authenticated
  USING (true);

-- ─── worker_service_types ────────────────────────────────────

CREATE POLICY "Tipos de serviço do worker são públicos"
  ON worker_service_types FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Worker gere os seus tipos de serviço"
  ON worker_service_types FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = worker_id);

CREATE POLICY "Worker remove os seus tipos de serviço"
  ON worker_service_types FOR DELETE TO authenticated
  USING (auth.uid() = worker_id);

-- ─── job_requests ────────────────────────────────────────────

CREATE POLICY "Client vê os seus jobs"
  ON job_requests FOR SELECT TO authenticated
  USING (auth.uid() = client_id);

CREATE POLICY "Worker vê jobs abertos e os seus"
  ON job_requests FOR SELECT TO authenticated
  USING (status = 'open' OR worker_has_proposal_for_job(id));

CREATE POLICY "Client cria jobs"
  ON job_requests FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = client_id);

-- Canonical name (covers edits + cancellations via RPC)
CREATE POLICY "Client atualiza os seus jobs"
  ON job_requests FOR UPDATE TO authenticated
  USING (auth.uid() = client_id);

-- ─── job_photos ──────────────────────────────────────────────

CREATE POLICY "Fotos são públicas"
  ON job_photos FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Client envia fotos do seu job"
  ON job_photos FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE id = job_photos.job_id AND client_id = auth.uid()
    )
  );

-- ─── job_proposals ───────────────────────────────────────────
-- Canonical names (duplicates removed):
--   "Worker envia proposta"       (not "Worker cria propostas")
--   "Worker vê as suas propostas" (not the unaccented variant)

CREATE POLICY "Worker envia proposta"
  ON job_proposals FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = worker_id);

CREATE POLICY "Worker vê as suas propostas"
  ON job_proposals FOR SELECT TO authenticated
  USING (auth.uid() = worker_id);

CREATE POLICY "Client vê propostas dos seus jobs"
  ON job_proposals FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE id = job_proposals.job_id AND client_id = auth.uid()
    )
  );

CREATE POLICY "Worker atualiza as suas propostas"
  ON job_proposals FOR UPDATE TO authenticated
  USING (auth.uid() = worker_id);

-- ─── notifications ───────────────────────────────────────────

CREATE POLICY "Utilizador vê as suas notificações"
  ON notifications FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Utilizador atualiza as suas notificações"
  ON notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Utilizador apaga as suas notificações"
  ON notifications FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- DB trigger functions run as SECURITY DEFINER (service_role);
-- explicit INSERT policy for service_role lets them bypass RLS.
CREATE POLICY "Sistema insere notificações"
  ON notifications FOR INSERT TO service_role
  WITH CHECK (true);

-- ─── help_requests ───────────────────────────────────────────

CREATE POLICY "Worker principal vê help requests"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE id = help_requests.proposal_id AND worker_id = auth.uid()
    )
  );

CREATE POLICY "Worker principal cria help requests"
  ON help_requests FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE id = help_requests.proposal_id AND worker_id = auth.uid()
    )
  );

-- ─── help_acceptances ────────────────────────────────────────

CREATE POLICY "Workers veem help acceptances relevantes"
  ON help_acceptances FOR SELECT TO authenticated
  USING (
    auth.uid() = worker_id
    OR EXISTS (
      SELECT 1
      FROM help_requests hr
      JOIN job_proposals jp ON jp.id = hr.proposal_id
      WHERE hr.id = help_acceptances.help_request_id
        AND jp.worker_id = auth.uid()
    )
  );

CREATE POLICY "Worker aceita ajudar"
  ON help_acceptances FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = worker_id);

CREATE POLICY "Worker cancela ajuda"
  ON help_acceptances FOR UPDATE TO authenticated
  USING (auth.uid() = worker_id);

-- ─── ratings ─────────────────────────────────────────────────

CREATE POLICY "Avaliações são públicas"
  ON ratings FOR SELECT
  USING (true);

CREATE POLICY "Utilizador submete avaliação"
  ON ratings FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = rater_id);

-- ─── job_reports ─────────────────────────────────────────────

CREATE POLICY "Utilizador reporta problema"
  ON job_reports FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = reporter_id);

-- TODO: add SELECT policy for admin review UI (Fase pós-MVP).
CREATE POLICY "Apenas serviço lê relatos"
  ON job_reports FOR SELECT TO service_role
  USING (true);

-- ============================================================
-- 6. FUNCTIONS (all SECURITY DEFINER, SET search_path = public)
-- ============================================================

-- ─── Helper used in RLS: does the calling worker have any
--     proposal (in any status) for the given job? ────────────

CREATE OR REPLACE FUNCTION worker_has_proposal_for_job(job_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM job_proposals jp
    WHERE jp.job_id = worker_has_proposal_for_job.job_id
      AND jp.worker_id = auth.uid()
  );
$$;

-- ─── create_user_profile ─────────────────────────────────────
-- Utility function for programmatic profile creation (upsert).
-- The Dart app currently uses a direct upsert on profiles;
-- this function is kept for DB-level or admin use.

CREATE OR REPLACE FUNCTION create_user_profile(
  user_id   uuid,
  full_name text,
  phone     text,
  user_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, role, full_name, phone)
  VALUES (user_id, user_role, full_name, phone)
  ON CONFLICT (id) DO UPDATE
    SET full_name  = EXCLUDED.full_name,
        phone      = EXCLUDED.phone,
        updated_at = now();
END;
$$;

-- ─── get_jobs_in_radius ──────────────────────────────────────
-- Haversine query: returns open jobs within radius_km of the
-- worker's position, excluding jobs where the worker is in
-- excluded_worker_ids or already has a pending proposal.

CREATE OR REPLACE FUNCTION get_jobs_in_radius(
  worker_lat  double precision,
  worker_lng  double precision,
  radius_km   integer,
  p_worker_id uuid DEFAULT NULL
)
RETURNS SETOF job_requests
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT jr.*
  FROM job_requests jr
  WHERE jr.status = 'open'
    AND (
      2 * 6371 * asin(sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))
    ) <= radius_km
    AND (p_worker_id IS NULL OR NOT (p_worker_id = ANY(jr.excluded_worker_ids)))
    AND (p_worker_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM job_proposals jp
      WHERE jp.job_id = jr.id
        AND jp.worker_id = p_worker_id
        AND jp.status = 'pending'
    ))
  ORDER BY jr.created_at DESC;
$$;

-- ─── create_proposal ─────────────────────────────────────────
-- Inserts a proposal under row-lock on job_requests to prevent
-- duplicate proposals racing the unique partial index.
-- Returns the new proposal UUID.

CREATE OR REPLACE FUNCTION create_proposal(
  p_job_id              uuid,
  p_worker_id           uuid,
  p_hourly_rate         numeric,
  p_estimated_hours_min numeric  DEFAULT NULL,
  p_estimated_hours_max numeric  DEFAULT NULL,
  p_people_needed       int      DEFAULT 1,
  p_notes               text     DEFAULT NULL,
  p_scheduled_date      date     DEFAULT NULL,
  p_scheduled_time      text     DEFAULT NULL,
  p_scheduled_flexible  boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proposal_id uuid;
  v_job_status  text;
  v_client_id   uuid;
BEGIN
  SELECT status, client_id
  INTO   v_job_status, v_client_id
  FROM   job_requests
  WHERE  id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job_status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  -- Friendly error before the unique index fires
  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE job_id = p_job_id AND worker_id = p_worker_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    status
  ) VALUES (
    p_job_id, p_worker_id, p_hourly_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    'pending'
  )
  RETURNING id INTO v_proposal_id;

  UPDATE job_requests
  SET proposal_count = proposal_count + 1,
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_client_id,
    'proposal_received',
    'Nova proposta recebida',
    'Um jardineiro enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$$;

-- ─── accept_proposal ─────────────────────────────────────────
-- Accepts one proposal, rejects all other pending proposals for
-- the same job (with notifications), and confirms the job.

CREATE OR REPLACE FUNCTION accept_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id          uuid;
  v_scheduled_date     date;
  v_scheduled_time     time;
  v_scheduled_flexible boolean;
BEGIN
  SELECT worker_id, scheduled_date, scheduled_time, scheduled_flexible
  INTO   v_worker_id, v_scheduled_date, v_scheduled_time, v_scheduled_flexible
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'accepted', updated_at = now()
  WHERE id = p_proposal_id;

  -- Reject remaining pending proposals and notify those workers atomically
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
$$;

-- ─── reject_proposal ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION reject_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id uuid;
BEGIN
  SELECT worker_id INTO v_worker_id
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'rejected', updated_at = now()
  WHERE id = p_proposal_id;

  UPDATE job_requests
  SET proposal_count = GREATEST(proposal_count - 1, 0),
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id,
    'proposal_rejected',
    'Proposta não selecionada',
    'O cliente recusou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── withdraw_proposal ───────────────────────────────────────

CREATE OR REPLACE FUNCTION withdraw_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM job_proposals
    WHERE id        = p_proposal_id
      AND job_id    = p_job_id
      AND worker_id = auth.uid()
      AND status    = 'pending'
  ) THEN
    RAISE EXCEPTION 'Proposta não encontrada ou não pode ser retirada.';
  END IF;

  UPDATE job_proposals
  SET status = 'superseded', updated_at = now()
  WHERE id = p_proposal_id;

  SELECT client_id INTO v_client_id FROM job_requests WHERE id = p_job_id;

  UPDATE job_requests
  SET proposal_count = GREATEST(proposal_count - 1, 0),
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_client_id,
    'proposal_withdrawn',
    'Proposta retirada',
    'Um jardineiro retirou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── cancel_job ──────────────────────────────────────────────
-- Cancels a job (open or confirmed). If the job was confirmed
-- and the cancelling party is within reopen limits, creates a
-- new open job with the cancelling worker added to
-- excluded_worker_ids. Returns the new job's UUID (or NULL).
--
-- Reopen limits: client ≤ 1, worker ≤ 2.

CREATE OR REPLACE FUNCTION cancel_job(
  p_job_id        uuid,
  p_reason        text,
  p_reason_detail text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job           job_requests%ROWTYPE;
  v_caller_id     uuid    := auth.uid();
  v_is_worker     boolean;
  v_other_user_id uuid;
  v_can_reopen    boolean := false;
  v_new_excluded  uuid[];
  v_new_job_id    uuid    := NULL;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed') THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser cancelado no estado atual.';
  END IF;

  v_is_worker := (v_job.client_id <> v_caller_id);

  -- Identify the other party for cancellation notification
  IF v_is_worker THEN
    v_other_user_id := v_job.client_id;
  ELSE
    SELECT worker_id INTO v_other_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  END IF;

  -- Only confirmed jobs can be reopened
  IF v_job.status = 'confirmed' THEN
    IF (NOT v_is_worker) AND v_job.reopen_count_client < 1 THEN
      v_can_reopen := true;
    ELSIF v_is_worker AND v_job.reopen_count_worker < 2 THEN
      v_can_reopen := true;
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

  IF v_other_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_other_user_id,
      'job_cancelled',
      'Pedido cancelado',
      'Um pedido foi cancelado.',
      p_job_id,
      'job_request'
    );
  END IF;

  IF v_can_reopen THEN
    v_new_excluded := v_job.excluded_worker_ids;
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id,       service_type_id,   address_text,
      location_lat,    location_lng,
      date_mode,       preferred_date,    availability_text,
      urgency,         size_estimate,     description,
      status,          reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id,      v_job.service_type_id, v_job.address_text,
      v_job.location_lat,   v_job.location_lng,
      v_job.date_mode,      v_job.preferred_date,  v_job.availability_text,
      v_job.urgency,        v_job.size_estimate,   v_job.description,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded,
      now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    -- Notify the client when the worker cancels and the job is reopened
    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        v_job.client_id,
        'job_reopened',
        'Pedido reaberto',
        'O pedido foi reaberto automaticamente.',
        v_new_job_id,
        'job_request'
      );
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$$;

-- ─── propose_reschedule ──────────────────────────────────────
-- Either party may propose a new date (24h rule; only one
-- pending reschedule at a time).

CREATE OR REPLACE FUNCTION propose_reschedule(
  p_job_id       uuid,
  p_new_date     date,
  p_new_time     text    DEFAULT NULL,
  p_new_flexible boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job            job_requests%ROWTYPE;
  v_caller_id      uuid := auth.uid();
  v_notify_user_id uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'confirmed' THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser remarcado.';
  END IF;
  IF v_job.reschedule_status = 'pending' THEN
    RAISE EXCEPTION 'Já existe uma remarcação pendente.';
  END IF;
  IF v_job.confirmed_date IS NOT NULL
     AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
    RAISE EXCEPTION 'A remarcação requer pelo menos 24h de antecedência.';
  END IF;

  UPDATE job_requests
  SET reschedule_proposed_date     = p_new_date,
      reschedule_proposed_time     = p_new_time::time,
      reschedule_proposed_flexible = p_new_flexible,
      reschedule_proposed_by       = v_caller_id,
      reschedule_status            = 'pending',
      updated_at                   = now()
  WHERE id = p_job_id;

  IF v_job.client_id = v_caller_id THEN
    SELECT worker_id INTO v_notify_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  ELSE
    v_notify_user_id := v_job.client_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_notify_user_id,
    'reschedule_proposed',
    'Remarcação proposta',
    'Foi proposta uma nova data para o trabalho.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── accept_reschedule ───────────────────────────────────────

CREATE OR REPLACE FUNCTION accept_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.reschedule_status <> 'pending' THEN
    RAISE EXCEPTION 'Não existe remarcação pendente para este pedido.';
  END IF;
  IF v_job.reschedule_proposed_by = auth.uid() THEN
    RAISE EXCEPTION 'Não podes aceitar a tua própria remarcação.';
  END IF;

  UPDATE job_requests
  SET confirmed_date               = reschedule_proposed_date,
      confirmed_time               = reschedule_proposed_time,
      confirmed_flexible           = COALESCE(reschedule_proposed_flexible, false),
      reschedule_status            = 'accepted',
      reschedule_proposed_date     = NULL,
      reschedule_proposed_time     = NULL,
      reschedule_proposed_flexible = NULL,
      reschedule_proposed_by       = NULL,
      updated_at                   = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.reschedule_proposed_by,
    'reschedule_accepted',
    'Remarcação aceite',
    'A nova data foi aceite.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── reject_reschedule ───────────────────────────────────────

CREATE OR REPLACE FUNCTION reject_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.reschedule_status <> 'pending' THEN
    RAISE EXCEPTION 'Não existe remarcação pendente para este pedido.';
  END IF;
  IF v_job.reschedule_proposed_by = auth.uid() THEN
    RAISE EXCEPTION 'Não podes recusar a tua própria remarcação.';
  END IF;

  UPDATE job_requests
  SET reschedule_status            = 'rejected',
      reschedule_proposed_date     = NULL,
      reschedule_proposed_time     = NULL,
      reschedule_proposed_flexible = NULL,
      reschedule_proposed_by       = NULL,
      updated_at                   = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.reschedule_proposed_by,
    'reschedule_rejected',
    'Remarcação recusada',
    'A nova data foi recusada.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── mark_job_done ───────────────────────────────────────────
-- Worker marks job as completed on their side.
-- Job moves to awaiting_confirmation; client receives notification.

CREATE OR REPLACE FUNCTION mark_job_done(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'confirmed' THEN
    RAISE EXCEPTION 'estado inválido: o pedido não está confirmado.';
  END IF;

  SELECT worker_id INTO v_worker_id
  FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

  IF v_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'não autorizado: só o worker aceite pode marcar como concluído.';
  END IF;

  UPDATE job_requests
  SET status     = 'awaiting_confirmation',
      updated_at = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'job_marked_done',
    'Trabalho concluído',
    'O prestador marcou o trabalho como concluído. Confirme se está satisfeito.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ─── confirm_job_completion ──────────────────────────────────
-- Client confirms the job is done. Job moves to completed;
-- worker receives notification.

CREATE OR REPLACE FUNCTION confirm_job_completion(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'awaiting_confirmation' THEN
    RAISE EXCEPTION 'estado inválido: o pedido não está a aguardar confirmação.';
  END IF;
  IF v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'não autorizado: só o cliente pode confirmar a conclusão.';
  END IF;

  UPDATE job_requests
  SET status     = 'completed',
      updated_at = now()
  WHERE id = p_job_id;

  SELECT worker_id INTO v_worker_id
  FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

  IF v_worker_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_worker_id,
      'job_completed',
      'Trabalho confirmado!',
      'O cliente confirmou a conclusão do trabalho.',
      p_job_id,
      'job_request'
    );
  END IF;
END;
$$;

-- ============================================================
-- 7. TRIGGER: notify workers when a new job is created
-- ============================================================

CREATE OR REPLACE FUNCTION notify_workers_new_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    wp.profile_id,
    'new_job_in_radius',
    'Novo pedido perto de si',
    'Um novo pedido foi criado na sua área de atuação.',
    NEW.id,
    'job_request'
  FROM worker_profiles wp
  WHERE (
    2 * 6371 * asin(sqrt(
      power(sin(radians((NEW.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
      + cos(radians(wp.base_lat::double precision))
        * cos(radians(NEW.location_lat::double precision))
        * power(sin(radians((NEW.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
    ))
  ) <= wp.radius_km
  AND NOT (wp.profile_id = ANY(NEW.excluded_worker_ids));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_workers_new_job ON job_requests;
CREATE TRIGGER trigger_notify_workers_new_job
  AFTER INSERT ON job_requests
  FOR EACH ROW
  EXECUTE FUNCTION notify_workers_new_job();

-- ============================================================
-- 8. STORAGE: buckets + policies
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('job-photos',    'job-photos',    true),
  ('worker-photos', 'worker-photos', true),
  ('avatars',       'avatars',       true)
ON CONFLICT (id) DO NOTHING;

-- job-photos: public read, authenticated write, delete by folder owner
CREATE POLICY "job-photos: leitura pública"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'job-photos');

CREATE POLICY "job-photos: upload autenticado"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'job-photos');

CREATE POLICY "job-photos: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- worker-photos: public read, owner only write/delete
CREATE POLICY "worker-photos: leitura pública"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'worker-photos');

CREATE POLICY "worker-photos: upload pelo dono"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'worker-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "worker-photos: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'worker-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- avatars: public read, owner only write/update/delete
CREATE POLICY "avatars: leitura pública"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "avatars: upload pelo dono"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "avatars: update pelo dono"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "avatars: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- ============================================================
-- 9. SEED — minimum data for a working dev environment
-- ============================================================

INSERT INTO service_categories (id, slug, name, icon)
VALUES ('00000000-0000-0000-0000-000000000001', 'gardening', 'Jardinagem', 'park')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO service_types (category_id, slug, name)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'lawn_mowing',  'Corte de relva'),
  ('00000000-0000-0000-0000-000000000001', 'pruning',      'Poda'),
  ('00000000-0000-0000-0000-000000000001', 'garden_setup', 'Montagem de jardim')
ON CONFLICT (category_id, slug) DO NOTHING;
