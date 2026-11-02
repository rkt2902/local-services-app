-- ══════════════════════════════════════════════════════════════
-- 0068 — Correções da revisão de fluxos de 2026-11-02
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, depois da 0067
-- (PR #41). Não depende dela e pode correr-se mais do que uma vez.
--
-- 1. Proposta cujo dia já passou conta como expirada:
--    - `block_expired_proposal_accept` recusa aceitá-la (antes o cliente
--      aceitava e o trabalho ficava marcado no passado, sem se poder
--      cancelar, e o auto_expire_jobs fechava-o 3 dias depois);
--    - `get_pending_proposals_for_job` devolve-a com `is_expired = true`
--      (a app já a põe no fim da lista, a cinzento, sem "Aceitar");
--    - trigger novo em `job_proposals` recusa criar uma proposta para um
--      dia que já passou (a app já não deixa escolher, o servidor também
--      não).
-- 2. `cancel_job` (mesma assinatura):
--    - pedido reaberto com data fixa já passada passa a usar o dia que
--      estava marcado, ou data flexível; antes morria na corrida seguinte
--      do auto_expire_jobs;
--    - o pedido reaberto fica com as fotos do original;
--    - a regra das 24h usa today_pt() (hora de Lisboa), como o resto.
-- ══════════════════════════════════════════════════════════════

-- ── 1) Proposta com o dia já passado ─────────────────────────

CREATE OR REPLACE FUNCTION public.block_expired_proposal_accept()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    IF NEW.valid_until IS NOT NULL AND NEW.valid_until < today_pt() THEN
      RAISE EXCEPTION 'Este orçamento expirou e já não pode ser aceite.';
    END IF;
    -- 0068: o dia proposto já passou.
    IF NEW.scheduled_date IS NOT NULL AND NEW.scheduled_date < today_pt() THEN
      RAISE EXCEPTION 'Este orçamento expirou: o dia proposto já passou.';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.block_past_proposal_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.scheduled_date IS NOT NULL AND NEW.scheduled_date < today_pt() THEN
    RAISE EXCEPTION 'O dia proposto já passou. Escolhe hoje ou um dia a seguir.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_job_proposal_block_past_date ON public.job_proposals;
CREATE TRIGGER trg_job_proposal_block_past_date
  BEFORE INSERT ON public.job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.block_past_proposal_date();

CREATE OR REPLACE FUNCTION public.get_pending_proposals_for_job(p_job_id uuid)
 RETURNS TABLE(id uuid, job_id uuid, worker_id uuid, hourly_rate numeric, estimated_hours_min numeric, estimated_hours_max numeric, people_needed integer, helpers_equipment_required boolean, notes text, status text, scheduled_date date, scheduled_time time without time zone, scheduled_flexible boolean, created_at timestamp with time zone, worker_name text, worker_avatar_url text, pricing_mode text, total_price numeric, includes text[], estimated_days_min integer, estimated_days_max integer, valid_until date, is_expired boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    jp.id, jp.job_id, jp.worker_id, jp.hourly_rate, jp.estimated_hours_min,
    jp.estimated_hours_max, jp.people_needed, jp.helpers_equipment_required,
    jp.notes, jp.status, jp.scheduled_date, jp.scheduled_time,
    jp.scheduled_flexible, jp.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url,
    jp.pricing_mode, jp.total_price, jp.includes,
    jp.estimated_days_min, jp.estimated_days_max, jp.valid_until,
    (   (jp.valid_until IS NOT NULL AND jp.valid_until < today_pt())
     -- 0068: o dia proposto já passou.
     OR (jp.scheduled_date IS NOT NULL AND jp.scheduled_date < today_pt())
    ) AS is_expired
  FROM   job_proposals jp
  JOIN   profiles      p ON p.id = jp.worker_id
  WHERE  jp.job_id = p_job_id
    AND  jp.status = 'pending'
    AND  EXISTS (
      SELECT 1 FROM job_requests jr
      WHERE jr.id = jp.job_id AND jr.client_id = auth.uid()
    )
  ORDER BY jp.created_at ASC;
$function$;

-- ── 2) cancel_job: reabrir com data válida e com as fotos ────

