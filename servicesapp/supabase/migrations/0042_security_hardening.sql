-- ============================================================
-- 0042_security_hardening.sql
-- NOVA — NÃO APLICADA. Aplicar manualmente via SQL Editor.
--
-- Contexto: review de código de 2026-10-16
-- (/mnt/project-files/projardim/review/2026-10-16-review-codigo.md).
-- Corrige as falhas de segurança S1 a S9, S11 e S12, os bugs B2 e B4
-- (lado BD), e P1/P3 (limpeza de notificações e índices).
--
-- Princípio: a app já faz quase tudo por RPC. Esta migration fecha os
-- caminhos de escrita direta (REST/PostgREST) que permitiam saltar as
-- regras dessas RPCs, e acrescenta autorização às RPCs que não a tinham.
--
-- Escritas diretas que a app CONTINUA a fazer (e que continuam
-- permitidas, agora com WITH CHECK apertado):
--   job_requests INSERT (criar pedido), job_photos INSERT/DELETE,
--   help_requests INSERT (pedido de ajudantes pós-confirmação),
--   help_acceptances INSERT (candidatura), profiles, worker_profiles,
--   notifications UPDATE (só a coluna `read`), job_reports INSERT,
--   worker_fleet_cards INSERT.
--
-- Nenhuma assinatura de RPC muda (sem DROP de overloads), por isso a app
-- atual continua a funcionar antes e depois de aplicar.
--
-- É idempotente: pode ser corrida mais que uma vez.
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- 1. S2 — create_user_profile: aceitava user_id da app, sem auth
--    (qualquer pessoa, até sem login, reescrevia nome/telefone de
--    qualquer utilizador). A app não a usa.
-- ══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_user_profile(uuid, text, text, text);


-- ══════════════════════════════════════════════════════════════
-- 2. Helpers SECURITY DEFINER para as policies novas
-- ══════════════════════════════════════════════════════════════

-- Um candidato não consegue ler o help_request antes de se candidatar
-- (RLS de help_requests), por isso a validação do INSERT em
-- help_acceptances precisa de um helper que corra como dono.
CREATE OR REPLACE FUNCTION public.help_request_open_for_candidate(
  p_help_request_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    JOIN   job_requests  jr ON jr.id = hr.job_id
    WHERE  hr.id        = p_help_request_id
      AND  hr.status    = 'open'
      AND  jr.status    IN ('confirmed', 'awaiting_confirmation')
      AND  jp.worker_id <> auth.uid()
      AND  jr.client_id <> auth.uid()
  );
$function$;

-- Limite simples anti-spam: cada pedido novo notifica (e faz push a)
-- todos os jardineiros no raio.
CREATE OR REPLACE FUNCTION public.client_recent_job_count()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COUNT(*)::integer
  FROM   job_requests
  WHERE  client_id  = auth.uid()
    AND  created_at > now() - interval '1 hour';
$function$;


-- ══════════════════════════════════════════════════════════════
-- 3. job_requests — S4/S5
-- ══════════════════════════════════════════════════════════════

-- UPDATE direto permitia ao cliente mudar qualquer coluna (status
-- 'completed', accepted_proposal_id, contadores de reabertura...). A app
-- não faz UPDATE direto: tudo passa por RPCs SECURITY DEFINER.
DROP POLICY IF EXISTS "Client atualiza os seus jobs"  ON job_requests;
DROP POLICY IF EXISTS "Cliente cancela os seus jobs" ON job_requests;

