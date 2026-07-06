-- Migration 0031: Register missing FKs that allow PostgREST one-hop joins to profiles.
-- NOT APPLIED — apply manually via Supabase SQL Editor, before deploying Dart Phase B.
--
-- CONTEXT:
-- Both FKs are declared in 0001_baseline.sql's table bodies (job_proposals and
-- help_acceptances both have "worker_id ... REFERENCES worker_profiles(profile_id)"),
-- but were never registered in pg_constraint. Root cause: CREATE TABLE IF NOT EXISTS
-- silently skips the entire table body (including all FK clauses) when the table
-- already existed. This is the same mechanism as the worker_profiles_profile_id_fkey
-- gap fixed in migration 0029.
--
-- Without these FKs in pg_constraint, PostgREST cannot discover the relationship
-- job_proposals.worker_id → profiles.id, so the direct embedded join
-- "profiles!job_proposals_worker_id_fkey(full_name, avatar_url)" returns null.
--
-- WHY profiles(id), not worker_profiles(profile_id)?
-- We add a direct FK to profiles(id) (not to worker_profiles) so that
-- proposal_repository.dart and help_request_repository.dart can join to profiles
-- in one hop without routing through worker_profiles at all. After migration 0030
-- restricts worker_profiles SELECT to owner-only, the old two-hop path breaks.
-- The direct path is safer, simpler, and works regardless of worker_profiles RLS.
-- Data integrity: worker_id already equals profiles.id via the existing chain
-- (worker_profiles.profile_id = profiles.id), so all existing rows satisfy both
-- new constraints — adding them will never reject any existing data.
--
-- PURELY ADDITIVE — zero behavior change. Safe to apply at any time.

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'job_proposals_worker_id_fkey'
  ) THEN
    ALTER TABLE job_proposals
      ADD CONSTRAINT job_proposals_worker_id_fkey
      FOREIGN KEY (worker_id) REFERENCES profiles(id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'help_acceptances_worker_id_fkey'
  ) THEN
    ALTER TABLE help_acceptances
      ADD CONSTRAINT help_acceptances_worker_id_fkey
      FOREIGN KEY (worker_id) REFERENCES profiles(id);
  END IF;
END $$;