CREATE OR REPLACE FUNCTION public.cancel_job(p_job_id uuid, p_reason text, p_reason_detail text DEFAULT NULL::text, p_client_wants_reopen boolean DEFAULT NULL::boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job           job_requests%ROWTYPE;
  v_caller_id     uuid    := auth.uid();
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
  v_can_reopen    boolean := false;
  v_new_excluded  uuid[];
  v_new_job_id    uuid    := NULL;
  v_date_mode     text;
  v_pref_date     date;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed') THEN
    RAISE EXCEPTION 'estado inválido: o pedido não pode ser cancelado no estado atual.';
  END IF;

  v_is_client := (v_job.client_id = v_caller_id);
  v_is_worker := v_job.status = 'confirmed' AND EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  id = v_job.accepted_proposal_id AND worker_id = v_caller_id
  );

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente ou o jardineiro do trabalho podem cancelar.';
  END IF;

  IF v_job.status = 'confirmed'
     AND v_job.confirmed_date IS NOT NULL
     AND (v_job.confirmed_date - today_pt()) < 1 THEN
    RAISE EXCEPTION 'O cancelamento requer pelo menos 24h de antecedência.';
  END IF;

  IF v_is_worker THEN
    v_other_user_id := v_job.client_id;
  ELSE
    SELECT worker_id INTO v_other_user_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;
  END IF;

  IF v_job.status = 'confirmed' THEN
    IF v_is_worker THEN
      IF v_job.reopen_count_worker < 2 THEN
        v_can_reopen := true;
      END IF;
    ELSE
      IF p_client_wants_reopen = true AND v_job.reopen_count_client < 1 THEN
        v_can_reopen := true;
      END IF;
    END IF;
  END IF;

  UPDATE job_requests
  SET status               = 'cancelled',
      cancelled_by         = v_caller_id,
      cancel_reason        = p_reason,
      cancel_reason_detail = p_reason_detail,
      cancelled_worker_id  = CASE WHEN v_is_worker THEN v_caller_id ELSE NULL END,
      updated_at           = now()
  WHERE id = p_job_id;

  UPDATE job_proposals
  SET status = 'rejected', updated_at = now()
  WHERE job_id = p_job_id AND status = 'pending';

  UPDATE help_requests
  SET    status = 'cancelled'
  WHERE  job_id = p_job_id AND status <> 'cancelled';

  UPDATE help_acceptances
  SET    status = 'rejected'
  WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = p_job_id)
    AND  status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado.',
         p_job_id, 'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id = p_job_id AND ha.status = 'accepted';

  IF v_other_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_other_user_id, 'job_cancelled', 'Pedido cancelado',
      'Um pedido foi cancelado.', p_job_id, 'job_request');
  END IF;

  IF v_can_reopen THEN
    v_new_excluded := v_job.excluded_worker_ids;

    -- 0068: data fixa que já passou (o jardineiro propôs outro dia e o
    -- original ficou para trás). Sem isto, auto_expire_jobs passava o
    -- pedido reaberto a no_response na corrida seguinte. Usa o dia que
    -- estava marcado (ainda futuro, o cancelamento exige 24h) ou, sem
    -- ele, passa a data flexível.
    v_date_mode := v_job.date_mode;
    v_pref_date := v_job.preferred_date;
    IF v_date_mode = 'fixed'
       AND (v_pref_date IS NULL OR v_pref_date < today_pt()) THEN
      IF v_job.confirmed_date IS NOT NULL
         AND v_job.confirmed_date >= today_pt() THEN
        v_pref_date := v_job.confirmed_date;
      ELSE
        v_date_mode := 'flexible';
        v_pref_date := NULL;
      END IF;
    END IF;
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id, service_type_id, address_text,
      location_lat, location_lng,
      date_mode, preferred_date, availability_text,
      urgency, size_estimate, description, location_area,
      status, reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id, v_job.service_type_id, v_job.address_text,
      v_job.location_lat, v_job.location_lng,
      v_date_mode, v_pref_date, v_job.availability_text,
      v_job.urgency, v_job.size_estimate, v_job.description, v_job.location_area,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded, now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    -- 0068: as fotos do pedido passam para o reaberto (mesmos ficheiros
    -- no Storage, só as linhas são copiadas).
    INSERT INTO job_photos (job_id, storage_path)
    SELECT v_new_job_id, storage_path
    FROM   job_photos
    WHERE  job_id = p_job_id
    ORDER  BY created_at;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto',
        'O pedido foi reaberto automaticamente.', v_new_job_id, 'job_request');
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$function$;