-- INSERT só de pedidos novos, no estado inicial. cancel_job (SECURITY
-- DEFINER) continua a poder criar o pedido reaberto.
DROP POLICY IF EXISTS "Client cria jobs" ON job_requests;
CREATE POLICY "Client cria jobs"
  ON job_requests FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = client_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE  id = auth.uid() AND role = 'client'
    )
    AND status                   = 'open'
    AND accepted_proposal_id     IS NULL
    AND proposal_count           = 0
    AND confirmed_date           IS NULL
    AND confirmed_time           IS NULL
    AND cancelled_by             IS NULL
    AND cancelled_worker_id      IS NULL
    AND cancel_reason            IS NULL
    AND reopened_from            IS NULL
    AND reopen_count_client      = 0
    AND reopen_count_worker      = 0
    AND reschedule_status        IS NULL
    AND reschedule_proposed_by   IS NULL
    AND excluded_worker_ids      = '{}'
    AND expires_at               <= now() + interval '49 hours'
    AND client_recent_job_count() < 5
  );


-- ══════════════════════════════════════════════════════════════
-- 4. job_proposals — S3
-- ══════════════════════════════════════════════════════════════

-- INSERT direto aceitava qualquer status (ex.: 'accepted' em pedido de
-- outro → telefone/morada do cliente + mark_job_done). A app só usa a
-- RPC create_proposal. UPDATE direto também não é usado (withdraw_proposal
-- é RPC).
DROP POLICY IF EXISTS "Worker envia proposta"             ON job_proposals;
DROP POLICY IF EXISTS "Worker atualiza as suas propostas" ON job_proposals;


-- ══════════════════════════════════════════════════════════════
-- 5. ratings — S4
-- ══════════════════════════════════════════════════════════════

-- A policy não validava o ratee_id. As 3 RPCs submit_*_rating são o único
-- caminho de escrita da app e validam a participação de ambos.
DROP POLICY IF EXISTS "Utilizador cria a sua avaliação" ON ratings;


-- ══════════════════════════════════════════════════════════════
-- 6. help_requests / help_acceptances — S8/S9
-- ══════════════════════════════════════════════════════════════

-- A app só cria help_requests diretamente depois da confirmação, e esses
-- precisam de aprovação do cliente. Os pedidos 'open' de raiz só nascem
-- em accept_proposal (SECURITY DEFINER).
DROP POLICY IF EXISTS "Worker principal cria help requests" ON help_requests;
CREATE POLICY "Worker principal cria help requests"
  ON help_requests FOR INSERT TO authenticated
  WITH CHECK (
    status = 'pending_approval'
    AND created_post_confirmation = true
    AND EXISTS (
      SELECT 1
      FROM   job_proposals jp
      JOIN   job_requests  jr ON jr.id = jp.job_id
      WHERE  jp.id                   = help_requests.proposal_id
        AND  jp.worker_id            = auth.uid()
        AND  jp.status               = 'accepted'
        AND  jr.id                   = help_requests.job_id
        AND  jr.accepted_proposal_id = jp.id
        AND  jr.status               = 'confirmed'
    )
  );

DROP POLICY IF EXISTS "Worker candidata-se a help_request" ON help_acceptances;
CREATE POLICY "Worker candidata-se a help_request"
  ON help_acceptances FOR INSERT TO authenticated
  WITH CHECK (
    worker_id   = auth.uid()
    AND status  = 'pending'
    AND agreed_rate = 0
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE  id = auth.uid() AND role = 'worker'
    )
    AND help_request_open_for_candidate(help_request_id)
  );

-- UPDATE direto deixava o principal aceitar candidatos (e definir
-- agreed_rate) sem passar pela RPC, e o candidato cancelar sem reabrir a
-- vaga nem notificar. A app usa só RPCs (accept/reject_help_candidate,
-- withdraw_help_acceptance).
DROP POLICY IF EXISTS "Worker principal decide candidatos" ON help_acceptances;
DROP POLICY IF EXISTS "Worker cancela ajuda"               ON help_acceptances;


-- ══════════════════════════════════════════════════════════════
-- 7. worker_fleet_cards — S7 (auto-ativação)
-- ══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Worker pede um cartão frota" ON worker_fleet_cards;
CREATE POLICY "Worker pede um cartão frota"
  ON worker_fleet_cards FOR INSERT TO authenticated
  WITH CHECK (worker_id = auth.uid() AND status = 'pending');


