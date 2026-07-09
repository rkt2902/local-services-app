-- ==============================================================
-- supabase/migrations/0001_consolidated_baseline.sql
--
-- Complete live DB state as of 2026-07-09.
-- Consolidates migrations 0001_baseline … 0032_audit_fixes.
-- Apply to a fresh Supabase project to reproduce the live DB exactly.
--
-- SOURCE:
--   supabase/snapshot_tables.csv (sections 1–6, taken 2026-07-09)
--   archive/0001_baseline.sql (service_categories, job_photos, functions
--     not captured by snapshot query, storage buckets, seed data)
--   archive/0032_audit_fixes.sql (corrected FKs, auth-checked RPCs,
--     role-change trigger, indexes, profiles SELECT policies)
--
-- NOTE: snapshot_a.csv and snapshot_b.csv do NOT exist. All snapshot
-- data was read from a single snapshot_tables.csv file.
--
-- IMPORTANT: This file reproduces the schema AFTER applying 0032 fixes,
-- even though 0032 has not yet been applied to the live DB. See:
--   archive/0032_audit_fixes.sql — apply this to the live DB manually.
--
-- NOT APPLIED — Henrique reviews and applies manually.
-- ==============================================================


-- ══════════════════════════════════════════════════════════════
-- 1. EXTENSIONS
-- ══════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ══════════════════════════════════════════════════════════════
-- 2. TABLES (FK dependency order)
--    Circular dep: job_requests.accepted_proposal_id → job_proposals
--    resolved in section 3.
-- ══════════════════════════════════════════════════════════════

-- ── profiles ─────────────────────────────────────────────────
-- Note: phone is nullable in the live DB (no NOT NULL constraint).
-- The original 0001_baseline had phone NOT NULL; it was changed
-- interactively after go-live.

