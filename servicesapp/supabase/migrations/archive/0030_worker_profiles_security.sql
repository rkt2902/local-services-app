-- Migration 0030: worker_profiles security hardening + location_name column.
-- NOT APPLIED — apply manually via Supabase SQL Editor.
-- Apply ONLY after migration 0031 has been applied AND the Dart join fixes
-- (proposal_repository.dart, help_request_repository.dart) have been deployed
-- and verified working against the current unrestricted database.
-- Applying this migration before Phase B Dart code is live will break the
-- proposal candidate name/avatar display.
--
-- ═══════════════════════════════════════════════════════════════════════
-- DESIGN RATIONALE — READ BEFORE TOUCHING THIS MIGRATION
-- ═══════════════════════════════════════════════════════════════════════
--
-- The raw worker_profiles table is restricted to owner-only SELECT
-- (profile_id = auth.uid()). This is the ONLY guarantee that base_lat and
-- base_lng (exact home coordinates) cannot be read by any other user —
-- including via direct REST calls that bypass all Dart code entirely.
--
-- The worker_profiles_public view exposes the safe subset of columns
-- (bio, radius_km, tools, location_name, photos — NOT base_lat, NOT base_lng)
-- to any authenticated user. This view is created intentionally WITHOUT
-- security_invoker, meaning it runs as the view owner (definer-style),
-- which is PostgreSQL's default for views.
--
-- *** WHY NOT security_invoker=true? ***
-- With security_invoker=true the view enforces the caller's RLS on the
-- underlying table. After this migration, the table has only an owner-only
-- SELECT policy. A non-owner caller through a security_invoker view would
-- get ZERO ROWS with NO ERROR — silent data loss. The view would be useless.
--
-- *** DO NOT "fix" this view by adding security_invoker=true ***
-- It will silently break every feature that reads another worker's public
-- profile (worker discovery, proposal cards, help candidate display, future
-- worker profile pages) with no error message, no crash, just empty data.
--
-- This is categorically different from worker_rating_summary (migration 0028),
-- which CORRECTLY uses security_invoker=true. That view's underlying table
-- (ratings) has USING(true) — fully public SELECT. There is no restrictive
-- row filter to bypass, so security_invoker is safe and good hygiene there.
-- Here, worker_profiles has OWNER-ONLY SELECT after this migration, so the
-- view MUST bypass it to serve its purpose. Definer-style is not a mistake;
-- it is the intended mechanism for column-scoped public access on a row-restricted table.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Step 1: Add location_name (city/area, populated via Nominatim reverse geocoding)
ALTER TABLE worker_profiles
  ADD COLUMN IF NOT EXISTS location_name text;

-- ─── Step 2: Remove all broad SELECT policies on worker_profiles ──────────────
--
-- CONFIRM NAMES before applying — run this query and verify both names appear:
--   SELECT policyname, cmd, qual
--   FROM pg_policies
--   WHERE tablename = 'worker_profiles'
--   ORDER BY cmd, policyname;
--
-- Expected from migration files (applied):
--   "Worker profiles são públicos"                    — 0001_baseline.sql, USING(true)
--   "Cliente ve perfil de worker com job confirmado"  — 0027_doc_audit_fixes.sql
--
-- DROP POLICY IF EXISTS is safe even if a name is wrong (no-op), but a mismatch
-- means the old policy remains and base_lat/base_lng stay exposed. Verify first.

-- Root cause of F10-S4: USING(true) on worker_profiles exposed base_lat/base_lng
-- to every authenticated user via direct REST GET /worker_profiles.
DROP POLICY IF EXISTS "Worker profiles são públicos" ON worker_profiles;

-- From migration 0027: granted confirmed-job clients access to the FULL worker_profiles
-- row including base_lat/base_lng. Superseded by worker_profiles_public view below,
-- which covers the same use case without exposing coordinates.
DROP POLICY IF EXISTS "Cliente ve perfil de worker com job confirmado" ON worker_profiles;

-- Note: INSERT and UPDATE policies are unaffected — confirmed from 0001_baseline.sql:
--   "Worker cria o seu próprio worker profile"  — INSERT, USING(profile_id = auth.uid())
--   "Worker atualiza o seu próprio worker profile" — UPDATE, USING(profile_id = auth.uid())
-- Only SELECT is being changed here. RLS policies are scoped per command.

-- ─── Step 3: Owner-only SELECT — this is the actual security boundary ─────────
-- After this policy, base_lat and base_lng are unreadable by any caller except
-- the worker themselves. Dart code in worker_repository.dart (fetchProfile,
-- hasProfile) reads the owner's own row — continues to work under this policy.
CREATE POLICY "Worker lê o seu próprio perfil"
  ON worker_profiles FOR SELECT TO authenticated
  USING (profile_id = auth.uid());

-- ─── Step 4: Public view — safe columns, deliberately definer-style ───────────
-- Exposes bio, radius, tools, location_name and portfolio photos to any
-- authenticated user. Supports worker discovery, proposal cards, future
-- worker profile pages — all without exposing base_lat or base_lng.
-- No security_invoker — intentionally bypasses the table's owner-only RLS
-- to serve the non-owner callers. See rationale at the top of this file.
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
  -- deliberately excludes: base_lat, base_lng, default_hourly_rate
FROM worker_profiles;

GRANT SELECT ON public.worker_profiles_public TO authenticated;

-- After applying, notify PostgREST to reload its schema cache so the new
-- view becomes discoverable as an embedded resource:
--   NOTIFY pgrst, 'reload schema';
-- Or trigger a PostgREST restart from the Supabase dashboard.