-- ══════════════════════════════════════════════════════════════
-- 8. notifications — só a coluna `read` é editável pelo dono
-- ══════════════════════════════════════════════════════════════

REVOKE UPDATE ON public.notifications FROM anon, authenticated;
GRANT  UPDATE (read) ON public.notifications TO authenticated;

DROP POLICY IF EXISTS "Utilizador marca as suas notificações como lidas" ON notifications;
CREATE POLICY "Utilizador marca as suas notificações como lidas"
  ON notifications FOR UPDATE TO authenticated
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);


-- ══════════════════════════════════════════════════════════════
-- 9. profiles — S3: o worker só vê o cliente do job em que é mesmo o
--    worker aceite (antes bastava ter uma proposta com status
--    'accepted', que se podia forjar por INSERT direto).
-- ══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Worker ve perfil de cliente com job confirmado" ON profiles;
CREATE POLICY "Worker ve perfil de cliente com job confirmado"
  ON profiles FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   job_requests  jr
      JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
      WHERE  jp.worker_id = auth.uid()
        AND  jr.client_id = profiles.id
    )
  );


-- ══════════════════════════════════════════════════════════════
-- 10. RPCs — autorização em falta
-- ══════════════════════════════════════════════════════════════

-- ── 10.1 S1 — cancel_job ────────────────────────────────────────
-- Antes: v_is_worker := (client_id <> caller), ou seja, QUALQUER conta
-- que não fosse o cliente era tratada como o worker. Agora: só o cliente
-- (open/confirmed) ou o worker da proposta aceite (confirmed).
-- Resto do corpo igual ao baseline (24h, reabertura, cascade de ajudantes).

CREATE OR REPLACE FUNCTION public.cancel_job(
  p_job_id              uuid,
  p_reason              text,
  p_reason_detail       text    DEFAULT NULL,
  p_client_wants_reopen boolean DEFAULT NULL
)
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
     AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
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
    IF v_is_worker THEN
      v_new_excluded := array_append(v_new_excluded, v_caller_id);
    END IF;

    INSERT INTO job_requests (
      client_id, service_type_id, address_text,
      location_lat, location_lng,
      date_mode, preferred_date, availability_text,
      urgency, size_estimate, description,
      status, reopened_from,
      reopen_count_client, reopen_count_worker,
      excluded_worker_ids, expires_at
    ) VALUES (
      v_job.client_id, v_job.service_type_id, v_job.address_text,
      v_job.location_lat, v_job.location_lng,
      v_job.date_mode, v_job.preferred_date, v_job.availability_text,
      v_job.urgency, v_job.size_estimate, v_job.description,
      'open', p_job_id,
      CASE WHEN NOT v_is_worker THEN v_job.reopen_count_client + 1
           ELSE v_job.reopen_count_client END,
      CASE WHEN v_is_worker THEN v_job.reopen_count_worker + 1
           ELSE v_job.reopen_count_worker END,
      v_new_excluded, now() + interval '48 hours'
    )
    RETURNING id INTO v_new_job_id;

    IF v_is_worker THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto',
        'O pedido foi reaberto automaticamente.', v_new_job_id, 'job_request');
    END IF;
  END IF;

  RETURN v_new_job_id;
END;
$function$;

-- ── 10.2 S6 — reject_proposal: só o cliente do pedido ───────────