CREATE TABLE IF NOT EXISTS profiles (
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text        NOT NULL CHECK (role IN ('client', 'worker')),
  full_name   text        NOT NULL,
  phone       text,
  avatar_url  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ── service_categories ───────────────────────────────────────
-- Not captured in snapshot query (excluded from table list).
-- Definition from archive/0001_baseline.sql.

CREATE TABLE IF NOT EXISTS service_categories (
  id     uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug   text        UNIQUE NOT NULL,
  name   text        NOT NULL,
  icon   text,
  active boolean     NOT NULL DEFAULT true
);

-- ── service_types ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS service_types (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  category_id uuid        NOT NULL REFERENCES service_categories(id) ON DELETE CASCADE,
  slug        text        NOT NULL,
  name        text        NOT NULL,
  active      boolean     NOT NULL DEFAULT true,
  UNIQUE (category_id, slug)
);

-- ── worker_profiles ──────────────────────────────────────────
-- location_name added in migration 0030 (reverse-geocoded city/area).

CREATE TABLE IF NOT EXISTS worker_profiles (
  profile_id          uuid        PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  bio                 text,
  default_hourly_rate numeric,
  radius_km           integer     NOT NULL DEFAULT 10,
  base_lat            numeric     NOT NULL,
  base_lng            numeric     NOT NULL,
  location_name       text,
  tools               text[]      NOT NULL DEFAULT '{}',
  photos              text[]      NOT NULL DEFAULT '{}',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- ── worker_service_types ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS worker_service_types (
  worker_id       uuid NOT NULL REFERENCES worker_profiles(profile_id) ON DELETE CASCADE,
  service_type_id uuid NOT NULL REFERENCES service_types(id)           ON DELETE CASCADE,
  PRIMARY KEY (worker_id, service_type_id)
);

-- ── job_requests ─────────────────────────────────────────────
-- accepted_proposal_id FK is deferred to section 3 (circular dep).
-- Note: confirmed_flexible is nullable boolean in the live DB.

CREATE TABLE IF NOT EXISTS job_requests (
  id                         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id                  uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  service_type_id            uuid        NOT NULL REFERENCES service_types(id),
  address_text               text        NOT NULL,
  location_lat               numeric     NOT NULL,
  location_lng               numeric     NOT NULL,
  date_mode                  text        NOT NULL DEFAULT 'flexible'
                               CHECK (date_mode IN ('fixed', 'flexible', 'availability')),
  preferred_date             date,
  availability_text          text,
  urgency                    text        CHECK (urgency IN ('normal', 'urgent')),
  size_estimate              text,
  description                text        NOT NULL,
  status                     text        NOT NULL DEFAULT 'open'
                               CHECK (status IN (
                                 'open', 'confirmed', 'awaiting_confirmation',
                                 'completed', 'no_response', 'cancelled'
                               )),
  accepted_proposal_id       uuid,
  proposal_count             integer     NOT NULL DEFAULT 0,
  confirmed_date             date,
  confirmed_time             time,
  confirmed_flexible         boolean,
  cancelled_by               uuid        REFERENCES profiles(id),
  cancel_reason              text,
  cancel_reason_detail       text,
  cancelled_worker_id        uuid        REFERENCES profiles(id),
  reopened_from              uuid        REFERENCES job_requests(id),
  reopen_count_client        integer     NOT NULL DEFAULT 0,
  reopen_count_worker        integer     NOT NULL DEFAULT 0,
  reschedule_proposed_date   date,
  reschedule_proposed_time   time,
  reschedule_proposed_flexible boolean,
  reschedule_proposed_by     uuid        REFERENCES profiles(id),
  reschedule_status          text        CHECK (reschedule_status IN ('pending', 'accepted', 'rejected')),
  excluded_worker_ids        uuid[]      NOT NULL DEFAULT '{}',
  expires_at                 timestamptz NOT NULL DEFAULT (now() + interval '48 hours'),
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now()
);

-- ── job_photos ───────────────────────────────────────────────
-- Not captured in snapshot query (excluded from table list).
-- Definition from archive/0001_baseline.sql.

CREATE TABLE IF NOT EXISTS job_photos (
  id           uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id       uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  storage_path text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ── job_proposals ────────────────────────────────────────────
-- CORRECTED FK: worker_id → profiles(id) ON DELETE CASCADE
-- (Live DB still points to worker_profiles(profile_id) — fixed in 0032.)

CREATE TABLE IF NOT EXISTS job_proposals (
  id                          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id                      uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  worker_id                   uuid        NOT NULL REFERENCES profiles(id)      ON DELETE CASCADE,
  hourly_rate                 numeric     NOT NULL,
  estimated_hours             numeric,
  estimated_hours_min         numeric,
  estimated_hours_max         numeric,
  people_needed               integer     NOT NULL DEFAULT 1,
  notes                       text,
  scheduled_date              date,
  scheduled_time              time,
  scheduled_flexible          boolean     NOT NULL DEFAULT false,
  helpers_equipment_required  boolean     NOT NULL DEFAULT false,
  status                      text        NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending', 'accepted', 'rejected', 'superseded')),
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT check_people_needed CHECK (people_needed >= 1)
);

-- ── notifications ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notifications (
  id           uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type         text        NOT NULL,
  title        text        NOT NULL,
  body         text        NOT NULL,
  related_id   uuid,
  related_type text,
  read         boolean     NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ── help_requests ────────────────────────────────────────────
-- status includes 'pending_approval' (added post-0001).

CREATE TABLE IF NOT EXISTS help_requests (
  id                      uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id                  uuid        NOT NULL REFERENCES job_requests(id)  ON DELETE CASCADE,
  proposal_id             uuid        NOT NULL REFERENCES job_proposals(id) ON DELETE CASCADE,
  slots_needed            integer     NOT NULL DEFAULT 1,
  status                  text        NOT NULL DEFAULT 'open'
                            CHECK (status IN ('pending_approval', 'open', 'filled', 'cancelled')),
  equipment_required      boolean     NOT NULL DEFAULT false,
  created_post_confirmation boolean   NOT NULL DEFAULT false,
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT check_slots_needed CHECK (slots_needed >= 1)
);

-- ── help_acceptances ─────────────────────────────────────────
-- CORRECTED FK: worker_id → profiles(id) ON DELETE CASCADE
-- (Live DB still points to worker_profiles(profile_id) — fixed in 0032.)
-- agreed_rate and brought_equipment added post-0001.

CREATE TABLE IF NOT EXISTS help_acceptances (
  id              uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  help_request_id uuid        NOT NULL REFERENCES help_requests(id) ON DELETE CASCADE,
  worker_id       uuid        NOT NULL REFERENCES profiles(id)       ON DELETE CASCADE,
  status          text        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  agreed_rate     numeric     NOT NULL DEFAULT 0,
  brought_equipment boolean   NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (help_request_id, worker_id),
  CONSTRAINT check_agreed_rate CHECK (
    (status <> 'accepted') OR (agreed_rate > 0)
  )
);

-- ── ratings ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ratings (
  id         uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id     uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  rater_id   uuid        NOT NULL REFERENCES profiles(id),
  ratee_id   uuid        NOT NULL REFERENCES profiles(id),
  stars      integer     NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment    text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, rater_id, ratee_id),
  CONSTRAINT check_rater_not_ratee CHECK (rater_id <> ratee_id)
);

-- ── job_reports ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS job_reports (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id      uuid        NOT NULL REFERENCES job_requests(id) ON DELETE CASCADE,
  reporter_id uuid        NOT NULL REFERENCES profiles(id),
  description text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);


-- ══════════════════════════════════════════════════════════════
-- 3. DEFERRED FK — close the circular dependency
-- ══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE  table_name       = 'job_requests'
      AND  constraint_name  = 'fk_accepted_proposal'
      AND  table_schema     = 'public'
  ) THEN
    ALTER TABLE job_requests
      ADD CONSTRAINT fk_accepted_proposal
      FOREIGN KEY (accepted_proposal_id) REFERENCES job_proposals(id);
  END IF;
END;
$$;


-- ══════════════════════════════════════════════════════════════
-- 4. INDEXES
-- ══════════════════════════════════════════════════════════════

-- Race-condition guard: one pending proposal per worker per job.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_proposal_per_worker_per_job
  ON job_proposals (job_id, worker_id)
  WHERE (status = 'pending');

-- help_acceptances
CREATE UNIQUE INDEX IF NOT EXISTS help_acceptances_help_request_id_worker_id_key
  ON help_acceptances (help_request_id, worker_id);
CREATE INDEX IF NOT EXISTS idx_help_acceptances_worker_id
  ON help_acceptances (worker_id);

-- help_requests
CREATE INDEX IF NOT EXISTS idx_help_requests_job_id
  ON help_requests (job_id);
CREATE INDEX IF NOT EXISTS idx_help_requests_proposal_id
  ON help_requests (proposal_id);

-- job_proposals (6 missing from live DB before 0032)
CREATE INDEX IF NOT EXISTS idx_job_proposals_worker_id
  ON job_proposals (worker_id);
CREATE INDEX IF NOT EXISTS idx_job_proposals_job_id
  ON job_proposals (job_id);

-- job_requests (missing from live DB before 0032)
CREATE INDEX IF NOT EXISTS idx_job_requests_client_id
  ON job_requests (client_id);
CREATE INDEX IF NOT EXISTS idx_job_requests_status
  ON job_requests (status);

-- notifications
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read
  ON notifications (user_id, read);

-- ratings
CREATE UNIQUE INDEX IF NOT EXISTS ratings_job_id_rater_id_ratee_id_key
  ON ratings (job_id, rater_id, ratee_id);

-- service_types
CREATE UNIQUE INDEX IF NOT EXISTS service_types_category_id_slug_key
  ON service_types (category_id, slug);


-- ══════════════════════════════════════════════════════════════
-- 5. ENABLE ROW LEVEL SECURITY
-- ══════════════════════════════════════════════════════════════

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


-- ══════════════════════════════════════════════════════════════
-- 6. RLS POLICIES
-- Policy names and expressions are taken verbatim from the live DB
-- (snapshot_tables.csv section 4_rls_policies, 2026-07-09).
-- Profiles SELECT and UPDATE policies incorporate 0032 changes.
-- ══════════════════════════════════════════════════════════════

-- ─── profiles ────────────────────────────────────────────────
-- Three granular SELECT policies replaced the original USING(true)
-- policy (captured from live DB in 0032 Priority 5).
-- UPDATE policy has explicit WITH CHECK (from 0032 Priority 3).

CREATE POLICY "Utilizador cria o seu perfil"
  ON profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Utilizador vê o seu perfil"
  ON profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Worker ve perfil de cliente com job confirmado"
  ON profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   job_proposals jp
      JOIN   job_requests  jr ON jr.id = jp.job_id
      WHERE  jp.worker_id  = auth.uid()
        AND  jr.client_id  = profiles.id
        AND  jp.status     = 'accepted'
    )
  );

