-- ==============================================================
-- supabase/migrations/0019_jobphotos_delete_policies.sql
--
-- P-FA2 + P-FA7: confirmed via live pg_policy query (2026-06-26)
-- that NO DELETE policy existed on storage.objects for job-photos
-- (not broken — simply absent; the 0001 baseline policy was either
-- never applied or dropped at some point).
-- Likewise, NO DELETE policy exists on the job_photos table (P-FA7).
--
-- Fix requires two coordinated changes:
--
-- (1) Dart (job_repository.dart): upload path changed from
--       '$jobId/<timestamp>.jpg'
--     to
--       '$clientId/$jobId/<timestamp>.jpg'
--     so that storage.foldername(name)[1] correctly extracts
--     clientId = auth.uid() for the storage DELETE policy.
--
-- (2) SQL (this file): new DELETE policies for both the storage
--     bucket and the job_photos table.
--
-- CAVEAT: photos uploaded BEFORE this migration retain the old
-- path format ($jobId/<timestamp>.jpg). For these rows,
-- storage.foldername(name)[1] extracts job_id — not client_id —
-- so they remain undeletable under the new storage policy.
-- No runtime impact: the app has no delete-photo UI feature yet.
-- ==============================================================

-- ── Storage DELETE policy (new — none existed) ────────────────
-- With the new upload path '$clientId/$jobId/<timestamp>.jpg',
-- foldername(name)[1] extracts clientId, which equals auth.uid()
-- for the client who created the job.
CREATE POLICY "job-photos: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- ── job_photos table DELETE policy (new — none existed) ───────
-- Uses EXISTS subquery since the table has no client_id column.
CREATE POLICY "Client apaga fotos do seu job"
  ON job_photos FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE id = job_photos.job_id
        AND client_id = auth.uid()
    )
  );
