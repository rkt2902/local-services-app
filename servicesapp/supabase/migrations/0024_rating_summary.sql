-- ============================================================
-- 0024_rating_summary.sql
-- Public view aggregating per-worker rating statistics.
-- Apply manually via Supabase SQL Editor.
-- ============================================================
--
-- Rationale for a VIEW rather than a SECURITY DEFINER function:
-- ratings already has SELECT USING (true) (public). A view is
-- the lightest-weight aggregate — no auth context needed, no
-- SECURITY DEFINER overhead, directly queryable via PostgREST
-- (.from('worker_rating_summary').select().eq('worker_id', id)).
--
-- RLS note: PostgreSQL views are NOT security_barrier by default,
-- meaning the underlying table's RLS policies are evaluated with
-- the calling role's permissions. Since ratings.SELECT USING (true)
-- allows all roles (anon + authenticated), the view is effectively
-- public. Explicit GRANT below ensures PostgREST can reach it.
-- ============================================================

CREATE OR REPLACE VIEW worker_rating_summary AS
SELECT
  ratee_id                        AS worker_id,
  ROUND(AVG(stars)::numeric, 1)   AS avg_rating,
  COUNT(*)                        AS rating_count
FROM ratings
GROUP BY ratee_id;

-- Grant PostgREST access for both anon and authenticated roles.
-- Views do not inherit grants from underlying tables.
GRANT SELECT ON worker_rating_summary TO anon, authenticated;