CREATE POLICY "Cliente ve perfil de worker com job confirmado"
  ON profiles FOR SELECT TO authenticated
  USING (
    role = 'worker'
    AND client_has_confirmed_job_with_worker(id)
  );

CREATE POLICY "Utilizador atualiza o seu perfil"
  ON profiles FOR UPDATE TO authenticated
  USING     (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ─── worker_profiles ─────────────────────────────────────────
-- Restricted to owner-only SELECT after migration 0030.

CREATE POLICY "Worker lê o seu próprio perfil"
  ON worker_profiles FOR SELECT TO authenticated
  USING (profile_id = auth.uid());

CREATE POLICY "Worker cria o seu perfil"
  ON worker_profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = profile_id);

CREATE POLICY "Worker atualiza o seu perfil"
  ON worker_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = profile_id);

-- ─── service_categories ──────────────────────────────────────

CREATE POLICY "Leitura pública de categorias"
  ON service_categories FOR SELECT TO authenticated
  USING (true);

-- ─── service_types ───────────────────────────────────────────

CREATE POLICY "Leitura pública de tipos de serviço"
  ON service_types FOR SELECT TO authenticated
  USING (true);

-- ─── worker_service_types ────────────────────────────────────
-- Live DB has an ALL policy (not separate INSERT/UPDATE/DELETE).

CREATE POLICY "Worker gere os seus serviços"
  ON worker_service_types FOR ALL TO authenticated
  USING (auth.uid() = worker_id);

CREATE POLICY "Qualquer autenticado vê serviços de workers"
  ON worker_service_types FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

-- ─── job_requests ────────────────────────────────────────────

CREATE POLICY "Client vê os seus jobs"
  ON job_requests FOR SELECT TO authenticated
  USING (auth.uid() = client_id);

CREATE POLICY "Worker vê jobs abertos"
  ON job_requests FOR SELECT TO authenticated
  USING ((status = 'open') AND (auth.role() = 'authenticated'));

CREATE POLICY "Worker ve jobs onde tem proposta"
  ON job_requests FOR SELECT TO authenticated
  USING (worker_has_proposal_for_job(id));

CREATE POLICY "Client cria jobs"
  ON job_requests FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Client atualiza os seus jobs"
  ON job_requests FOR UPDATE TO authenticated
  USING (auth.uid() = client_id);

CREATE POLICY "Cliente cancela os seus jobs"
  ON job_requests FOR UPDATE TO authenticated
  USING (auth.uid() = client_id);

-- ─── job_photos ──────────────────────────────────────────────

CREATE POLICY "Ver fotos de jobs proprios ou abertos"
  ON job_photos FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id = job_photos.job_id
        AND  (client_id = auth.uid() OR status = 'open')
    )
  );

CREATE POLICY "Cliente adiciona fotos aos seus jobs"
  ON job_photos FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id = job_photos.job_id AND client_id = auth.uid()
    )
  );

CREATE POLICY "Client apaga fotos do seu job"
  ON job_photos FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id = job_photos.job_id AND client_id = auth.uid()
    )
  );

-- ─── job_proposals ───────────────────────────────────────────

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
      WHERE  id = job_proposals.job_id AND client_id = auth.uid()
    )
  );

CREATE POLICY "Worker atualiza as suas propostas"
  ON job_proposals FOR UPDATE TO authenticated
  USING     (auth.uid() = worker_id)
  WITH CHECK ((auth.uid() = worker_id) AND (status = 'superseded'));

-- ─── notifications ───────────────────────────────────────────
-- No INSERT policy for authenticated: all inserts go through
-- SECURITY DEFINER functions which bypass RLS.

CREATE POLICY "Utilizador vê as suas notificações"
  ON notifications FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Utilizador marca as suas notificações como lidas"
  ON notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);

-- ─── help_requests ───────────────────────────────────────────

CREATE POLICY "Worker principal vê os seus help requests"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE  id = help_requests.proposal_id AND worker_id = auth.uid()
    )
  );

