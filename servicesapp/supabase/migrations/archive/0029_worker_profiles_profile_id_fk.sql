-- ==============================================================
-- supabase/migrations/0029_worker_profiles_profile_id_fk.sql
--
-- Bug 3 fix: PostgREST two-hop join
--   worker_profiles(profiles(full_name, avatar_url))
-- returns worker_profiles: {profiles: null} despite the live SQL
-- join (worker_profiles.profile_id → profiles.id) working correctly.
--
-- Root cause: the inline FOREIGN KEY declared in 0001_baseline.sql
-- (profile_id uuid PRIMARY KEY REFERENCES profiles(id)) may be
-- absent from the live DB if CREATE TABLE IF NOT EXISTS skipped the
-- table body because the table already existed without the FK.
-- PostgREST builds its schema cache from pg_constraint — if the FK
-- is not in pg_constraint, the second hop of the embedded join
-- cannot be resolved and returns null silently.
--
-- Fix: ensure the FK exists with the standard auto-generated name
-- (worker_profiles_profile_id_fkey) so PostgREST can discover it.
-- The DO block is a no-op if the FK already exists.
--
-- After applying this migration the select string in
-- proposal_repository.dart uses the explicit FK hint
--   profiles!worker_profiles_profile_id_fkey(...)
-- to make the disambiguation unambiguous even if PostgREST finds
-- multiple relationships from worker_profiles to other tables.
--
-- IMPORTANT: written but NOT applied to the live DB.
-- Apply manually via the Supabase SQL Editor.
-- ==============================================================

DO $$
BEGIN
  -- Only add the FK if no FK on worker_profiles.profile_id exists yet.
  -- Checks by column name so it is safe regardless of the constraint name
  -- that was auto-generated when the table was first created.
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.referential_constraints rc
    JOIN   information_schema.key_column_usage        kcu
           ON  kcu.constraint_name  = rc.constraint_name
           AND kcu.constraint_schema = rc.constraint_schema
    WHERE  kcu.table_schema  = 'public'
      AND  kcu.table_name    = 'worker_profiles'
      AND  kcu.column_name   = 'profile_id'
  ) THEN
    ALTER TABLE public.worker_profiles
      ADD CONSTRAINT worker_profiles_profile_id_fkey
      FOREIGN KEY (profile_id)
      REFERENCES public.profiles (id)
      ON DELETE CASCADE;
  END IF;
END $$;
