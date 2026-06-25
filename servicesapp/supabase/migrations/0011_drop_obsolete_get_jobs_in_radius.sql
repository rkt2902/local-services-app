-- Drop the obsolete 3-arg overload of get_jobs_in_radius.
-- This overload predates the p_worker_id parameter and returns all matching
-- jobs without filtering the requesting worker from results, which is both
-- incorrect (workers see their own jobs in the discovery list) and a minor
-- information leak.
-- Confirmed still present in live DB via snapshot 2026-06-25 (02_functions.csv).
-- The 4-arg overload (worker_lat, worker_lng, radius_km, p_worker_id) is
-- unaffected and remains the only callable version after this drop.
DROP FUNCTION IF EXISTS get_jobs_in_radius(numeric, numeric, integer);