CREATE POLICY "Worker candidato vê help requests onde se candidatou"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM help_acceptances
      WHERE  help_request_id = help_requests.id AND worker_id = auth.uid()
    )
  );

CREATE POLICY "Cliente vê help requests dos seus jobs"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE  id = help_requests.job_id AND client_id = auth.uid()
    )
  );

CREATE POLICY "Worker principal cria help requests"
  ON help_requests FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM job_proposals
      WHERE  id = help_requests.proposal_id
        AND  worker_id = auth.uid()
        AND  status    = 'accepted'
    )
  );

-- ─── help_acceptances ────────────────────────────────────────

CREATE POLICY "Worker vê as suas candidaturas"
  ON help_acceptances FOR SELECT TO authenticated
  USING (worker_id = auth.uid());

CREATE POLICY "Worker principal vê candidatos"
  ON help_acceptances FOR SELECT TO authenticated
  USING (is_principal_worker_for_help_request(help_request_id));

CREATE POLICY "Worker candidata-se a help_request"
  ON help_acceptances FOR INSERT TO authenticated
  WITH CHECK (
    (worker_id = auth.uid()) AND (status = 'pending')
  );

CREATE POLICY "Worker cancela ajuda"
  ON help_acceptances FOR UPDATE TO authenticated
  USING     (auth.uid() = worker_id)
  WITH CHECK ((auth.uid() = worker_id) AND (status = 'cancelled'));

CREATE POLICY "Worker principal decide candidatos"
  ON help_acceptances FOR UPDATE TO authenticated
  USING (is_principal_worker_for_help_request(help_request_id));

-- ─── ratings ─────────────────────────────────────────────────

CREATE POLICY "Leitura pública de avaliações"
  ON ratings FOR SELECT
  USING (true);

CREATE POLICY "Utilizador cria a sua avaliação"
  ON ratings FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = rater_id
    AND EXISTS (
      SELECT 1 FROM job_requests jr
      WHERE  jr.id     = ratings.job_id
        AND  jr.status = 'completed'
        AND (
          jr.client_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM job_proposals jp
            WHERE  jp.id = jr.accepted_proposal_id AND jp.worker_id = auth.uid()
          )
          OR EXISTS (
            SELECT 1
            FROM   help_requests    hr
            JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                                      AND ha.status = 'accepted'
                                      AND ha.worker_id = auth.uid()
            WHERE  hr.proposal_id = jr.accepted_proposal_id
          )
        )
    )
  );

-- ─── job_reports ─────────────────────────────────────────────

CREATE POLICY "Utilizador vê os seus reports"
  ON job_reports FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

CREATE POLICY "Participante pode reportar o seu job"
  ON job_reports FOR INSERT TO authenticated
  WITH CHECK (
    reporter_id = auth.uid()
    AND (
      EXISTS (
        SELECT 1 FROM job_requests
        WHERE  id = job_reports.job_id AND client_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM   job_requests jr
        JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
        WHERE  jr.id         = job_reports.job_id
          AND  jp.worker_id  = auth.uid()
      )
    )
  );


-- ══════════════════════════════════════════════════════════════
-- 7. FUNCTIONS
-- All functions are SECURITY DEFINER with SET search_path TO 'public'
-- unless noted otherwise.
--
-- Functions 1–4 are helpers used in RLS policies — must be defined
-- before the policies are evaluated (policies below CREATE POLICY are
-- fine; evaluation happens at query time, not creation time).
--
-- accept_proposal, create_proposal, sync_worker_service_types:
--   Auth-checked versions from archive/0032_audit_fixes.sql.
-- All other functions: exact bodies from snapshot_tables.csv (2026-07-09).
-- ══════════════════════════════════════════════════════════════

-- ── 1. worker_has_proposal_for_job (used in RLS policy) ─────────
-- Not in snapshot (not captured by snapshot query). From 0001_baseline.

CREATE OR REPLACE FUNCTION public.worker_has_proposal_for_job(job_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   job_proposals jp
    WHERE  jp.job_id    = worker_has_proposal_for_job.job_id
      AND  jp.worker_id = auth.uid()
  );
$$;

-- ── 2. is_principal_worker_for_help_request (used in RLS) ───────

CREATE OR REPLACE FUNCTION public.is_principal_worker_for_help_request(
  p_help_request_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.id        = p_help_request_id
      AND  jp.worker_id = auth.uid()
  );
$function$;

-- ── 3. client_has_confirmed_job_with_worker (used in RLS) ───────

CREATE OR REPLACE FUNCTION public.client_has_confirmed_job_with_worker(
  worker_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   job_requests  jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.client_id  = auth.uid()
      AND  jp.worker_id  = client_has_confirmed_job_with_worker.worker_id
      AND  jr.status     IN ('confirmed', 'awaiting_confirmation', 'completed')
  );
$function$;

-- ── 4. create_user_profile (admin/programmatic use) ─────────────
-- Not in snapshot. From 0001_baseline.

