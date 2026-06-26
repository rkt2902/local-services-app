-- ==============================================================
-- supabase/migrations/0017_help_candidate_autoreject.sql
--
-- P-9-1: accept_help_candidate now auto-rejects all remaining
-- pending candidates when accepted_count reaches slots_needed,
-- notifying each one immediately via 'help_rejected'.
--
-- Before applying, run the orphan-count diagnostic:
--   SELECT COUNT(*)
--   FROM   help_acceptances ha
--   JOIN   help_requests    hr ON hr.id = ha.help_request_id
--   WHERE  ha.status = 'pending'
--     AND  hr.status = 'filled';
-- The DO block below handles any count (idempotent if 0).
-- ==============================================================

-- ── accept_help_candidate (updated) ──────────────────────────
-- Identical to the 0004 body plus a FOR loop that rejects and
-- notifies all other pending candidates the moment slots_needed
-- is reached.

CREATE OR REPLACE FUNCTION accept_help_candidate(
  p_help_acceptance_id uuid,
  p_agreed_rate        numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_slots_needed        int;
  v_accepted_count      int;
  v_current_status      text;
  v_remaining_candidate RECORD;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id,
         hr.slots_needed, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id,
         v_slots_needed, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;

  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode aceitar candidatos.';
  END IF;

  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION
      'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances
  SET    status = 'accepted', agreed_rate = p_agreed_rate
  WHERE  id = p_help_acceptance_id;

  SELECT COUNT(*) INTO v_accepted_count
  FROM   help_acceptances
  WHERE  help_request_id = v_help_request_id
    AND  status = 'accepted';

  IF v_accepted_count >= v_slots_needed THEN
    UPDATE help_requests SET status = 'filled' WHERE id = v_help_request_id;

    FOR v_remaining_candidate IN
      SELECT id, worker_id
      FROM   help_acceptances
      WHERE  help_request_id = v_help_request_id
        AND  status = 'pending'
        AND  id <> p_help_acceptance_id
    LOOP
      UPDATE help_acceptances SET status = 'rejected' WHERE id = v_remaining_candidate.id;
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_remaining_candidate.worker_id, 'help_rejected',
              'Candidatura não selecionada',
              'Todas as vagas foram preenchidas.',
              v_help_request_id, 'help_request');
    END LOOP;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_helper_worker_id,
    'help_accepted',
    'Candidatura aceite!',
    'Foste selecionado para fazer parte da equipa.',
    v_help_request_id,
    'help_request'
  );
END;
$$;

-- ── One-time cleanup: orphaned pending candidates ─────────────
-- Rejects and notifies any help_acceptances still 'pending'
-- whose parent help_request is already 'filled'. These existed
-- before migration 0017 when accept_help_candidate did not
-- auto-reject remaining candidates on fill. Idempotent — only
-- touches status = 'pending' rows; safe to run if count is 0.
DO $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT ha.id, ha.worker_id, ha.help_request_id
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  ha.status = 'pending'
      AND  hr.status = 'filled'
  LOOP
    UPDATE help_acceptances SET status = 'rejected' WHERE id = v_rec.id;
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_rec.worker_id, 'help_rejected',
            'Candidatura não selecionada',
            'Todas as vagas foram preenchidas.',
            v_rec.help_request_id, 'help_request');
  END LOOP;
END;
$$;