CREATE OR REPLACE FUNCTION public.reject_proposal(
  p_proposal_id uuid,
  p_job_id      uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_worker_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM job_requests
    WHERE  id = p_job_id AND client_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode recusar propostas.';
  END IF;

  SELECT worker_id INTO v_worker_id
  FROM   job_proposals
  WHERE  id = p_proposal_id AND job_id = p_job_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou já processada.';
  END IF;

  UPDATE job_proposals
  SET status = 'rejected', updated_at = now()
  WHERE id = p_proposal_id;

  UPDATE job_requests
  SET proposal_count = GREATEST(proposal_count - 1, 0),
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id,
    'proposal_rejected',
    'Proposta não selecionada',
    'O cliente recusou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$$;

-- ── 10.3 S3 — mark_job_done: só o worker da proposta ACEITE do job ──
-- (antes bastava qualquer proposta com status 'accepted' nesse job)

CREATE OR REPLACE FUNCTION public.mark_job_done(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  SELECT jr.client_id INTO v_client_id
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  UPDATE public.job_requests
    SET status = 'awaiting_confirmation', updated_at = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_client_id, 'job_marked_done', 'Trabalho concluído!',
    'O jardineiro marcou o trabalho como concluído. Confirma se está satisfeito.',
    p_job_id, 'job_request');
END;
$function$;

-- ── 10.4 S13 — create_proposal: validações em falta ─────────────
-- Assinatura igual (a app ainda envia p_worker_id; continua a ser
-- comparado com auth.uid()). Novo: worker de facto, não o próprio
-- cliente, não excluído do pedido, preço > 0.

CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_worker_id                  uuid,
  p_hourly_rate                numeric,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job         job_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM worker_profiles WHERE profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Só jardineiros podem enviar propostas.';
  END IF;

  IF p_hourly_rate IS NULL OR p_hourly_rate <= 0 THEN
    RAISE EXCEPTION 'O preço por hora tem de ser maior que zero.';
  END IF;

  IF p_people_needed IS NULL OR p_people_needed < 1 THEN
    RAISE EXCEPTION 'Número de pessoas inválido.';
  END IF;

  SELECT * INTO v_job
  FROM   job_requests
  WHERE  id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;
  IF v_job.client_id = auth.uid() THEN
    RAISE EXCEPTION 'Não podes enviar proposta para o teu próprio pedido.';
  END IF;
  IF auth.uid() = ANY(v_job.excluded_worker_ids) THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tens uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    status
  ) VALUES (
    p_job_id, auth.uid(), p_hourly_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
    'pending'
  )
  RETURNING id INTO v_proposal_id;

  UPDATE job_requests
  SET proposal_count = proposal_count + 1,
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'proposal_received',
    'Nova proposta recebida',
    'Um jardineiro enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$function$;

-- ── 10.5 S8 — accept_help_candidate: só com o pedido de ajuda 'open'
-- (antes aceitava candidatos enquanto o cliente ainda não tinha aprovado)

CREATE OR REPLACE FUNCTION public.accept_help_candidate(
  p_help_acceptance_id uuid,
  p_agreed_rate        numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_slots_needed        int;
  v_accepted_count      int;
  v_current_status      text;
  v_hr_status           text;
  v_remaining_candidate RECORD;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id,
         hr.slots_needed, ha.status, hr.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id,
         v_slots_needed, v_current_status, v_hr_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha, hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode aceitar candidatos.';
  END IF;
  IF v_hr_status <> 'open' THEN
    RAISE EXCEPTION 'O pedido de ajuda não está aberto (estado atual: %).', v_hr_status;
  END IF;
  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION 'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;
  IF p_agreed_rate IS NULL OR p_agreed_rate <= 0 THEN
    RAISE EXCEPTION 'A taxa acordada tem de ser maior que zero.';
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
    v_helper_worker_id, 'help_accepted', 'Candidatura aceite!',
    'Foste selecionado para fazer parte da equipa.',
    v_help_request_id, 'help_request'
  );
END;
$function$;

-- ── 10.6 B4 — remarcações: data futura e pedido ainda confirmado ──