CREATE OR REPLACE FUNCTION public.create_user_profile(
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

-- ── 5. accept_proposal (0032: auth check added) ──────────────────
-- AUTH CHECK: caller must be the client of this job.

CREATE OR REPLACE FUNCTION public.accept_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id          uuid;
  v_scheduled_date     date;
  v_scheduled_time     time;
  v_scheduled_flexible boolean;
  v_people_needed      int;
  v_equipment_required boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM job_requests
    WHERE  id = p_job_id AND client_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode aceitar propostas.';
  END IF;

  SELECT worker_id, scheduled_date, scheduled_time, scheduled_flexible,
         people_needed, helpers_equipment_required
  INTO   v_worker_id, v_scheduled_date, v_scheduled_time, v_scheduled_flexible,
         v_people_needed, v_equipment_required
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'accepted', updated_at = now()
  WHERE id = p_proposal_id;

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

  IF v_people_needed > 1 THEN
    INSERT INTO help_requests (
      job_id, proposal_id, slots_needed,
      equipment_required, created_post_confirmation, status
    ) VALUES (
      p_job_id, p_proposal_id, v_people_needed - 1,
      COALESCE(v_equipment_required, false), false, 'open'
    );
  END IF;

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
$function$;

-- ── 6. create_proposal (0032: auth check added) ──────────────────
-- AUTH CHECK: worker can only create proposals as themselves.

CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_worker_id                  uuid,
  p_hourly_rate                numeric,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job_status  text;
  v_client_id   uuid;
BEGIN
  IF p_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

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

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = p_worker_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    status
  ) VALUES (
    p_job_id, p_worker_id, p_hourly_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
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
$function$;

-- ── 7. sync_worker_service_types (0032: auth check added) ────────
-- AUTH CHECK: workers can only sync their own service types.

CREATE OR REPLACE FUNCTION public.sync_worker_service_types(
  p_worker_id        uuid,
  p_service_type_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  DELETE FROM worker_service_types WHERE worker_id = p_worker_id;
  IF array_length(p_service_type_ids, 1) IS NOT NULL
     AND array_length(p_service_type_ids, 1) > 0 THEN
    INSERT INTO worker_service_types (worker_id, service_type_id)
    SELECT p_worker_id, unnest(p_service_type_ids);
  END IF;
END;
$function$;

-- ── 8. reject_proposal ──────────────────────────────────────────
-- Not in snapshot. From 0001_baseline.

CREATE OR REPLACE FUNCTION public.reject_proposal(
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

-- ── 9. withdraw_proposal ────────────────────────────────────────
-- Not in snapshot. From 0001_baseline.

CREATE OR REPLACE FUNCTION public.withdraw_proposal(
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
    WHERE  id        = p_proposal_id
      AND  job_id    = p_job_id
      AND  worker_id = auth.uid()
      AND  status    = 'pending'
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

-- ── 10. confirm_job_completion ───────────────────────────────────
-- Not in snapshot. From 0001_baseline.

CREATE OR REPLACE FUNCTION public.confirm_job_completion(p_job_id uuid)
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

-- ── 11. accept_help_candidate ────────────────────────────────────
-- From snapshot (exact body).

CREATE OR REPLACE FUNCTION public.accept_help_candidate(
  p_help_acceptance_id uuid,
  p_agreed_rate        numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_slots_needed        int;
  v_accepted_count      int;
  v_current_status      text;
  v_remaining_candidate RECORD;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id,
         hr.slots_needed, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id,
         v_slots_needed, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode aceitar candidatos.';
  END IF;
  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION 'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances
  SET    status = 'accepted', agreed_rate = p_agreed_rate
  WHERE  id = p_help_acceptance_id;

  SELECT COUNT(*) INTO v_accepted_count
  FROM   help_acceptances
  WHERE  help_request_id = v_help_request_id
    AND  status = 'accepted';

  IF v_accepted_count >= v_slots_needed THEN
    UPDATE help_requests SET status = 'filled' WHERE id = v_help_request_id;

    FOR v_remaining_candidate IN
      SELECT id, worker_id
      FROM   help_acceptances
      WHERE  help_request_id = v_help_request_id
        AND  status = 'pending'
        AND  id <> p_help_acceptance_id
    LOOP
      UPDATE help_acceptances SET status = 'rejected' WHERE id = v_remaining_candidate.id;
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_remaining_candidate.worker_id, 'help_rejected',
              'Candidatura não selecionada',
              'Todas as vagas foram preenchidas.',
              v_help_request_id, 'help_request');
    END LOOP;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_helper_worker_id, 'help_accepted', 'Candidatura aceite!',
    'Foste selecionado para fazer parte da equipa.',
    v_help_request_id, 'help_request'
  );
END;
$function$;

-- ── 12. accept_reschedule ────────────────────────────────────────
-- From snapshot.

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
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id;
  IF v_job IS NULL OR v_job.reschedule_status != 'pending' THEN
    RAISE EXCEPTION 'Sem remarcação pendente';
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
        updated_at               = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_accepted', 'Remarcação aceite',
    'A nova data foi aceite.', p_job_id, 'job_request');
END;
$function$;

-- ── 13. approve_help_request ─────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.approve_help_request(p_help_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status        text;
  v_job_client_id uuid;
  v_worker_id     uuid;
BEGIN
  SELECT hr.status, jr.client_id, jp.worker_id
  INTO   v_status, v_job_client_id, v_worker_id
  FROM   help_requests hr
  JOIN   job_requests  jr ON jr.id = hr.job_id
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  WHERE  hr.id = p_help_request_id
  FOR UPDATE OF hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'help_request não encontrado.';
  END IF;
  IF v_job_client_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o cliente do job pode aprovar este pedido de ajuda.';
  END IF;
  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'help_request não está em pending_approval (estado atual: %).', v_status;
  END IF;

  UPDATE help_requests SET status = 'open' WHERE id = p_help_request_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id, 'help_request_approved', 'Pedido de equipa aprovado',
    'O cliente aprovou o pedido de ajudantes. Podes agora aceitar candidatos.',
    p_help_request_id, 'help_request'
  );
END;
$function$;

-- ── 14. auto_confirm_completed_jobs ─────────────────────────────
-- From snapshot (version with client notification, from 0020).

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
    WHERE  status     = 'awaiting_confirmation'
      AND  updated_at < NOW() - INTERVAL '3 days'
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

-- ── 15. auto_expire_jobs ─────────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.auto_expire_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

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
END;
$function$;

-- ── 16. cancel_job ───────────────────────────────────────────────
-- From snapshot (full body with 24h rule, reopen, helper cascade).

CREATE OR REPLACE FUNCTION public.cancel_job(
  p_job_id              uuid,
  p_reason              text,
  p_reason_detail       text    DEFAULT NULL,
  p_client_wants_reopen boolean DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  IF v_job.status = 'confirmed'
     AND v_job.confirmed_date IS NOT NULL
     AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
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
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id, service_type_id, address_text,
      location_lat, location_lng,
      date_mode, preferred_date, availability_text,
      urgency, size_estimate, description,
      status, reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id, v_job.service_type_id, v_job.address_text,
      v_job.location_lat, v_job.location_lng,
      v_job.date_mode, v_job.preferred_date, v_job.availability_text,
      v_job.urgency, v_job.size_estimate, v_job.description,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded, now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto',
        'O pedido foi reaberto automaticamente.', v_new_job_id, 'job_request');
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$function$;

-- ── 17. get_accepted_helpers_for_job ────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.get_accepted_helpers_for_job(p_job_id uuid)
RETURNS TABLE(worker_id uuid, full_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT ha.worker_id, p.full_name
  FROM   job_requests     jr
  JOIN   job_proposals    jp ON jp.id  = jr.accepted_proposal_id
  JOIN   help_requests    hr ON hr.proposal_id = jp.id
  JOIN   help_acceptances ha ON ha.help_request_id = hr.id AND ha.status = 'accepted'
  JOIN   profiles          p ON p.id  = ha.worker_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid();
$function$;

-- ── 18. get_help_requests_in_radius ─────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  proposal_id               uuid,
  slots_needed              integer,
  status                    text,
  equipment_required        boolean,
  created_post_confirmation boolean,
  created_at                timestamptz,
  location_lat              double precision,
  location_lng              double precision,
  service_type_id           uuid,
  principal_name            text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
    hr.equipment_required, hr.created_post_confirmation, hr.created_at,
    jr.location_lat::double precision, jr.location_lng::double precision,
    jr.service_type_id, p.full_name AS principal_name
  FROM   help_requests  hr
  JOIN   job_requests   jr ON jr.id = hr.job_id
  JOIN   job_proposals  jp ON jp.id = hr.proposal_id
  JOIN   profiles        p ON p.id  = jp.worker_id
  WHERE  hr.status = 'open'
    AND  jr.status NOT IN ('cancelled', 'completed')
    AND  jp.worker_id <> auth.uid()
    AND  NOT EXISTS (
      SELECT 1 FROM help_acceptances ha
      WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid()
    )
    AND (
      2 * 6371 * asin(sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))
    ) <= radius_km
  ORDER BY
    power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
    + cos(radians(worker_lat))
      * cos(radians(jr.location_lat::double precision))
      * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
    ASC;
$function$;

-- ── 19. get_jobs_in_radius ───────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(
  worker_lat  numeric,
  worker_lng  numeric,
  radius_km   integer,
  p_worker_id uuid DEFAULT NULL
)
RETURNS SETOF job_requests
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jr.*
  FROM   public.job_requests jr
  WHERE  jr.status = 'open'
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  (p_worker_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = p_worker_id AND jp.status = 'pending'
    ))
    AND (
      6371 * acos(
        cos(radians(worker_lat))
        * cos(radians(jr.location_lat))
        * cos(radians(jr.location_lng) - radians(worker_lng))
        + sin(radians(worker_lat)) * sin(radians(jr.location_lat))
      )
    ) <= radius_km
  ORDER BY (
    6371 * acos(
      cos(radians(worker_lat))
      * cos(radians(jr.location_lat))
      * cos(radians(jr.location_lng) - radians(worker_lng))
      + sin(radians(worker_lat)) * sin(radians(jr.location_lat))
    )
  ) ASC;
$function$;

-- ── 20. get_my_help_acceptances ──────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.get_my_help_acceptances()
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  service_type_name text,
  principal_name    text,
  job_status        text,
  job_id            uuid,
  principal_worker_id uuid,
  confirmed_date    date,
  confirmed_time    time,
  address_text      text,
  location_lat      numeric,
  location_lng      numeric,
  principal_phone   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.status, ha.agreed_rate, ha.brought_equipment, ha.created_at,
    st.name         AS service_type_name,
    p.full_name     AS principal_name,
    jr.status       AS job_status,
    jr.id           AS job_id,
    jp.worker_id    AS principal_worker_id,
    jr.confirmed_date, jr.confirmed_time, jr.address_text,
    jr.location_lat, jr.location_lng,
    p.phone         AS principal_phone
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER  BY ha.created_at DESC;
$function$;

-- ── 21. mark_job_done ────────────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.mark_job_done(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.job_proposals jp
    JOIN   public.job_requests  jr ON jr.id = jp.job_id
    WHERE  jp.job_id    = p_job_id
      AND  jp.worker_id = auth.uid()
      AND  jp.status    = 'accepted'
      AND  jr.status    = 'confirmed'
  ) THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  SELECT client_id INTO v_client_id FROM public.job_requests WHERE id = p_job_id;

  UPDATE public.job_requests
    SET status = 'awaiting_confirmation', updated_at = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_client_id, 'job_marked_done', 'Trabalho concluído!',
    'O jardineiro marcou o trabalho como concluído. Confirma se está satisfeito.',
    p_job_id, 'job_request');
