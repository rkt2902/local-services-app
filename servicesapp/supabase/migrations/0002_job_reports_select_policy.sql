-- ==============================================================
-- supabase/migrations/0002_job_reports_select_policy.sql
-- Gap found during migrations-baseline review (2026-06-19):
-- job_reports had INSERT policy but no SELECT policy, so
-- reporters could not read back their own submitted reports.
-- ==============================================================

CREATE POLICY "Utilizador vê os seus reports"
  ON public.job_reports
  FOR SELECT
  USING (auth.uid() = reporter_id);
