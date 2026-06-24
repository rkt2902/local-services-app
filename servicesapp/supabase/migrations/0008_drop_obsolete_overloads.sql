-- ==============================================================
-- supabase/migrations/0008_drop_obsolete_overloads.sql
-- Removes two obsolete function overloads discovered during
-- manual deployment of migrations 0002-0007 on 2026-06-24.
--
-- Root cause: PostgreSQL's CREATE OR REPLACE creates a NEW
-- overload when the parameter list changes — it does NOT replace
-- an existing overload with a different signature.  Both functions
-- below were left live when their replacements were deployed via
-- CREATE OR REPLACE with a different parameter list.
--
-- Dropped overloads:
--   cancel_job(uuid)
--     Created interactively before migration tracking began.
--     Superseded by cancel_job(uuid, text, text) in 0001_baseline.
--
--   create_proposal(uuid, uuid, numeric, numeric, numeric,
--                   integer, text, date, text, boolean)
--     The 10-parameter version from 0001_baseline.sql.
--     Superseded when 0005 added p_helpers_equipment_required as
--     an 11th parameter via CREATE OR REPLACE — which created a
--     new overload instead of replacing the 10-param one.
--
-- VERIFY BEFORE RUNNING:
--   SELECT proname, pg_get_function_identity_arguments(oid) AS args
--   FROM pg_proc WHERE proname IN ('cancel_job', 'create_proposal');
--   Each function must appear exactly once after this migration.
-- ==============================================================


-- ─── cancel_job(uuid) — obsolete single-param overload ───────────────────────
-- Predates the p_reason / reopening logic introduced in 0001_baseline.
-- The live version is cancel_job(uuid, text, text DEFAULT NULL) — unaffected.

DROP FUNCTION IF EXISTS cancel_job(uuid);


-- ─── create_proposal — obsolete 10-param overload ────────────────────────────
-- The 0001_baseline declared p_scheduled_time as TEXT (the ::time cast is done
-- inside the function body).  The DROP below uses TEXT accordingly.
--
-- ⚠ IMPORTANT: If the live pg_proc query above shows the 9th argument type as
--   "time without time zone" instead of "text" (which would indicate an older
--   interactive version of the function was created directly in the SQL editor
--   with a different parameter type), change "text" to "time without time zone"
--   in the line below before running this migration.  Use IF EXISTS — a wrong
--   type signature causes the DROP to silently no-op rather than error.

DROP FUNCTION IF EXISTS create_proposal(
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  integer,
  text,
  date,
  text,
  boolean
);