END;
$function$;

-- ── 22. propose_reschedule ───────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.propose_reschedule(
  p_job_id       uuid,
  p_new_date     date,
  p_new_time     time    DEFAULT NULL,
  p_new_flexible boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id       uuid := auth.uid();
  v_job           public.job_requests;
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id;
  IF v_job IS NULL OR v_job.status != 'confirmed' THEN
    RAISE EXCEPTION 'Só jobs confirmados podem ser remarcados';
  END IF;
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date - current_date < 1 THEN
    RAISE EXCEPTION 'Não pode remarcar com menos de 24h de antecedência';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF v_job.reschedule_status = 'pending' THEN
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

-- ── 23. reject_help_candidate ────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.reject_help_candidate(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_current_status      text;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode rejeitar candidatos.';
  END IF;
  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION 'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances SET status = 'rejected' WHERE id = p_help_acceptance_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_helper_worker_id, 'help_rejected', 'Candidatura não selecionada',
    'O worker principal não selecionou a tua candidatura.',
    v_help_request_id, 'help_request');
END;
$function$;

-- ── 24. reject_reschedule ────────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.reject_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id     uuid := auth.uid();
  v_job         public.job_requests;
  v_is_client   boolean;
  v_is_worker   boolean;
  v_proposer_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id;
  IF v_job IS NULL OR v_job.reschedule_status != 'pending' THEN
    RAISE EXCEPTION 'Sem remarcação pendente';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF v_job.reschedule_proposed_by = v_user_id THEN
    RAISE EXCEPTION 'Não pode recusar a sua própria remarcação';
  END IF;
  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;

  v_proposer_id := v_job.reschedule_proposed_by;

  UPDATE public.job_requests
    SET reschedule_proposed_date     = null,
        reschedule_proposed_time     = null,
        reschedule_proposed_flexible = null,
        reschedule_proposed_by       = null,
        reschedule_status            = 'rejected',
        updated_at                   = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_rejected', 'Remarcação recusada',
    'A nova data foi recusada. Mantém-se a data original.',
    p_job_id, 'job_request');
