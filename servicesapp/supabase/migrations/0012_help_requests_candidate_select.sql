-- Add missing SELECT policy for candidate workers on help_requests.
-- Without this policy, direct PostgREST fetches (fetchHelpRequestById,
-- fetchHelpRequestsForJob) returned null/empty for any worker who applied but
-- is not the principal — even for help_requests they have a candidacy on.
-- Discovery still worked via the SECURITY DEFINER RPC get_help_requests_in_radius
-- (which bypasses RLS), but any detail-screen reload after applying silently failed.
-- Identified in three-way crosscheck 2026-06-25, HIGH finding #3.
CREATE POLICY "Worker candidato vê help requests onde se candidatou"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM help_acceptances
      WHERE help_acceptances.help_request_id = help_requests.id
        AND help_acceptances.worker_id = auth.uid()
    )
  );

-- Drop duplicate job_proposals RLS policies left behind when separate migrations
-- added policies without checking for pre-existing ones with the same intent.
-- Keeping: "Worker envia proposta" (INSERT) and "Worker vê as suas propostas" (SELECT).
-- Dropping functional duplicates that only differ in name/accent.
-- Identified in three-way crosscheck 2026-06-25, MEDIUM finding.
DROP POLICY IF EXISTS "Worker cria propostas" ON job_proposals;
DROP POLICY IF EXISTS "Worker ve as suas propostas" ON job_proposals;