CREATE OR REPLACE FUNCTION public.propose_reschedule(
  p_job_id       uuid,
  p_new_date     date,
  p_new_time     time    DEFAULT NULL,
  p_new_flexible boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id       uuid := auth.uid();
  v_job           public.job_requests;
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.status != 'confirmed' THEN
    RAISE EXCEPTION 'Só jobs confirmados podem ser remarcados';
  END IF;
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date - current_date < 1 THEN
    RAISE EXCEPTION 'Não pode remarcar com menos de 24h de antecedência';
  END IF;
  IF p_new_date IS NULL OR p_new_date - current_date < 1 THEN
    RAISE EXCEPTION 'A nova data tem de ser pelo menos amanhã';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;
  IF v_job.reschedule_status = 'pending' THEN
    RAISE EXCEPTION 'Já existe uma remarcação pendente';
  END IF;

  UPDATE public.job_requests
    SET reschedule_proposed_date     = p_new_date,
        reschedule_proposed_time     = p_new_time,
        reschedule_proposed_flexible = p_new_flexible,
        reschedule_proposed_by       = v_user_id,
        reschedule_status            = 'pending',
        updated_at                   = now()
    WHERE id = p_job_id;

  IF v_is_client THEN
    SELECT worker_id INTO v_other_user_id
    FROM   public.job_proposals WHERE id = v_job.accepted_proposal_id;
  ELSE
    v_other_user_id := v_job.client_id;
  END IF;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_other_user_id, 'reschedule_proposed', 'Pedido de remarcação',
    'A outra parte propôs uma nova data para o trabalho.',
    p_job_id, 'job_request');
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id   uuid := auth.uid();
  v_job       public.job_requests;
  v_is_client boolean;
  v_is_worker boolean;
  v_proposer_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.reschedule_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Sem remarcação pendente';
  END IF;
  IF v_job.status <> 'confirmed' THEN
    RAISE EXCEPTION 'O trabalho já não está confirmado';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF v_job.reschedule_proposed_by = v_user_id THEN
    RAISE EXCEPTION 'Não pode aceitar a sua própria remarcação';
  END IF;
  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;

  v_proposer_id := v_job.reschedule_proposed_by;

  UPDATE public.job_requests
    SET confirmed_date           = reschedule_proposed_date,
        confirmed_time           = reschedule_proposed_time,
        confirmed_flexible       = reschedule_proposed_flexible,
        reschedule_proposed_date = null,
        reschedule_proposed_time = null,
        reschedule_proposed_flexible = null,
        reschedule_proposed_by   = null,
        reschedule_status        = 'accepted',
        updated_at               = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_accepted', 'Remarcação aceite',
    'A nova data foi aceite.', p_job_id, 'job_request');
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_reschedule(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id     uuid := auth.uid();
  v_job         public.job_requests;
  v_is_client   boolean;
  v_is_worker   boolean;
  v_proposer_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.reschedule_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Sem remarcação pendente';
  END IF;
  IF v_job.status <> 'confirmed' THEN
    RAISE EXCEPTION 'O trabalho já não está confirmado';
  END IF;

  v_is_client := (v_job.client_id = v_user_id);
  SELECT EXISTS(
    SELECT 1 FROM public.job_proposals
    WHERE id = v_job.accepted_proposal_id AND worker_id = v_user_id
  ) INTO v_is_worker;

  IF v_job.reschedule_proposed_by = v_user_id THEN
    RAISE EXCEPTION 'Não pode recusar a sua própria remarcação';
  END IF;
  IF NOT (v_is_client OR v_is_worker) THEN
    RAISE EXCEPTION 'Não autorizado';
  END IF;

  v_proposer_id := v_job.reschedule_proposed_by;

  UPDATE public.job_requests
    SET reschedule_proposed_date     = null,
        reschedule_proposed_time     = null,
        reschedule_proposed_flexible = null,
        reschedule_proposed_by       = null,
        reschedule_status            = 'rejected',
        updated_at                   = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_rejected', 'Remarcação recusada',
    'A nova data foi recusada. Mantém-se a data original.',
    p_job_id, 'job_request');
END;
$function$;


-- ══════════════════════════════════════════════════════════════
-- 11. Pesquisas por raio — B2, B4, S10
-- ══════════════════════════════════════════════════════════════

-- ── 11.1 get_jobs_in_radius ─────────────────────────────────────
-- B2: acos() rebentava ("input is out of range") quando um pedido ficava
-- exatamente na base do worker (arredondamento > 1). Passa a haversine
-- com asin, como get_help_requests_in_radius.
-- S10: raio limitado a 50 km no servidor (o slider da app vai de 1 a 50).
-- Mesma assinatura e mesmo tipo de retorno: CREATE OR REPLACE chega.

CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(
  worker_lat  numeric,
  worker_lng  numeric,
  radius_km   integer,
  p_worker_id uuid DEFAULT NULL
)
RETURNS SETOF job_requests
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jr.*
  FROM   public.job_requests jr
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((jr.location_lat::double precision - worker_lat::double precision) / 2)), 2)
      + cos(radians(worker_lat::double precision))
        * cos(radians(jr.location_lat::double precision))
        * power(sin(radians((jr.location_lng::double precision - worker_lng::double precision) / 2)), 2)
    ))) AS distance_km
  ) d
  WHERE  jr.status = 'open'
    AND  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  d.distance_km <= LEAST(GREATEST(radius_km, 1), 50)
  ORDER BY d.distance_km ASC;
$function$;

-- ── 11.2 get_help_requests_in_radius ────────────────────────────
-- B4: a 0034/0039 perderam o ORDER BY por distância.
-- S10: raio limitado a 50 km; só para workers.
-- Mesma assinatura e mesmo RETURNS TABLE da 0039.

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  proposal_id               uuid,
  slots_needed              integer,
  status                    text,
  equipment_required        boolean,
  created_post_confirmation boolean,
  created_at                timestamptz,
  location_lat              double precision,
  location_lng              double precision,
  service_type_id           uuid,
  principal_name            text,
  principal_avatar_url      text,
  payment_per_helper        numeric,
  confirmed_date            date,
  confirmed_time            time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT id, job_id, proposal_id, slots_needed, status, equipment_required,
         created_post_confirmation, created_at, location_lat, location_lng,
         service_type_id, principal_name, principal_avatar_url,
         payment_per_helper, confirmed_date, confirmed_time
  FROM (
    SELECT
      hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
      hr.equipment_required, hr.created_post_confirmation, hr.created_at,
      jr.location_lat::double precision AS location_lat,
      jr.location_lng::double precision AS location_lng,
      jr.service_type_id, p.full_name AS principal_name,
      p.avatar_url AS principal_avatar_url,
      CASE WHEN hr.equipment_required THEN jp.hourly_rate
           ELSE jp.hourly_rate * 0.7
      END AS payment_per_helper,
      jr.confirmed_date, jr.confirmed_time,
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      ))) AS distance_km
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    WHERE  hr.status = 'open'
      AND  jr.status NOT IN ('cancelled', 'completed')
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid()
      )
  ) t
  WHERE t.distance_km <= LEAST(GREATEST(radius_km, 1), 50)
  ORDER BY t.distance_km ASC;
$function$;


-- ══════════════════════════════════════════════════════════════
-- 12. Storage — S11
-- ══════════════════════════════════════════════════════════════

-- Limite de tamanho e só imagens (as fotos já vão comprimidas pela app:
-- avatares a 400 px, fotos de pedidos a 800 px JPEG).
UPDATE storage.buckets
SET    file_size_limit    = 2097152,  -- 2 MB
       allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE  id IN ('avatars', 'job-photos');

-- As policies de SELECT abertas a todos (incluindo anon) deixavam listar
-- os buckets inteiros (ids de clientes e de pedidos). Os buckets são
-- públicos, por isso os URLs públicos (getPublicUrl) continuam a
-- funcionar SEM policy de SELECT. Fica só o SELECT do próprio dono, que o
-- upload com upsert:true precisa.
DROP POLICY IF EXISTS "Leitura pública de avatars"    ON storage.objects;
DROP POLICY IF EXISTS "avatars: leitura pelo dono"    ON storage.objects;
CREATE POLICY "avatars: leitura pelo dono"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );

