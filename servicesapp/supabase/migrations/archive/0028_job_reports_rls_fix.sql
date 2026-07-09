-- ==============================================================
-- supabase/migrations/0028_job_reports_rls_fix.sql
-- Fase 10 security audit fixes.
--
-- F10-S1: Tighten job_reports INSERT policy to job participants only.
-- F10-S2: Capture security_invoker = true on worker_rating_summary
--         (was fixed in SQL Editor after 0024 — not reproducible
--          from migrations until now).
--
-- Policy names corrected after live DB verification — original file
-- had wrong names from migration assumption. Real names confirmed via
-- SELECT policyname FROM pg_policies WHERE tablename = 'job_reports'.
--
-- IMPORTANT: written but NOT applied to the live DB.
-- Apply manually via the Supabase SQL Editor.
-- ==============================================================


-- ── F10-S1 — job_reports: restrict INSERT to participants, preserve SELECT ────
--
-- Live DB had two policies on job_reports (confirmed via pg_policies):
--   "Utilizador cria o seu report"  (INSERT) — replaced below
--   "Utilizador vê os seus reports" (SELECT) — dropped and recreated unchanged
--
-- The INSERT policy only checked auth.uid() = reporter_id. Any authenticated
-- user could file a report for any job_id with no relationship to the job.
--
-- New INSERT policy: reporter must be the client of the job, or the accepted
-- worker. Helper workers are not included — they have no direct relationship
-- to job_requests.
--
-- SELECT policy is recreated identically (reporter sees own reports only).

DROP POLICY IF EXISTS "Utilizador cria o seu report" ON job_reports;
DROP POLICY IF EXISTS "Utilizador vê os seus reports" ON job_reports;

CREATE POLICY "Participante pode reportar o seu job"
  ON job_reports FOR INSERT TO authenticated
  WITH CHECK (
    reporter_id = auth.uid() AND (
      EXISTS (
        SELECT 1 FROM job_requests
        WHERE  id        = job_reports.job_id
          AND  client_id = auth.uid()
      ) OR EXISTS (
        SELECT 1
        FROM   job_requests  jr
        JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
        WHERE  jr.id        = job_reports.job_id
          AND  jp.worker_id  = auth.uid()
      )
    )
  );

CREATE POLICY "Utilizador vê os seus reports"
  ON job_reports FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());


-- ── F10-S2 — worker_rating_summary: permanent security_invoker capture ─────────
--
-- Migration 0024 created the view without security_invoker = true.
-- A direct SQL Editor fix was applied after 0024, but was not captured in
-- migrations. A fresh DB build or any CREATE OR REPLACE from 0024 would lose
-- the setting. This migration makes the security_invoker setting reproducible.
--
-- Behaviour note: ratings.SELECT USING (true) is already public for all roles,
-- so security_invoker vs definer makes no difference TODAY. The fix is forward-
-- looking: any future RLS tightening on ratings would be bypassed by a
-- security-definer view silently. With security_invoker = true the view honours
-- the caller's permissions.
--
-- GRANT is repeated because views do not inherit grants from underlying tables.

CREATE OR REPLACE VIEW public.worker_rating_summary
  WITH (security_invoker = true)
AS
SELECT
  ratee_id                      AS worker_id,
  ROUND(AVG(stars)::numeric, 1) AS avg_rating,
  COUNT(*)                      AS rating_count
FROM ratings
GROUP BY ratee_id;

GRANT SELECT ON public.worker_rating_summary TO authenticated, anon;
