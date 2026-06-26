-- ============================================================
-- 0021_ratings_hardening.sql  — Fase 11 (Avaliações)
-- Apply manually via Supabase SQL Editor.
-- ============================================================

-- 1. Schema hardening: rater cannot be the same person as ratee
ALTER TABLE ratings
  ADD CONSTRAINT check_rater_not_ratee CHECK (rater_id <> ratee_id);


-- 2. Update get_my_help_acceptances to expose job_id + principal_worker_id
--    (needed so the helper card can call submit_helper_rating without extra round-trips)
CREATE OR REPLACE FUNCTION get_my_help_acceptances()
RETURNS TABLE(
  id                  uuid,
  help_request_id     uuid,
  status              text,
  agreed_rate         numeric,
  brought_equipment   boolean,
  created_at          timestamptz,
  service_type_name   text,
  principal_name      text,
  job_status          text,
  job_id              uuid,
  principal_worker_id uuid
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    ha.id,
    ha.help_request_id,
    ha.status,
    ha.agreed_rate,
    ha.brought_equipment,
    ha.created_at,
    st.name         AS service_type_name,
    p.full_name     AS principal_name,
    jr.status       AS job_status,
    jr.id           AS job_id,
    jp.worker_id    AS principal_worker_id
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER BY ha.created_at DESC;
$$;


-- 3. get_accepted_helpers_for_job
--    Returns the worker_id + full_name of each accepted helper for a job.
--    Only succeeds when the caller is the principal (accepted proposal worker).
CREATE OR REPLACE FUNCTION get_accepted_helpers_for_job(p_job_id uuid)
RETURNS TABLE(
  worker_id  uuid,
  full_name  text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    ha.worker_id,
    p.full_name
  FROM   job_requests     jr
  JOIN   job_proposals    jp ON jp.id  = jr.accepted_proposal_id
  JOIN   help_requests    hr ON hr.proposal_id = jp.id
  JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                            AND ha.status = 'accepted'
  JOIN   profiles          p ON p.id   = ha.worker_id
  WHERE  jr.id       = p_job_id
    AND  jp.worker_id = auth.uid();
$$;


-- 4. submit_client_rating
--    Client rates the job once; the given stars propagate to the principal worker
--    and every accepted helper. The comment is stored only on the principal's row.
--    Idempotent: ON CONFLICT DO NOTHING.
CREATE OR REPLACE FUNCTION submit_client_rating(
  p_job_id  uuid,
  p_stars   int,
  p_comment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_helper    RECORD;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode submeter esta avaliação.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp
  WHERE  jp.id = v_job.accepted_proposal_id;

  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Proposta aceite não encontrada.';
  END IF;

  -- Rate principal (carries comment)
  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- Rate each accepted helper (no comment propagated)
  FOR v_helper IN
    SELECT ha.worker_id
    FROM   help_requests    hr
    JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                              AND ha.status = 'accepted'
    WHERE  hr.proposal_id = v_job.accepted_proposal_id
  LOOP
    INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
    VALUES (p_job_id, auth.uid(), v_helper.worker_id, p_stars, NULL)
    ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
  END LOOP;
END;
$$;


-- 5. submit_principal_rating
--    Principal rates either the client or an accepted helper individually.
CREATE OR REPLACE FUNCTION submit_principal_rating(
  p_job_id   uuid,
  p_ratee_id uuid,
  p_stars    int,
  p_comment  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job      job_requests%ROWTYPE;
  v_principal uuid;
  v_valid    boolean := false;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp
  WHERE  jp.id = v_job.accepted_proposal_id;

  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o prestador principal pode submeter esta avaliação.';
  END IF;

  -- Allow rating the client
  IF p_ratee_id = v_job.client_id THEN
    v_valid := true;
  END IF;

  -- Allow rating an accepted helper
  IF NOT v_valid THEN
    SELECT EXISTS (
      SELECT 1
      FROM   help_requests    hr
      JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                                AND ha.status = 'accepted'
                                AND ha.worker_id = p_ratee_id
      WHERE  hr.proposal_id = v_job.accepted_proposal_id
    ) INTO v_valid;
  END IF;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'Não autorizado: o utilizador avaliado não é participante deste trabalho.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), p_ratee_id, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
END;
$$;


-- 6. submit_helper_rating
--    Accepted helper rates the principal worker.
--    Principal is auto-resolved from the accepted proposal.
CREATE OR REPLACE FUNCTION submit_helper_rating(
  p_job_id  uuid,
  p_stars   int,
  p_comment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_is_helper boolean;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM   help_requests    hr
    JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                              AND ha.status = 'accepted'
                              AND ha.worker_id = auth.uid()
    WHERE  hr.proposal_id = v_job.accepted_proposal_id
  ) INTO v_is_helper;

  IF NOT v_is_helper THEN
    RAISE EXCEPTION 'Não autorizado: só ajudantes aceites podem submeter esta avaliação.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp
  WHERE  jp.id = v_job.accepted_proposal_id;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;
END;
$$;