DROP POLICY IF EXISTS "Leitura publica de job-photos" ON storage.objects;
DROP POLICY IF EXISTS "job-photos: leitura pelo dono" ON storage.objects;
CREATE POLICY "job-photos: leitura pelo dono"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- O upload de fotos de pedido usa upsert:true, que também precisa de
-- UPDATE. Só existia para avatars.
DROP POLICY IF EXISTS "job-photos: update pelo dono" ON storage.objects;
CREATE POLICY "job-photos: update pelo dono"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );


-- ══════════════════════════════════════════════════════════════
-- 13. P1 — limpeza de notificações antigas
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  DELETE FROM notifications
  WHERE  (read = true  AND created_at < now() - interval '90 days')
     OR  (created_at < now() - interval '180 days');
END;
$function$;

SELECT cron.schedule(
  'cleanup-old-notifications',
  '30 3 * * *',
  'SELECT cleanup_old_notifications()'
);


-- ══════════════════════════════════════════════════════════════
-- 14. S12 — permissões de EXECUTE
-- ══════════════════════════════════════════════════════════════
-- O Supabase dá EXECUTE a anon/authenticated em todas as funções novas
-- do schema public. Nenhuma RPC da app precisa de anon (o cartão público
-- /w/:workerId lê a view worker_public_card, não uma função).
-- Só mexe em funções nossas (ignora as que pertencem a extensões).

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM   pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public'
      AND  p.prokind = 'f'
      AND  NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE  d.objid = p.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END;
$$;

-- Funções só de cron / trigger: ninguém de fora as chama.
REVOKE EXECUTE ON FUNCTION public.auto_confirm_completed_jobs() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.auto_expire_jobs()            FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_old_notifications()   FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_workers_new_job()      FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_profile_role_change() FROM authenticated;
DO $$
BEGIN
  IF to_regprocedure('public.notifications_send_push()') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.notifications_send_push() FROM authenticated;
  END IF;
END;
$$;

-- Funções criadas no futuro continuam a nascer com EXECUTE para PUBLIC
-- (privilégio por omissão global do Postgres, não dá para tirar só neste
-- schema). Regra a partir daqui: cada migration que cria uma função faz
-- REVOKE EXECUTE ... FROM PUBLIC, anon e GRANT ... TO authenticated.

-- Views: worker_profiles_public e worker_rating_summary eram legíveis por
-- anon pelos grants por defeito. Só worker_public_card é pública de
-- propósito (cartão partilhável, 0033).
REVOKE ALL ON public.worker_profiles_public FROM anon;
REVOKE ALL ON public.worker_rating_summary  FROM anon;


-- ══════════════════════════════════════════════════════════════
-- 15. P3 — índices em falta (colunas usadas em policies, RPCs e views)
-- ══════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_job_photos_job_id
  ON job_photos (job_id);
CREATE INDEX IF NOT EXISTS idx_ratings_ratee_id
  ON ratings (ratee_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rater_id
  ON ratings (rater_id);
CREATE INDEX IF NOT EXISTS idx_job_reports_job_id
  ON job_reports (job_id);
CREATE INDEX IF NOT EXISTS idx_job_requests_accepted_proposal_id
  ON job_requests (accepted_proposal_id);
CREATE INDEX IF NOT EXISTS idx_worker_service_types_service_type_id
  ON worker_service_types (service_type_id);
CREATE INDEX IF NOT EXISTS idx_job_requests_open_created
  ON job_requests (created_at DESC) WHERE status = 'open';


NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- Verificação depois de aplicar (só leitura)
-- ══════════════════════════════════════════════════════════════
-- select tablename, policyname, cmd from pg_policies
--  where schemaname = 'public'
--    and tablename in ('job_requests','job_proposals','ratings','help_requests','help_acceptances','worker_fleet_cards','notifications')
--  order by tablename, cmd;
-- select has_function_privilege('anon', 'public.cancel_job(uuid,text,text,boolean)', 'execute');  -- false
-- select to_regprocedure('public.create_user_profile(uuid,text,text,text)');                      -- null
-- select id, file_size_limit, allowed_mime_types from storage.buckets;