END;
$function$;

-- ── 25. submit_client_rating ─────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.submit_client_rating(
  p_job_id  uuid,
  p_stars   integer,
  p_comment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_helper    RECORD;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode submeter esta avaliação.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Proposta aceite não encontrada.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  FOR v_helper IN
    SELECT ha.worker_id
    FROM   help_requests    hr
    JOIN   help_acceptances ha ON ha.help_request_id = hr.id AND ha.status = 'accepted'
    WHERE  hr.proposal_id = v_job.accepted_proposal_id
  LOOP
    INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
    VALUES (p_job_id, auth.uid(), v_helper.worker_id, p_stars, NULL)
    ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
  END LOOP;
END;
$function$;

-- ── 26. submit_helper_rating ─────────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.submit_helper_rating(
  p_job_id  uuid,
  p_stars   integer,
  p_comment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_is_helper boolean;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM   help_requests    hr
    JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                              AND ha.status = 'accepted'
                              AND ha.worker_id = auth.uid()
    WHERE  hr.proposal_id = v_job.accepted_proposal_id
  ) INTO v_is_helper;

  IF NOT v_is_helper THEN
    RAISE EXCEPTION 'Não autorizado: só ajudantes aceites podem submeter esta avaliação.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
END;
$function$;

-- ── 27. submit_principal_rating ──────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.submit_principal_rating(
  p_job_id   uuid,
  p_ratee_id uuid,
  p_stars    integer,
  p_comment  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_valid     boolean := false;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o prestador principal pode submeter esta avaliação.';
  END IF;

  IF p_ratee_id = v_job.client_id THEN v_valid := true; END IF;

  IF NOT v_valid THEN
    SELECT EXISTS (
      SELECT 1
      FROM   help_requests    hr
      JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                                AND ha.status = 'accepted'
                                AND ha.worker_id = p_ratee_id
      WHERE  hr.proposal_id = v_job.accepted_proposal_id
    ) INTO v_valid;
  END IF;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'Não autorizado: o utilizador avaliado não é participante deste trabalho.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), p_ratee_id, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
END;
$function$;

-- ── 28. withdraw_help_acceptance ────────────────────────────────
-- From snapshot.

CREATE OR REPLACE FUNCTION public.withdraw_help_acceptance(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id           uuid;
  v_help_request_id     uuid;
  v_help_request_status text;
  v_principal_worker_id uuid;
  v_current_status      text;
  v_job_status          text;
BEGIN
  SELECT ha.worker_id, ha.help_request_id, ha.status,
         hr.status, jp.worker_id
  INTO   v_worker_id, v_help_request_id, v_current_status,
         v_help_request_status, v_principal_worker_id
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Só podes retirar a tua própria candidatura.';
  END IF;
  IF v_current_status <> 'accepted' THEN
    RAISE EXCEPTION 'Só podes retirar uma candidatura aceite (estado atual: %).', v_current_status;
  END IF;

  SELECT jr.status INTO v_job_status
  FROM   job_requests  jr
  JOIN   help_requests hr ON hr.job_id = jr.id
  WHERE  hr.id = v_help_request_id;

  IF v_job_status NOT IN ('confirmed', 'awaiting_confirmation') THEN
    RAISE EXCEPTION 'Não é possível desistir: o trabalho já não está ativo.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  IF v_help_request_status = 'filled' THEN
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga para ajudante voltou a ficar disponível.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_principal_worker_id, 'help_withdrew', 'Ajudante desistiu',
    'Um ajudante retirou a sua aceitação.',
    v_help_request_id, 'help_request');
END;
$function$;

-- ── 29. prevent_profile_role_change (0032: new) ──────────────────
-- Guards against role escalation via direct PATCH on profiles.
-- WITH CHECK on UPDATE policy cannot reference OLD.role in PG RLS.

CREATE OR REPLACE FUNCTION public.prevent_profile_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'Não é permitido alterar o role do perfil.';
  END IF;
  RETURN NEW;
END;
$$;

-- ── 30. notify_workers_new_job (trigger function) ────────────────
-- Not in snapshot (not in snapshot query). From 0001_baseline.

CREATE OR REPLACE FUNCTION public.notify_workers_new_job()
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


-- ══════════════════════════════════════════════════════════════
-- 8. TRIGGERS
-- ══════════════════════════════════════════════════════════════

-- Notifies workers in radius when a new job is created.
DROP TRIGGER IF EXISTS trigger_notify_workers_new_job ON job_requests;
CREATE TRIGGER trigger_notify_workers_new_job
  AFTER INSERT ON job_requests
  FOR EACH ROW
  EXECUTE FUNCTION notify_workers_new_job();

-- Prevents role escalation via direct UPDATE on profiles (0032).
DROP TRIGGER IF EXISTS tg_prevent_profile_role_change ON profiles;
CREATE TRIGGER tg_prevent_profile_role_change
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_profile_role_change();


-- ══════════════════════════════════════════════════════════════
-- 9. VIEWS
-- ══════════════════════════════════════════════════════════════

-- worker_profiles_public: safe public columns (no home coordinates).
-- Deliberately WITHOUT security_invoker — runs as view owner so it can
-- read worker_profiles rows for non-owners despite the owner-only SELECT
-- policy. DO NOT add security_invoker=true: it would silently return
-- zero rows for non-owners, breaking all worker discovery features.
CREATE OR REPLACE VIEW public.worker_profiles_public AS
SELECT
  profile_id,
  bio,
  radius_km,
  tools,
  location_name,
  photos,
  created_at,
  updated_at
FROM worker_profiles;

GRANT SELECT ON public.worker_profiles_public TO authenticated;

-- worker_rating_summary: aggregate rating per worker.
-- security_invoker=true is correct here: ratings has USING(true) SELECT,
-- so the invoker's RLS lets all authenticated users read. security_invoker
-- prevents the view from being used to bypass RLS if ratings policies change.
CREATE OR REPLACE VIEW public.worker_rating_summary
WITH (security_invoker = true)
AS
SELECT
  ratee_id          AS worker_id,
  round(avg(stars), 1) AS avg_rating,
  count(*)          AS rating_count
FROM ratings
GROUP BY ratee_id;


-- ══════════════════════════════════════════════════════════════
-- 10. STORAGE
-- Storage buckets are created via Supabase dashboard or the
-- storage API. The INSERT below is idempotent via ON CONFLICT.
-- If you are applying to a fresh project, create buckets first
-- through the Supabase dashboard (Storage → New Bucket) and then
-- run this file, OR run the INSERT directly.
-- ══════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('avatars',    'avatars',    true),
  ('job-photos', 'job-photos', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies (exact names from live DB snapshot).

-- ── avatars ──────────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura pública de avatars"           ON storage.objects;
CREATE POLICY "Leitura pública de avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Upload avatar autenticado"             ON storage.objects;
CREATE POLICY "Upload avatar autenticado"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );

DROP POLICY IF EXISTS "avatars: update pelo próprio utilizador" ON storage.objects;
CREATE POLICY "avatars: update pelo próprio utilizador"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );

DROP POLICY IF EXISTS "avatars: delete pelo próprio utilizador" ON storage.objects;
CREATE POLICY "avatars: delete pelo próprio utilizador"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );

-- ── job-photos ───────────────────────────────────────────────
DROP POLICY IF EXISTS "Leitura publica de job-photos"        ON storage.objects;
CREATE POLICY "Leitura publica de job-photos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'job-photos');

DROP POLICY IF EXISTS "Upload autenticado em job-photos"     ON storage.objects;
CREATE POLICY "Upload autenticado em job-photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "job-photos: delete pelo dono"         ON storage.objects;
CREATE POLICY "job-photos: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );


-- ══════════════════════════════════════════════════════════════
-- 11. pg_cron JOBS
-- These are registered via cron.schedule(), which upserts by
-- jobname — safe to re-run. Requires the pg_cron extension to
-- be enabled in the Supabase dashboard first.
-- Verify after applying:
--   SELECT jobname, schedule, active FROM cron.job
--   WHERE jobname IN ('auto-expire-jobs', 'auto-confirm-completed-jobs');
-- ══════════════════════════════════════════════════════════════

SELECT cron.schedule(
  'auto-expire-jobs',
  '0 */3 * * *',
  'SELECT auto_expire_jobs()'
);

SELECT cron.schedule(
  'auto-confirm-completed-jobs',
  '0 */3 * * *',
  'SELECT auto_confirm_completed_jobs()'
);


-- ══════════════════════════════════════════════════════════════
-- 12. SEED DATA
-- Minimum data for a working dev/staging environment.
-- Idempotent via ON CONFLICT DO NOTHING.
-- ══════════════════════════════════════════════════════════════

INSERT INTO service_categories (id, slug, name, icon)
VALUES ('00000000-0000-0000-0000-000000000001', 'gardening', 'Jardinagem', 'park')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO service_types (category_id, slug, name)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'lawn_mowing',  'Corte de relva'),
  ('00000000-0000-0000-0000-000000000001', 'pruning',      'Poda'),
  ('00000000-0000-0000-0000-000000000001', 'garden_setup', 'Montagem de jardim')
ON CONFLICT (category_id, slug) DO NOTHING;
