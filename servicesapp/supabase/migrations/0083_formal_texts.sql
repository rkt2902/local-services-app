-- ════════════════════════════════════════════════════════════════
-- 0083 — Textos dos avisos e erros: tratamento formal e "Profissional"
-- ════════════════════════════════════════════════════════════════
--
-- NÃO APLICADA. Aplicar à mão no SQL Editor do Supabase, depois da 0082.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz: volta a criar (CREATE OR REPLACE, mesma assinatura e mesmo
-- RETURNS) as funções que escrevem avisos, notificações push e mensagens de
-- erro, só com os textos mudados:
--   - "tu" passa a tratamento formal ("O seu pedido", "Pode", "Veja");
--   - "jardineiro" passa a "profissional".
-- A lógica de cada função é a da última migration que a definiu (indicada
-- antes de cada uma). Nenhuma assinatura muda, por isso não há DROP.
-- Os avisos já enviados ficam com o texto antigo.
--
-- Regras de sempre: quem chama é auth.uid(); nenhuma RPC recebe
-- worker_id/client_id/user_id vindos da app.
-- ════════════════════════════════════════════════════════════════

-- approve_help_request (antes em 0001_consolidated_baseline.sql)
CREATE OR REPLACE FUNCTION public.approve_help_request(p_help_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status        text;
  v_job_client_id uuid;
  v_worker_id     uuid;
BEGIN
  SELECT hr.status, jr.client_id, jp.worker_id
  INTO   v_status, v_job_client_id, v_worker_id
  FROM   help_requests hr
  JOIN   job_requests  jr ON jr.id = hr.job_id
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  WHERE  hr.id = p_help_request_id
  FOR UPDATE OF hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'help_request não encontrado.';
  END IF;
  IF v_job_client_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o cliente do job pode aprovar este pedido de ajuda.';
  END IF;
  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'help_request não está em pending_approval (estado atual: %).', v_status;
  END IF;

  UPDATE help_requests SET status = 'open' WHERE id = p_help_request_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_worker_id, 'help_request_approved', 'Pedido de equipa aprovado',
    'O cliente aprovou o pedido de ajudantes. Já pode aceitar candidatos.',
    p_help_request_id, 'help_request'
  );
END;
$function$;

-- reject_help_candidate (antes em 0001_consolidated_baseline.sql)
CREATE OR REPLACE FUNCTION public.reject_help_candidate(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal_worker_id uuid;
  v_helper_worker_id    uuid;
  v_help_request_id     uuid;
  v_current_status      text;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status
  INTO   v_principal_worker_id, v_helper_worker_id, v_help_request_id, v_current_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Apenas o worker principal pode rejeitar candidatos.';
  END IF;
  IF v_current_status <> 'pending' THEN
    RAISE EXCEPTION 'Candidatura não está em estado pending (estado atual: %).', v_current_status;
  END IF;

  UPDATE help_acceptances SET status = 'rejected' WHERE id = p_help_acceptance_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_helper_worker_id, 'help_rejected', 'Candidatura não selecionada',
    'O profissional responsável não selecionou a sua candidatura.',
    v_help_request_id, 'help_request');
END;
$function$;

-- apply_to_help_request (antes em 0048_worker_helper_flow_fixes.sql)
CREATE OR REPLACE FUNCTION public.apply_to_help_request(
  p_help_request_id   uuid,
  p_brought_equipment boolean,
  p_message           text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_id           uuid;
  v_principal_id uuid;
  v_name         text;
  v_message      text := NULLIF(btrim(p_message), '');
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM profiles WHERE id = v_uid AND role = 'worker'
  ) THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT help_request_open_for_candidate(p_help_request_id) THEN
    RAISE EXCEPTION 'Este pedido de ajuda já não está aberto.';
  END IF;

  IF v_message IS NOT NULL AND length(v_message) > 500 THEN
    RAISE EXCEPTION 'A mensagem pode ter no máximo 500 caracteres.';
  END IF;

  INSERT INTO help_acceptances (
    help_request_id, worker_id, status, agreed_rate, brought_equipment, message
  ) VALUES (
    p_help_request_id, v_uid, 'pending', 0, COALESCE(p_brought_equipment, false), v_message
  )
  ON CONFLICT (help_request_id, worker_id) DO UPDATE
    SET status            = 'pending',
        agreed_rate       = 0,
        brought_equipment = EXCLUDED.brought_equipment,
        message           = EXCLUDED.message,
        created_at        = now()
    WHERE help_acceptances.status IN ('rejected', 'cancelled')
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Já se candidatou a este pedido de ajuda.';
  END IF;

  SELECT jp.worker_id INTO v_principal_id
  FROM   help_requests hr
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  WHERE  hr.id = p_help_request_id;

  SELECT full_name INTO v_name FROM profiles WHERE id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_principal_id, 'help_candidate_applied', 'Novo candidato a ajudante',
    COALESCE(NULLIF(btrim(v_name), ''), 'Um profissional')
      || ' candidatou-se para o ajudar. Veja a equipa para aceitar ou recusar.',
    p_help_request_id, 'help_request');

  RETURN v_id;
END;
$function$;

-- close_help_on_job_done (antes em 0048_worker_helper_flow_fixes.sql)
CREATE OR REPLACE FUNCTION public.close_help_on_job_done()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('awaiting_confirmation', 'completed')
     AND OLD.status IS DISTINCT FROM NEW.status THEN

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O trabalho a que se candidatou já foi feito sem precisar de mais ajudantes.',
           NEW.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id = NEW.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  status = 'pending'
      AND  help_request_id IN (SELECT id FROM help_requests WHERE job_id = NEW.id);

    UPDATE help_requests
    SET    status = 'cancelled'
    WHERE  job_id = NEW.id AND status IN ('pending_approval', 'open');
  END IF;
  RETURN NULL;
END;
$function$;

-- cancel_help_request (antes em 0049_pending_decisions.sql)
CREATE OR REPLACE FUNCTION public.cancel_help_request(p_help_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal  uuid;
  v_hr_status  text;
  v_job_status text;
BEGIN
  SELECT jp.worker_id, hr.status, jr.status
  INTO   v_principal, v_hr_status, v_job_status
  FROM   help_requests hr
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  JOIN   job_requests  jr ON jr.id = hr.job_id
  WHERE  hr.id = p_help_request_id
  FOR UPDATE OF hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido de ajuda não encontrado.';
  END IF;
  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Só o profissional responsável pode gerir a equipa.';
  END IF;
  IF v_hr_status NOT IN ('pending_approval', 'open', 'filled') THEN
    RAISE EXCEPTION 'Este pedido de ajuda já está fechado.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só pode mudar a equipa com o trabalho por fazer.';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
         'O profissional responsável fechou o pedido de ajuda.',
         p_help_request_id, 'help_request'
  FROM   help_acceptances ha
  WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_removed', 'Já não faz parte da equipa',
         'O profissional responsável fechou a equipa e já não precisa da sua ajuda neste trabalho.',
         p_help_request_id, 'help_request'
  FROM   help_acceptances ha
  WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'accepted';

  UPDATE help_acceptances
  SET    status = CASE WHEN status = 'pending' THEN 'rejected' ELSE 'cancelled' END
  WHERE  help_request_id = p_help_request_id
    AND  status IN ('pending', 'accepted');

  UPDATE help_requests SET status = 'cancelled' WHERE id = p_help_request_id;
END;
$function$;

-- update_help_request_slots (antes em 0049_pending_decisions.sql)
CREATE OR REPLACE FUNCTION public.update_help_request_slots(
  p_help_request_id uuid,
  p_slots           integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal  uuid;
  v_hr_status  text;
  v_job_status text;
  v_accepted   integer;
BEGIN
  IF p_slots IS NULL OR p_slots < 1 OR p_slots > 10 THEN
    RAISE EXCEPTION 'O número de ajudantes tem de ser entre 1 e 10.';
  END IF;

  SELECT jp.worker_id, hr.status, jr.status
  INTO   v_principal, v_hr_status, v_job_status
  FROM   help_requests hr
  JOIN   job_proposals jp ON jp.id = hr.proposal_id
  JOIN   job_requests  jr ON jr.id = hr.job_id
  WHERE  hr.id = p_help_request_id
  FOR UPDATE OF hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido de ajuda não encontrado.';
  END IF;
  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Só o profissional responsável pode gerir a equipa.';
  END IF;
  IF v_hr_status NOT IN ('pending_approval', 'open', 'filled') THEN
    RAISE EXCEPTION 'Este pedido de ajuda já está fechado.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só pode mudar a equipa com o trabalho por fazer.';
  END IF;

  SELECT COUNT(*)::integer INTO v_accepted
  FROM   help_acceptances
  WHERE  help_request_id = p_help_request_id AND status = 'accepted';

  IF p_slots < v_accepted THEN
    RAISE EXCEPTION 'Já tem % ajudantes aceites. Retire alguém da equipa antes de reduzir as vagas.', v_accepted;
  END IF;

  -- À espera do cliente: só muda o número (o cliente aprova o novo).
  IF v_hr_status = 'pending_approval' THEN
    UPDATE help_requests SET slots_needed = p_slots WHERE id = p_help_request_id;
    RETURN;
  END IF;

  IF v_accepted >= p_slots THEN
    UPDATE help_requests
    SET    slots_needed = p_slots, status = 'filled'
    WHERE  id = p_help_request_id;

    -- Igual a accept_help_candidate quando as vagas ficam preenchidas.
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura não selecionada',
           'Todas as vagas foram preenchidas.',
           p_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = p_help_request_id AND status = 'pending';
  ELSE
    UPDATE help_requests
    SET    slots_needed = p_slots, status = 'open'
    WHERE  id = p_help_request_id;

    IF v_hr_status = 'filled' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
             'Uma vaga de ajudante a que se candidatou voltou a abrir. Pode candidatar-se outra vez.',
             p_help_request_id, 'help_request'
      FROM   help_acceptances ha
      WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'rejected';
    END IF;
  END IF;
END;
$function$;

-- update_job_request (antes em 0049_pending_decisions.sql)
CREATE OR REPLACE FUNCTION public.update_job_request(
  p_job_id            uuid,
  p_description       text,
  p_date_mode         text,
  p_preferred_date    date,
  p_availability_text text,
  p_address_text      text,
  p_location_lat      double precision,
  p_location_lng      double precision,
  p_location_area     text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_job          job_requests%ROWTYPE;
  v_description  text := btrim(COALESCE(p_description, ''));
  v_address      text := btrim(COALESCE(p_address_text, ''));
  v_availability text := NULLIF(btrim(p_availability_text), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.client_id <> v_uid THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Só pode alterar um pedido enquanto está aberto.';
  END IF;

  IF length(v_description) < 10 OR length(v_description) > 500 THEN
    RAISE EXCEPTION 'A descrição tem de ter entre 10 e 500 caracteres.';
  END IF;
  IF p_date_mode IS NULL OR p_date_mode NOT IN ('fixed', 'flexible', 'availability') THEN
    RAISE EXCEPTION 'Modo de data inválido.';
  END IF;
  IF p_date_mode = 'fixed'
     AND (p_preferred_date IS NULL OR p_preferred_date < today_pt()) THEN
    RAISE EXCEPTION 'Escolha uma data a partir de hoje.';
  END IF;
  IF p_date_mode = 'availability' AND v_availability IS NULL THEN
    RAISE EXCEPTION 'Indique a sua disponibilidade.';
  END IF;
  IF v_address = '' THEN
    RAISE EXCEPTION 'Indique a morada.';
  END IF;
  IF p_location_lat IS NULL OR p_location_lng IS NULL
     OR p_location_lat NOT BETWEEN -90 AND 90
     OR p_location_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Localização inválida.';
  END IF;

  UPDATE job_requests
  SET    description       = v_description,
         date_mode         = p_date_mode,
         preferred_date    = CASE WHEN p_date_mode = 'fixed' THEN p_preferred_date END,
         availability_text = v_availability,
         address_text      = v_address,
         location_lat      = p_location_lat::numeric,
         location_lng      = p_location_lng::numeric,
         location_area     = NULLIF(btrim(p_location_area), ''),
         updated_at        = now()
  WHERE  id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT jp.worker_id, 'job_updated', 'Pedido alterado',
         'O cliente alterou o pedido a que fez uma proposta. Verifique se a sua proposta ainda se adequa.',
         p_job_id, 'job_request'
  FROM   job_proposals jp
  WHERE  jp.job_id = p_job_id AND jp.status = 'pending';
END;
$function$;

-- start_job (antes em 0052_job_start_flow.sql)
CREATE OR REPLACE FUNCTION public.start_job(
  p_job_id      uuid,
  p_photo_paths text[] DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests%ROWTYPE;
  v_opens  timestamptz;
  v_photos text[];
BEGIN
  SELECT jr.* INTO v_job
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já foi iniciado.';
  END IF;

  -- Janela: 1h antes da hora combinada (hora de Portugal). Sem hora, a
  -- partir do dia; sem data, sempre.
  IF v_job.confirmed_date IS NOT NULL THEN
    IF v_job.confirmed_time IS NOT NULL AND NOT COALESCE(v_job.confirmed_flexible, false) THEN
      v_opens := ((v_job.confirmed_date + v_job.confirmed_time) AT TIME ZONE 'Europe/Lisbon')
                 - INTERVAL '1 hour';
      IF now() < v_opens THEN
        RAISE EXCEPTION 'Só pode iniciar o trabalho a partir das % de %.',
          to_char(v_opens AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'),
          to_char(v_opens AT TIME ZONE 'Europe/Lisbon', 'DD/MM');
      END IF;
    ELSIF v_job.confirmed_date > today_pt() THEN
      RAISE EXCEPTION 'Só pode iniciar o trabalho a partir do dia do trabalho (%).',
        to_char(v_job.confirmed_date, 'DD/MM');
    END IF;
  END IF;

  v_photos := validated_job_photo_paths(p_job_id, p_photo_paths);

  UPDATE public.job_requests
  SET    started_at         = now(),
         before_photo_paths = v_photos,
         updated_at         = now()
  WHERE  id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_started', 'O trabalho começou',
    'O profissional começou o trabalho.', p_job_id, 'job_request');
END;
$function$;

-- help_request_before_insert (antes em 0054_help_requests_job_day_and_alerts.sql)
CREATE OR REPLACE FUNCTION public.help_request_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM help_requests
    WHERE  job_id = NEW.job_id AND status IN ('pending_approval', 'open')
  ) THEN
    RAISE EXCEPTION 'Já tem um pedido de ajudantes ativo para este trabalho.';
  END IF;

  IF NEW.status = 'pending_approval' AND job_day_reached(NEW.job_id) THEN
    RAISE EXCEPTION 'Os ajudantes têm de ser pedidos até à véspera do trabalho.';
  END IF;

  RETURN NEW;
END;
$function$;

-- notify_workers_new_help_request (antes em 0054_help_requests_job_day_and_alerts.sql)
CREATE OR REPLACE FUNCTION public.notify_workers_new_help_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests;
  v_principal uuid;
BEGIN
  IF NEW.status <> 'open' THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM 'pending_approval' THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_job FROM job_requests WHERE id = NEW.job_id;
  IF v_job.id IS NULL OR v_job.status <> 'confirmed'
     OR (v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date <= today_pt()) THEN
    RETURN NULL;
  END IF;

  SELECT worker_id INTO v_principal FROM job_proposals WHERE id = NEW.proposal_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    wp.profile_id,
    'new_help_request_in_radius',
    'Pedido de ajuda perto de si',
    'Um profissional procura '
      || NEW.slots_needed
      || CASE WHEN NEW.slots_needed = 1 THEN ' ajudante' ELSE ' ajudantes' END
      || ' na sua zona. Veja o valor e candidate-se.',
    NEW.id,
    'help_request'
  FROM worker_profiles wp
  WHERE wp.profile_id <> v_principal
    AND wp.profile_id <> v_job.client_id
    AND (
      EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
          AND  wst.service_type_id = v_job.service_type_id
      )
      OR NOT EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
      )
    )
    AND NOT EXISTS (
      SELECT 1 FROM help_acceptances ha
      WHERE  ha.help_request_id = NEW.id
        AND  ha.worker_id = wp.profile_id
        AND  ha.status IN ('pending', 'accepted')
    )
    AND (
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((v_job.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
        + cos(radians(wp.base_lat::double precision))
          * cos(radians(v_job.location_lat::double precision))
          * power(sin(radians((v_job.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
      )))
    ) <= wp.radius_km;

  RETURN NULL;
END;
$function$;

-- notify_client_help_request_pending (antes em 0055_team_flow_improvements.sql)
CREATE OR REPLACE FUNCTION public.notify_client_help_request_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  IF NEW.status = 'pending_approval' THEN
    SELECT client_id INTO v_client_id FROM job_requests WHERE id = NEW.job_id;
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_client_id, 'help_request_pending_approval', 'Pedido de ajudantes',
      'O profissional quer levar ' || NEW.slots_needed
        || CASE WHEN NEW.slots_needed = 1 THEN ' ajudante' ELSE ' ajudantes' END
        || ' para o seu trabalho. Abra o pedido para aprovar. Sem resposta, fica aprovado em 24 horas.',
      NEW.job_id, 'job_request');
  END IF;
  RETURN NULL;
END;
$function$;

-- notify_helpers_on_job_change (antes em 0055_team_flow_improvements.sql)
CREATE OR REPLACE FUNCTION public.notify_helpers_on_job_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type  text;
  v_title text;
  v_body  text;
BEGIN
  IF NEW.accepted_proposal_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'confirmed' AND OLD.started_at IS NULL
     AND NEW.started_at IS NOT NULL THEN
    v_type  := 'help_job_started';
    v_title := 'O trabalho começou';
    v_body  := 'O profissional responsável iniciou o trabalho em que vai ajudar.';
  ELSIF OLD.status = 'confirmed' AND NEW.status = 'confirmed'
     AND (OLD.confirmed_date IS DISTINCT FROM NEW.confirmed_date
          OR OLD.confirmed_time IS DISTINCT FROM NEW.confirmed_time) THEN
    v_type  := 'help_job_rescheduled';
    v_title := 'Data do trabalho mudou';
    v_body  := CASE
      WHEN NEW.confirmed_date IS NULL THEN
        'O trabalho em que vai ajudar mudou de data. Abra a app para ver a nova data.'
      WHEN NEW.confirmed_flexible OR NEW.confirmed_time IS NULL THEN
        'O trabalho em que vai ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM') || '.'
      ELSE
        'O trabalho em que vai ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM')
          || ' às ' || to_char(NEW.confirmed_time, 'HH24:MI') || '.'
    END;
  ELSIF NEW.status = 'awaiting_confirmation' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_done';
    v_title := 'Trabalho marcado como concluído';
    v_body  := 'O profissional responsável marcou como concluído o trabalho em que ajudou.';
  ELSIF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_completed';
    v_title := 'Trabalho concluído';
    v_body  := 'O trabalho em que ajudou ficou confirmado. Já pode avaliar o profissional responsável.';
  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT DISTINCT ha.worker_id, v_type, v_title, v_body, NEW.id, 'job_request'
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  WHERE  hr.job_id      = NEW.id
    AND  hr.proposal_id = NEW.accepted_proposal_id
    AND  ha.status      = 'accepted';

  RETURN NULL;
END;
$function$;

-- process_help_request_deadlines (antes em 0055_team_flow_improvements.sql)
CREATE OR REPLACE FUNCTION public.process_help_request_deadlines()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hr        RECORD;
  v_accepted  integer;
  v_pending   integer;
  v_free      integer;
BEGIN
  -- 7. Por aprovar há 24h: aprova. O trigger da 0054 avisa a zona.
  -- No dia do trabalho não (o trigger recusaria); o cron da 0054 fecha.
  FOR v_hr IN
    SELECT hr.id, hr.job_id, jp.worker_id AS principal_id, jr.client_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status = 'pending_approval'
      AND  hr.created_at <= now() - INTERVAL '24 hours'
      AND  jr.status = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    UPDATE help_requests SET status = 'open' WHERE id = v_hr.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_hr.principal_id, 'help_request_approved', 'Pedido de equipa aprovado',
      'O cliente não respondeu em 24 horas, por isso o pedido de ajudantes ficou aprovado. Já pode aceitar candidatos.',
      v_hr.id, 'help_request');

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_hr.client_id, 'help_request_auto_approved', 'Ajudantes aprovados',
      'Passaram 24 horas sem resposta, por isso o pedido de ajudantes do profissional ficou aprovado.',
      v_hr.job_id, 'job_request');
  END LOOP;

  -- 3. Véspera do trabalho, a partir das 18h em Portugal, uma vez.
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Lisbon') < 18 THEN
    RETURN;
  END IF;

  FOR v_hr IN
    SELECT hr.id, hr.job_id, hr.status, hr.slots_needed,
           jp.worker_id AS principal_id, jr.client_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status IN ('pending_approval', 'open')
      AND  hr.eve_reminder_sent_at IS NULL
      AND  jr.status = 'confirmed'
      AND  jr.confirmed_date = today_pt() + 1
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    IF v_hr.status = 'pending_approval' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.client_id, 'help_request_pending_approval', 'Aprova os ajudantes hoje',
        'O profissional pediu ajudantes para o trabalho de amanhã. Se não aprovar hoje, o pedido fecha à meia-noite.',
        v_hr.job_id, 'job_request');
    ELSE
      SELECT count(*) FILTER (WHERE status = 'accepted'),
             count(*) FILTER (WHERE status = 'pending')
      INTO   v_accepted, v_pending
      FROM   help_acceptances
      WHERE  help_request_id = v_hr.id;

      v_free := GREATEST(v_hr.slots_needed - v_accepted, 0);

      IF v_pending > 0 THEN
        INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
        VALUES (v_hr.principal_id, 'help_request_closing_soon', 'O pedido de ajudantes fecha hoje',
          'Tem ' || v_pending
            || CASE WHEN v_pending = 1 THEN ' candidato' ELSE ' candidatos' END
            || ' por decidir. À meia-noite o pedido fecha e quem não aceitar fica de fora.',
          v_hr.id, 'help_request');
      ELSIF v_free > 0 THEN
        INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
        VALUES (v_hr.principal_id, 'help_request_closing_soon', 'O pedido de ajudantes fecha hoje',
          'Ainda tem ' || v_free
            || CASE WHEN v_free = 1 THEN ' vaga' ELSE ' vagas' END
            || ' por preencher. À meia-noite o pedido fecha e o trabalho fica com a equipa que tiver.',
          v_hr.id, 'help_request');
      END IF;
    END IF;

    UPDATE help_requests SET eve_reminder_sent_at = now() WHERE id = v_hr.id;
  END LOOP;
END;
$function$;

-- remove_help_helper (antes em 0055_team_flow_improvements.sql)
CREATE OR REPLACE FUNCTION public.remove_help_helper(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_principal       uuid;
  v_helper          uuid;
  v_help_request_id uuid;
  v_ha_status       text;
  v_hr_status       text;
  v_job_id          uuid;
  v_job_status      text;
  v_left            integer;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status, hr.status,
         jr.id, jr.status
  INTO   v_principal, v_helper, v_help_request_id, v_ha_status, v_hr_status,
         v_job_id, v_job_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  JOIN   job_requests     jr ON jr.id = hr.job_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha, hr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Só o profissional responsável pode gerir a equipa.';
  END IF;
  IF v_ha_status <> 'accepted' THEN
    RAISE EXCEPTION 'Este ajudante já não está na equipa.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só pode mudar a equipa com o trabalho por fazer.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  IF job_day_reached(v_job_id) THEN
    IF v_hr_status = 'filled' THEN
      SELECT count(*) INTO v_left
      FROM   help_acceptances
      WHERE  help_request_id = v_help_request_id AND status = 'accepted';

      IF v_left > 0 THEN
        UPDATE help_requests SET slots_needed = v_left WHERE id = v_help_request_id;
      ELSE
        UPDATE help_requests SET status = 'cancelled' WHERE id = v_help_request_id;
      END IF;
    END IF;
  ELSIF v_hr_status = 'filled' THEN
    -- Vaga volta a abrir; quem tinha sido recusado fica a saber (como em
    -- withdraw_help_acceptance).
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga de ajudante a que se candidatou voltou a abrir. Pode candidatar-se outra vez.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_helper, 'help_removed', 'Já não faz parte da equipa',
    'O profissional responsável retirou-o da equipa deste trabalho.',
    v_help_request_id, 'help_request');
END;
$function$;

-- withdraw_help_acceptance (antes em 0055_team_flow_improvements.sql)
CREATE OR REPLACE FUNCTION public.withdraw_help_acceptance(p_help_acceptance_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id           uuid;
  v_help_request_id     uuid;
  v_help_request_status text;
  v_principal_worker_id uuid;
  v_current_status      text;
  v_job_id              uuid;
  v_job_status          text;
  v_name                text;
BEGIN
  SELECT ha.worker_id, ha.help_request_id, ha.status,
         hr.status, jp.worker_id, jr.id, jr.status
  INTO   v_worker_id, v_help_request_id, v_current_status,
         v_help_request_status, v_principal_worker_id, v_job_id, v_job_status
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id = ha.help_request_id
  JOIN   job_proposals    jp ON jp.id = hr.proposal_id
  JOIN   job_requests     jr ON jr.id = hr.job_id
  WHERE  ha.id = p_help_acceptance_id
  FOR UPDATE OF ha;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Candidatura não encontrada.';
  END IF;
  IF v_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'Só pode retirar a sua própria candidatura.';
  END IF;

  -- Candidatura ainda por decidir: retira-se sem mais nada.
  IF v_current_status = 'pending' THEN
    UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;
    RETURN;
  END IF;

  IF v_current_status <> 'accepted' THEN
    RAISE EXCEPTION 'Esta candidatura já não está ativa.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Não é possível desistir: o trabalho já não está por fazer.';
  END IF;
  IF job_day_reached(v_job_id) THEN
    RAISE EXCEPTION 'No dia do trabalho já não pode desistir. Fale com o profissional responsável pelo WhatsApp.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  IF v_help_request_status = 'filled' THEN
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga de ajudante a que se candidatou voltou a abrir. Pode candidatar-se outra vez.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  SELECT full_name INTO v_name FROM profiles WHERE id = v_worker_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_principal_worker_id, 'help_withdrew', 'Ajudante desistiu',
    COALESCE(NULLIF(btrim(v_name), ''), 'Um ajudante')
      || ' desistiu de o ajudar. A vaga voltou a abrir.',
    v_help_request_id, 'help_request');
END;
$function$;

-- notify_workers_job_open (antes em 0057_direct_requests.sql)
CREATE OR REPLACE FUNCTION public.notify_workers_job_open(p_job job_requests)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT
    wp.profile_id,
    'new_job_in_radius',
    'Novo pedido perto de si',
    'Há um pedido novo na sua zona. Veja os detalhes e envie a sua proposta.',
    p_job.id,
    'job_request'
  FROM worker_profiles wp
  WHERE wp.profile_id <> p_job.client_id
    AND wp.profile_id IS DISTINCT FROM p_job.direct_worker_id
    AND NOT (wp.profile_id = ANY(COALESCE(p_job.excluded_worker_ids, '{}'::uuid[])))
    AND (
      EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
          AND  wst.service_type_id = p_job.service_type_id
      )
      OR NOT EXISTS (
        SELECT 1 FROM worker_service_types wst
        WHERE  wst.worker_id = wp.profile_id
      )
    )
    AND (
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((p_job.location_lat::double precision - wp.base_lat::double precision) / 2)), 2)
        + cos(radians(wp.base_lat::double precision))
          * cos(radians(p_job.location_lat::double precision))
          * power(sin(radians((p_job.location_lng::double precision - wp.base_lng::double precision) / 2)), 2)
      )))
    ) <= wp.radius_km;
END;
$function$;

-- create_proposal (antes em 0058_proposal_pricing_and_work_days.sql)
CREATE OR REPLACE FUNCTION public.create_proposal(
  p_job_id                     uuid,
  p_hourly_rate                numeric  DEFAULT NULL,
  p_estimated_hours_min        numeric  DEFAULT NULL,
  p_estimated_hours_max        numeric  DEFAULT NULL,
  p_people_needed              integer  DEFAULT 1,
  p_notes                      text     DEFAULT NULL,
  p_scheduled_date             date     DEFAULT NULL,
  p_scheduled_time             text     DEFAULT NULL,
  p_scheduled_flexible         boolean  DEFAULT false,
  p_helpers_equipment_required boolean  DEFAULT false,
  p_pricing_mode               text     DEFAULT 'hourly',
  p_total_price                numeric  DEFAULT NULL,
  p_includes                   text[]   DEFAULT '{}',
  p_estimated_days_min         integer  DEFAULT NULL,
  p_estimated_days_max         integer  DEFAULT NULL,
  p_valid_until                date     DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_proposal_id uuid;
  v_job         job_requests%ROWTYPE;
  v_mode        text := COALESCE(p_pricing_mode, 'hourly');
  v_rate        numeric;
  v_includes    text[];
  v_hours       numeric;
  v_team        numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM worker_profiles WHERE profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Só profissionais podem enviar propostas.';
  END IF;

  IF v_mode NOT IN ('hourly', 'fixed_total') THEN
    RAISE EXCEPTION 'Tipo de preço inválido.';
  END IF;

  IF p_people_needed IS NULL OR p_people_needed < 1 THEN
    RAISE EXCEPTION 'Número de pessoas inválido.';
  END IF;

  IF p_estimated_days_min IS NOT NULL AND p_estimated_days_min < 1
     OR p_estimated_days_max IS NOT NULL
        AND p_estimated_days_max < COALESCE(p_estimated_days_min, 1) THEN
    RAISE EXCEPTION 'Duração em dias inválida.';
  END IF;

  IF p_valid_until IS NOT NULL
     AND (p_valid_until < today_pt() OR p_valid_until > today_pt() + 60) THEN
    RAISE EXCEPTION 'A validade do orçamento tem de ser entre hoje e daqui a 60 dias.';
  END IF;

  -- Só opções ativas, sem repetidas.
  SELECT COALESCE(array_agg(DISTINCT o.slug), '{}')
  INTO   v_includes
  FROM   unnest(COALESCE(p_includes, '{}')) AS s(slug)
  JOIN   proposal_include_options o ON o.slug = s.slug AND o.active;

  IF cardinality(v_includes) <> cardinality(ARRAY(
       SELECT DISTINCT s FROM unnest(COALESCE(p_includes, '{}')) AS s)) THEN
    RAISE EXCEPTION 'Opção de "o que inclui" inválida.';
  END IF;

  IF v_mode = 'hourly' THEN
    IF p_hourly_rate IS NULL OR p_hourly_rate <= 0 THEN
      RAISE EXCEPTION 'O preço por hora tem de ser maior que zero.';
    END IF;
    v_rate := p_hourly_rate;
  ELSE
    IF p_total_price IS NULL OR p_total_price <= 0 THEN
      RAISE EXCEPTION 'Indique o valor total da proposta.';
    END IF;
    -- Hora de referência, só para a sugestão aos ajudantes: a do perfil
    -- ou o total a dividir pelas horas da equipa (8 h por dia).
    SELECT NULLIF(default_hourly_rate, 0) INTO v_rate
    FROM   worker_profiles WHERE profile_id = auth.uid();
    IF v_rate IS NULL OR v_rate <= 0 THEN
      v_hours := COALESCE(p_estimated_hours_max, p_estimated_hours_min,
                          p_estimated_days_max * 8, p_estimated_days_min * 8, 8);
      v_team  := 1 + (p_people_needed - 1)
                     * CASE WHEN COALESCE(p_helpers_equipment_required, false)
                            THEN 1 ELSE 0.75 END;
      v_rate  := GREATEST(round(p_total_price / (v_hours * v_team), 2), 0.01);
    END IF;
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
    RAISE EXCEPTION 'Não pode enviar proposta para o seu próprio pedido.';
  END IF;
  IF auth.uid() = ANY(v_job.excluded_worker_ids) THEN
    RAISE EXCEPTION 'Este pedido já não está disponível.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já tem uma proposta para este pedido.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO job_proposals (
    job_id, worker_id, hourly_rate,
    estimated_hours_min, estimated_hours_max,
    people_needed, notes,
    scheduled_date, scheduled_time, scheduled_flexible,
    helpers_equipment_required,
    pricing_mode, total_price, includes,
    estimated_days_min, estimated_days_max, valid_until,
    status
  ) VALUES (
    p_job_id, auth.uid(), v_rate,
    p_estimated_hours_min, p_estimated_hours_max,
    p_people_needed, p_notes,
    p_scheduled_date,
    p_scheduled_time::time,
    COALESCE(p_scheduled_flexible, false),
    COALESCE(p_helpers_equipment_required, false),
    v_mode,
    CASE WHEN v_mode = 'fixed_total' THEN p_total_price END,
    v_includes,
    p_estimated_days_min, p_estimated_days_max, p_valid_until,
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
    'Um profissional enviou uma proposta para o seu pedido.',
    p_job_id,
    'job_request'
  );

  RETURN v_proposal_id;
END;
$function$;

-- decline_direct_job_request (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.decline_direct_job_request(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;

  IF NOT FOUND OR v_job.direct_worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'open' OR v_job.direct_status IS DISTINCT FROM 'waiting' THEN
    RAISE EXCEPTION 'Este pedido já não está reservado para si.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM job_proposals
    WHERE  job_id = p_job_id AND worker_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Já enviou uma proposta para este pedido. Retire-a primeiro.';
  END IF;

  PERFORM end_direct_reservation(p_job_id, 'declined');
END;
$function$;

-- hold_direct_job (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.hold_direct_job(
  p_job_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job         job_requests%ROWTYPE;
  v_worker_name text;
BEGIN
  IF p_reason NOT IN ('declined', 'expired') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  UPDATE job_requests
  SET    direct_status = 'on_hold',
         direct_hold_reason = p_reason,
         excluded_worker_ids = CASE
           WHEN p_reason = 'declined' AND NOT (direct_worker_id = ANY(excluded_worker_ids))
             THEN array_append(excluded_worker_ids, direct_worker_id)
           ELSE excluded_worker_ids
         END,
         expires_at = GREATEST(expires_at, now() + interval '48 hours'),
         updated_at = now()
  WHERE  id = p_job_id
    AND  status = 'open'
    AND  direct_status = 'waiting'
  RETURNING * INTO v_job;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_worker_name
  FROM   profiles WHERE id = v_job.direct_worker_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_job.client_id,
    'direct_request_released',
    CASE WHEN p_reason = 'declined'
         THEN COALESCE(v_worker_name, 'O profissional') || ' não pode desta vez'
         ELSE COALESCE(v_worker_name, 'O profissional') || ' não respondeu a tempo'
    END,
    'O pedido está parado. Pretende mostrá-lo a outros profissionais?',
    v_job.id,
    'job_request'
  );
END;
$function$;

-- job_proposal_direct_before_insert (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.job_proposal_direct_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM job_requests jr
    WHERE  jr.id = NEW.job_id
      AND  job_reserved_for_other(jr.direct_status, jr.direct_until,
                                  jr.direct_worker_id, NEW.worker_id,
                                  jr.direct_auto_release)
  ) THEN
    RAISE EXCEPTION 'Este pedido ainda está reservado a outro profissional.';
  END IF;
  RETURN NEW;
END;
$function$;

-- job_request_direct_before_insert (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.job_request_direct_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_worker_id uuid;
BEGIN
  NEW.direct_worker_id   := NULL;
  NEW.direct_until       := NULL;
  NEW.direct_status      := NULL;
  NEW.direct_hold_reason := NULL;

  IF NEW.direct_source_job_id IS NOT NULL THEN
    SELECT jp.worker_id INTO v_worker_id
    FROM   job_requests  src
    JOIN   job_proposals jp ON jp.id = src.accepted_proposal_id
    WHERE  src.id        = NEW.direct_source_job_id
      AND  src.client_id = NEW.client_id
      AND  src.status    = 'completed';

    IF v_worker_id IS NULL THEN
      RAISE EXCEPTION 'Só pode pedir de novo a um profissional com quem já concluiu um trabalho.';
    END IF;

    NEW.direct_card_worker_id := NULL;
    NEW.card_visit_id         := NULL;
    NEW.direct_origin := CASE WHEN NEW.direct_origin = 'your_gardeners'
                              THEN 'your_gardeners' ELSE 'repeat_hire' END;

  ELSIF NEW.direct_card_worker_id IS NOT NULL THEN
    v_worker_id := NEW.direct_card_worker_id;

    IF v_worker_id = NEW.client_id THEN
      RAISE EXCEPTION 'Não pode pedir um orçamento a si próprio.';
    END IF;
    NEW.direct_origin := 'public_card';

  ELSE
    NEW.direct_origin       := NULL;
    NEW.card_visit_id       := NULL;
    NEW.direct_auto_release := true;
    RETURN NEW;
  END IF;

  IF NOT worker_can_receive_direct_requests(v_worker_id) THEN
    RAISE EXCEPTION 'Este profissional já não aceita pedidos.';
  END IF;

  -- A visita só fica ligada se for ao cartão deste jardineiro.
  IF NEW.card_visit_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM worker_card_visits
      WHERE  id = NEW.card_visit_id AND worker_id = v_worker_id
    ) THEN
      NEW.card_visit_id := NULL;
    ELSE
      UPDATE worker_card_visits SET visitor_id = NEW.client_id
      WHERE  id = NEW.card_visit_id AND visitor_id IS NULL;
    END IF;
  END IF;

  NEW.direct_auto_release := COALESCE(NEW.direct_auto_release, true);
  NEW.direct_worker_id    := v_worker_id;
  NEW.direct_until        := now() + interval '24 hours';
  NEW.direct_status       := 'waiting';
  RETURN NEW;
END;
$function$;

-- notify_workers_new_job (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.notify_workers_new_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_client  text;
  v_service text;
BEGIN
  IF NEW.direct_status = 'waiting' AND NEW.direct_worker_id IS NOT NULL THEN
    IF NEW.direct_origin = 'public_card' THEN
      SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_client
      FROM   profiles WHERE id = NEW.client_id;
      SELECT name INTO v_service FROM service_types WHERE id = NEW.service_type_id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        NEW.direct_worker_id,
        'direct_job_request',
        'Novo pedido pelo seu cartão',
        COALESCE(v_client, 'Um cliente') || ' quer um orçamento'
          || COALESCE(' para ' || v_service, '') || '. Tem 24 horas.',
        NEW.id,
        'job_request'
      );
    ELSE
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (
        NEW.direct_worker_id,
        'direct_job_request',
        'Pedido só para si',
        'Um cliente com quem já trabalhou pediu-lhe um trabalho. Tem 24 horas para responder antes de o pedido abrir a outros profissionais.',
        NEW.id,
        'job_request'
      );
    END IF;
    RETURN NEW;
  END IF;

  PERFORM notify_workers_job_open(NEW);
  RETURN NEW;
END;
$function$;

-- open_direct_job_to_all (antes em 0059_card_direct_requests_and_tracking.sql)
CREATE OR REPLACE FUNCTION public.open_direct_job_to_all(
  p_job_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job         job_requests%ROWTYPE;
  v_worker_name text;
BEGIN
  IF p_status NOT IN ('declined', 'expired', 'released') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  UPDATE job_requests
  SET    direct_status = p_status,
         direct_hold_reason = NULL,
         excluded_worker_ids = CASE
           WHEN p_status = 'declined' AND NOT (direct_worker_id = ANY(excluded_worker_ids))
             THEN array_append(excluded_worker_ids, direct_worker_id)
           ELSE excluded_worker_ids
         END,
         expires_at = GREATEST(expires_at, now() + interval '48 hours'),
         updated_at = now()
  WHERE  id = p_job_id
    AND  status = 'open'
    AND  (direct_status = 'waiting'
          OR (direct_status = 'on_hold' AND p_status = 'released'))
  RETURNING * INTO v_job;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM notify_workers_job_open(v_job);

  IF p_status IN ('declined', 'expired') THEN
    SELECT NULLIF(btrim(split_part(full_name, ' ', 1)), '') INTO v_worker_name
    FROM   profiles WHERE id = v_job.direct_worker_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (
      v_job.client_id,
      'direct_request_released',
      CASE WHEN p_status = 'declined'
           THEN COALESCE(v_worker_name, 'O profissional') || ' não pode desta vez'
           ELSE COALESCE(v_worker_name, 'O profissional') || ' não respondeu a tempo'
      END,
      'O seu pedido já está visível para outros profissionais da zona.',
      v_job.id,
      'job_request'
    );
  END IF;
END;
$function$;

-- admin_set_worker_plan (antes em 0060_admin_and_worker_plans.sql)
CREATE OR REPLACE FUNCTION public.admin_set_worker_plan(
  p_worker_id   uuid,
  p_tier        text,
  p_starts_at   date DEFAULT NULL,
  p_ends_at     date DEFAULT NULL,
  p_verified_at date DEFAULT NULL,
  p_notes       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_starts date := COALESCE(p_starts_at, (now() AT TIME ZONE 'Europe/Lisbon')::date);
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_tier NOT IN ('free', 'pro', 'pro_plus') THEN
    RAISE EXCEPTION 'Plano inválido.';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at < v_starts THEN
    RAISE EXCEPTION 'A data de fim tem de ser depois do início.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_worker_id AND role = 'worker') THEN
    RAISE EXCEPTION 'Profissional não encontrado.';
  END IF;

  INSERT INTO worker_plans AS wp
    (worker_id, tier, starts_at, ends_at, verified_at, notes, updated_at, updated_by)
  VALUES
    (p_worker_id, p_tier, v_starts, p_ends_at, p_verified_at,
     NULLIF(btrim(COALESCE(p_notes, '')), ''), now(), auth.uid())
  ON CONFLICT (worker_id) DO UPDATE
    SET tier        = EXCLUDED.tier,
        starts_at   = EXCLUDED.starts_at,
        ends_at     = EXCLUDED.ends_at,
        verified_at = EXCLUDED.verified_at,
        notes       = EXCLUDED.notes,
        updated_at  = now(),
        updated_by  = auth.uid();

  INSERT INTO admin_actions (admin_id, action, target_id, details)
  VALUES (auth.uid(), 'set_worker_plan', p_worker_id, jsonb_build_object(
    'tier', p_tier, 'starts_at', v_starts, 'ends_at', p_ends_at,
    'verified_at', p_verified_at));
END;
$function$;

-- enforce_free_plan_limit (antes em 0060_admin_and_worker_plans.sql)
CREATE OR REPLACE FUNCTION public.enforce_free_plan_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF public.worker_active_tier(NEW.worker_id) = 'free'
     AND public.worker_jobs_accepted_this_month(NEW.worker_id)
         >= public.free_plan_monthly_job_limit() THEN
    RAISE EXCEPTION 'Chegou aos % trabalhos deste mês do plano Grátis. Pode voltar a enviar propostas no próximo mês.',
      public.free_plan_monthly_job_limit()
      USING ERRCODE = 'P0001', HINT = 'free_plan_limit';
  END IF;
  RETURN NEW;
END;
$function$;

-- notifications_add_job_context (antes em 0062_job_followups_and_better_notifications.sql)
CREATE OR REPLACE FUNCTION public.notifications_add_job_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_id  uuid;
  v_job     job_requests;
  v_service text;
  v_date    date;
  v_context text;
  v_name    text;
  v_price   text;
  v_km      integer;
  v_prop    job_proposals;
BEGIN
  BEGIN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id AND deleted_at IS NOT NULL
    ) THEN
      RETURN NULL;
    END IF;

    IF NEW.related_id IS NULL OR NEW.related_type IS NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.related_type = 'job_request' THEN
      v_job_id := NEW.related_id;
    ELSIF NEW.related_type = 'help_request' THEN
      SELECT job_id INTO v_job_id FROM help_requests WHERE id = NEW.related_id;
    END IF;

    IF v_job_id IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT * INTO v_job FROM job_requests WHERE id = v_job_id;

    -- Textos antigos → textos com quem e quanto.
    IF NEW.related_type = 'job_request' THEN
      CASE NEW.type
        WHEN 'new_job_in_radius' THEN
          IF NEW.title = 'Novo pedido perto de si' THEN
            SELECT round(km_between(wp.base_lat, wp.base_lng,
                                    v_job.location_lat, v_job.location_lng))::int
            INTO   v_km
            FROM   worker_profiles wp WHERE wp.profile_id = NEW.user_id;
            NEW.body := 'Pedido novo em ' || job_area_label(v_job.location_area)
              || COALESCE(', a ' || v_km || ' km de si', '')
              || '. Seja o primeiro a enviar proposta.';
          END IF;

        WHEN 'proposal_received' THEN
          IF NEW.body = 'Um profissional enviou uma proposta para o seu pedido.' THEN
            SELECT * INTO v_prop FROM job_proposals
            WHERE  job_id = v_job_id AND status = 'pending'
            ORDER  BY created_at DESC LIMIT 1;
            v_name := first_name_of(v_prop.worker_id);
            v_price := CASE
              WHEN v_prop.pricing_mode = 'fixed_total' AND v_prop.total_price IS NOT NULL
                THEN pt_money(v_prop.total_price) || ' no total'
              WHEN v_prop.hourly_rate IS NOT NULL
                THEN pt_money(v_prop.hourly_rate) || '/h'
            END;
            NEW.title := 'Nova proposta' || COALESCE(' de ' || v_name, '');
            NEW.body := COALESCE(v_name, 'Um profissional') || ' enviou uma proposta'
              || COALESCE(': ' || v_price, '')
              || CASE WHEN v_job.proposal_count > 1
                      THEN '. Já tem ' || v_job.proposal_count || ' propostas para comparar.'
                      ELSE '. Veja os detalhes e decida quando quiser.' END;
          END IF;

        WHEN 'proposal_withdrawn' THEN
          IF NEW.body IN ('Um profissional retirou a sua proposta.',
                          'Um profissional retirou a proposta que lhe tinha feito.') THEN
            SELECT first_name_of(worker_id) INTO v_name FROM job_proposals
            WHERE  job_id = v_job_id AND status = 'withdrawn'
            ORDER  BY updated_at DESC LIMIT 1;
            NEW.body := COALESCE(v_name, 'Um profissional') || ' retirou a proposta.'
              || CASE WHEN v_job.proposal_count > 0
                      THEN ' As outras continuam à sua espera.'
                      ELSE ' O pedido continua aberto a outros profissionais.' END;
          END IF;

        WHEN 'proposal_accepted' THEN
          IF NEW.body = 'O cliente aceitou a sua proposta.' THEN
            v_name := first_name_of(v_job.client_id);
            NEW.title := 'Proposta aceite';
            NEW.body := COALESCE(v_name, 'O cliente')
              || ' aceitou a sua proposta. Combine os pormenores por WhatsApp.';
          END IF;

        WHEN 'proposal_rejected' THEN
          IF NEW.body = 'O cliente recusou a sua proposta.' THEN
            NEW.body := 'O cliente recusou a sua proposta. Há mais pedidos à sua espera.';
          ELSIF NEW.body = 'O cliente escolheu outra proposta.' THEN
            NEW.body := 'O cliente escolheu outra proposta. Há mais pedidos à sua espera.';
          END IF;

        WHEN 'job_cancelled' THEN
          IF NEW.body = 'Um pedido foi cancelado.' THEN
            v_name := first_name_of(v_job.cancelled_by);
            IF NEW.user_id = v_job.client_id THEN
              NEW.title := 'Trabalho cancelado';
              NEW.body := COALESCE(v_name, 'O profissional')
                || ' cancelou o trabalho. Vamos mostrar o pedido de novo a outros profissionais.';
            ELSE
              NEW.title := 'Trabalho cancelado';
              NEW.body := COALESCE(v_name, 'O cliente') || ' cancelou o trabalho.';
            END IF;
          END IF;

        WHEN 'job_reopened' THEN
          IF NEW.body = 'O pedido foi reaberto automaticamente.' THEN
            NEW.title := 'O seu pedido voltou a estar aberto';
            NEW.body := 'Já está visível para outros profissionais. As novas propostas aparecem aqui.';
          END IF;

        WHEN 'job_started' THEN
          IF NEW.body = 'O profissional começou o trabalho.' THEN
            SELECT first_name_of(jp.worker_id) INTO v_name
            FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;
            NEW.body := COALESCE(v_name, 'O profissional') || ' começou o trabalho.';
          END IF;

        WHEN 'reschedule_proposed' THEN
          IF NEW.body = 'A outra parte propôs uma nova data para o trabalho.' THEN
            v_name := first_name_of(v_job.reschedule_proposed_by);
            NEW.title := 'Pedido de nova data';
            NEW.body := COALESCE(v_name, 'A outra pessoa') || ' propôs mudar o trabalho para '
              || COALESCE(to_char(v_job.reschedule_proposed_date, 'DD/MM'), 'outra data')
              || '. Aceite ou recuse na app.';
          END IF;

        WHEN 'reschedule_accepted' THEN
          IF NEW.body = 'A nova data foi aceite.' THEN
            NEW.title := 'Nova data aceite';
            NEW.body := 'O trabalho passou para '
              || COALESCE(to_char(v_job.confirmed_date, 'DD/MM'), 'a nova data') || '.';
          END IF;

        WHEN 'job_no_response' THEN
          IF NEW.title = 'Sem resposta' THEN
            NEW.title := 'Pedido sem propostas';
            NEW.body := 'O seu pedido fechou sem propostas. Pode publicá-lo de novo, com outra data ou mais detalhes.';
          END IF;

        ELSE
          NULL;
      END CASE;
    END IF;

    IF NEW.type = 'help_rejected'
       AND NEW.body = 'O profissional responsável não selecionou a sua candidatura.' THEN
      NEW.body := 'O profissional responsável escolheu outra pessoa para esta vaga.';
    END IF;

    SELECT st.name, COALESCE(jr.confirmed_date, jr.preferred_date)
    INTO   v_service, v_date
    FROM   job_requests  jr
    JOIN   service_types st ON st.id = jr.service_type_id
    WHERE  jr.id = v_job_id;

    IF v_service IS NULL OR btrim(v_service) = '' THEN
      RETURN NEW;
    END IF;

    v_context := v_service || COALESCE(', ' || to_char(v_date, 'DD/MM'), '');

    IF NEW.body IS NOT NULL AND strpos(NEW.body, '(' || v_context || ')') = 0 THEN
      NEW.body := NEW.body || ' (' || v_context || ')';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
  END;

  RETURN NEW;
END;
$function$;

-- notify_workers_wider_ring (antes em 0062_job_followups_and_better_notifications.sql)
CREATE OR REPLACE FUNCTION public.notify_workers_wider_ring(
  p_job job_requests, p_from_km integer, p_to_km integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT c.worker_id,
         'new_job_in_radius',
         'Pedido um pouco mais longe',
         'Ainda ninguém da zona respondeu a este pedido em '
           || job_area_label(p_job.location_area) || ', a '
           || round(c.distance_km)::int || ' km de si. Se lhe for conveniente, envie proposta.',
         p_job.id,
         'job_request'
  FROM   job_candidate_workers(p_job) c
  WHERE  c.distance_km >  c.radius_km + p_from_km
    AND  c.distance_km <= c.radius_km + p_to_km;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

-- process_open_job_followups (antes em 0062_job_followups_and_better_notifications.sql)
CREATE OR REPLACE FUNCTION public.process_open_job_followups()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hour   integer := extract(hour FROM now() AT TIME ZONE 'Europe/Lisbon');
  v_job    job_requests;
  v_ids    uuid[];
  r        record;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;
  -- Só de dia: um pedido que faz 6 h às 3 da manhã espera pelas 8h.
  IF v_hour < 8 OR v_hour >= 21 THEN
    RETURN;
  END IF;

  -- 6.1 24 h sem propostas: mostrar 10 km mais longe e avisar o cliente.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status = 'open'
      AND  proposal_count = 0
      AND  followup_stage < 2
      AND  visible_to_all_at IS NOT NULL
      AND  visible_to_all_at <= now() - interval '24 hours'
      AND  COALESCE(direct_status, '') NOT IN ('waiting', 'on_hold')
      AND  expires_at > now()
      AND  NOT (date_mode = 'fixed' AND preferred_date < today_pt())
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    followup_stage = 2, no_proposals_nudged_at = now()
    WHERE  id = v_job.id;

    IF v_job.search_extra_km < 10 THEN
      PERFORM widen_job_reach(v_job.id, 10 - v_job.search_extra_km);
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_proposals_yet', 'Ainda sem propostas',
      'Já mostrámos o seu pedido a profissionais um pouco mais longe. Também ajuda alargar a data ou juntar mais detalhes à descrição.',
      v_job.id, 'job_request');
  END LOOP;

  -- 6.2 6 h sem propostas: lembrete aos jardineiros que o veem.
  SELECT array_agg(id) INTO v_ids
  FROM   job_requests
  WHERE  status = 'open'
    AND  proposal_count = 0
    AND  followup_stage = 0
    AND  visible_to_all_at IS NOT NULL
    AND  visible_to_all_at <= now() - interval '6 hours'
    AND  COALESCE(direct_status, '') NOT IN ('waiting', 'on_hold')
    AND  expires_at > now()
    AND  NOT (date_mode = 'fixed' AND preferred_date < today_pt());

  IF v_ids IS NULL THEN
    RETURN;
  END IF;

  UPDATE job_requests SET followup_stage = 1 WHERE id = ANY(v_ids);

  -- Um aviso por jardineiro: com um pedido diz qual; com vários junta-os.
  -- Quem já teve um lembrete nas últimas 20 h fica de fora.
  FOR r IN
    WITH pairs AS (
      SELECT c.worker_id, jr.id AS job_id, jr.location_area, c.distance_km
      FROM   job_requests jr
      CROSS JOIN LATERAL job_candidate_workers(jr) c
      WHERE  jr.id = ANY(v_ids)
        AND  c.distance_km <= c.radius_km + jr.search_extra_km
    )
    SELECT p.worker_id,
           count(*)                       AS n,
           (array_agg(p.job_id ORDER BY p.distance_km))[1]        AS job_id,
           (array_agg(p.location_area ORDER BY p.distance_km))[1] AS area,
           min(p.distance_km)             AS distance_km
    FROM   pairs p
    WHERE  NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE  n.user_id = p.worker_id
        AND  n.type = 'job_opportunity_reminder'
        AND  n.created_at > now() - interval '20 hours'
    )
    GROUP  BY p.worker_id
  LOOP
    IF r.n = 1 THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.worker_id, 'job_opportunity_reminder', 'Ainda ninguém enviou proposta',
        'O pedido em ' || job_area_label(r.area) || ', a ' || round(r.distance_km)::int
          || ' km de si, continua sem propostas. Quem responde primeiro tem mais hipóteses.',
        r.job_id, 'job_request');
    ELSE
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.worker_id, 'job_opportunity_reminder', r.n || ' pedidos sem propostas perto de si',
        'Há ' || r.n || ' pedidos na sua zona à espera da primeira proposta. Veja-os em Pedidos disponíveis.',
        NULL, NULL);
    END IF;
  END LOOP;
END;
$function$;

-- widen_job_search (antes em 0062_job_followups_and_better_notifications.sql)
CREATE OR REPLACE FUNCTION public.widen_job_search(p_job_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id;
  IF v_job.id IS NULL OR v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'open' THEN
    RAISE EXCEPTION 'Este pedido já não está aberto.';
  END IF;
  IF COALESCE(v_job.direct_status, '') IN ('waiting', 'on_hold') THEN
    RAISE EXCEPTION 'Este pedido ainda está reservado a um profissional. Mostre-o primeiro a todos.';
  END IF;
  IF v_job.search_extra_km >= 30 THEN
    RAISE EXCEPTION 'O pedido já está a ser mostrado o mais longe possível.';
  END IF;

  UPDATE job_requests
  SET    followup_stage = 2,
         no_proposals_nudged_at = COALESCE(no_proposals_nudged_at, now())
  WHERE  id = p_job_id;

  RETURN widen_job_reach(p_job_id, 10);
END;
$function$;

-- account_deletion_blocker (antes em 0066_account_deletion_erase_and_email_block.sql)
CREATE OR REPLACE FUNCTION public.account_deletion_blocker(p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN
       EXISTS (
         SELECT 1 FROM job_requests
         WHERE  client_id = p_uid
           AND  status IN ('confirmed', 'awaiting_confirmation')
       )
    OR EXISTS (
         SELECT 1
         FROM   job_proposals jp
         JOIN   job_requests  jr ON jr.id = jp.job_id
         WHERE  jp.worker_id = p_uid
           AND  jp.status    = 'accepted'
           AND  jr.status IN ('confirmed', 'awaiting_confirmation')
       )
    OR EXISTS (
         SELECT 1
         FROM   help_acceptances ha
         JOIN   help_requests    hr ON hr.id = ha.help_request_id
         JOIN   job_requests     jr ON jr.id = hr.job_id
         WHERE  ha.worker_id = p_uid
           AND  ha.status    = 'accepted'
           AND  jr.status    = 'confirmed'
       )
  THEN 'Tem trabalhos em curso. Conclua-os ou cancele-os antes de eliminar a conta.'
  END;
$function$;

-- cancel_job (antes em 0069_multi_day_and_started_job_rules.sql)
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
    RAISE EXCEPTION 'Não autorizado: só o cliente ou o profissional do trabalho podem cancelar.';
  END IF;

  -- 0069: trabalho já iniciado (a regra das 24h não o apanha com data
  -- "a combinar" ou depois de uma remarcação).
  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já começou e já não pode ser cancelado nem remarcado.';
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

-- close_help_requests_on_job_day (antes em 0070_privacy_and_deleted_account_fixes.sql)
CREATE OR REPLACE FUNCTION public.close_help_requests_on_job_day()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hr        RECORD;
  v_accepted  integer;
BEGIN
  FOR v_hr IN
    SELECT hr.id, hr.status, jp.worker_id AS principal_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status IN ('pending_approval', 'open')
      AND  jr.status = 'confirmed'
      AND  (jr.started_at IS NOT NULL
            OR (jr.confirmed_date IS NOT NULL AND jr.confirmed_date <= today_pt()))
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O dia do trabalho chegou e o pedido de ajuda fechou sem a sua candidatura ser aceite.',
           v_hr.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_hr.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = v_hr.id AND status = 'pending';

    SELECT count(*) INTO v_accepted
    FROM   help_acceptances
    WHERE  help_request_id = v_hr.id AND status = 'accepted';

    IF v_accepted > 0 THEN
      UPDATE help_requests
      SET    status = 'filled', slots_needed = v_accepted
      WHERE  id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        'O trabalho é hoje, por isso o pedido de ajudantes fechou. A sua equipa fica com '
          || v_accepted
          || CASE WHEN v_accepted = 1 THEN ' ajudante.' ELSE ' ajudantes.' END,
        v_hr.id, 'help_request');
    ELSE
      UPDATE help_requests SET status = 'cancelled' WHERE id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        CASE WHEN v_hr.status = 'pending_approval'
          THEN 'O trabalho é hoje e o cliente não chegou a aprovar os ajudantes. O pedido fechou.'
          ELSE 'O trabalho é hoje e ninguém foi aceite como ajudante. O pedido fechou.'
        END,
        v_hr.id, 'help_request');
    END IF;
  END LOOP;
END;
$function$;

-- auto_confirm_completed_jobs (antes em 0071_day_jobs_reports_and_agenda.sql)
CREATE OR REPLACE FUNCTION public.auto_confirm_completed_jobs()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 5.1 Lembrete ao cliente 24h depois (uma vez só).
  FOR v_job IN
    SELECT * FROM job_requests jr
    WHERE  jr.status = 'awaiting_confirmation'
      AND  COALESCE(jr.marked_done_at, jr.updated_at) < now() - INTERVAL '24 hours'
      AND  jr.confirmation_reminder_sent_at IS NULL
      -- 0071: com relato da cliente o prazo é outro e ela já foi avisada.
      AND  NOT job_has_client_report(jr.id)
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'Confirme o trabalho',
      'O profissional marcou o trabalho como concluído. Confirme ou reporte um problema. Sem resposta, fica confirmado automaticamente dentro de 24 horas.',
      v_job.id, 'job_request');

    UPDATE job_requests SET confirmation_reminder_sent_at = now() WHERE id = v_job.id;
  END LOOP;

  -- 5.2 Confirmação automática às 48h.
  FOR v_job IN
    SELECT * FROM job_requests jr
    WHERE  jr.status = 'awaiting_confirmation'
      -- 0071: 48h; com relato da cliente, 7 dias. Só os relatos dela
      -- contam (antes um relato do jardineiro também travava) e o
      -- trabalho já não fica preso para sempre.
      AND  COALESCE(jr.marked_done_at, jr.updated_at)
             < now() - CASE WHEN job_has_client_report(jr.id)
                            THEN INTERVAL '7 days' ELSE INTERVAL '48 hours' END
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'completed', updated_at = now()
    WHERE  id = v_job.id;

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_completed', 'Trabalho confirmado automaticamente',
        CASE WHEN job_has_client_report(v_job.id)
          THEN 'Passaram 7 dias desde o relato da cliente sem ela confirmar. O trabalho foi confirmado automaticamente.'
          ELSE 'Passaram 48 horas sem confirmação. O trabalho foi confirmado automaticamente.' END,
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_completed', 'Trabalho confirmado automaticamente',
      CASE WHEN job_has_client_report(v_job.id)
        THEN 'Passaram 7 dias desde o seu relato. O trabalho foi confirmado automaticamente.'
        ELSE 'Passaram 48 horas sem resposta. O trabalho foi confirmado automaticamente.' END,
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

-- mark_job_done (antes em 0071_day_jobs_reports_and_agenda.sql)
CREATE OR REPLACE FUNCTION public.mark_job_done(p_job_id uuid, p_photo_paths text[] DEFAULT '{}'::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job      job_requests%ROWTYPE;
  v_photos   text[];
  v_minutes  integer;
  v_duration text;
  v_prop     job_proposals%ROWTYPE;
  v_start_d  date;
  v_days     integer;
BEGIN
  SELECT jr.* INTO v_job
  FROM   public.job_requests  jr
  JOIN   public.job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE  jr.id        = p_job_id
    AND  jp.worker_id = auth.uid()
    AND  jr.status    = 'confirmed'
  FOR UPDATE OF jr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado ou job não está confirmado';
  END IF;

  IF v_job.started_at IS NULL THEN
    RAISE EXCEPTION 'Inicie o trabalho antes de o marcar como concluído.';
  END IF;

  -- Mesma regra da 0046: só a partir do dia do trabalho.
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date > today_pt() THEN
    RAISE EXCEPTION 'Só pode marcar como concluído a partir do dia do trabalho (%).',
      to_char(v_job.confirmed_date, 'DD/MM');
  END IF;

  v_photos := validated_job_photo_paths(p_job_id, p_photo_paths);

  -- 0071: trabalho por dias mostra os dias (sem horas); à hora, a soma
  -- dos dias registados, sem contar as noites.
  SELECT * INTO v_prop FROM job_proposals WHERE id = v_job.accepted_proposal_id;
  IF proposal_is_day_based(v_prop.estimated_days_min, v_prop.estimated_days_max) THEN
    v_start_d  := (v_job.started_at AT TIME ZONE 'Europe/Lisbon')::date;
    v_days     := today_pt() - v_start_d + 1;
    v_duration := CASE WHEN v_days <= 1 THEN '1 dia'
                       ELSE v_days || ' dias, de ' || to_char(v_start_d, 'DD/MM')
                            || ' a ' || to_char(today_pt(), 'DD/MM') END;
  ELSE
    SELECT COALESCE(sum(extract(epoch FROM (COALESCE(wd.ended_at, now()) - wd.started_at))), 0)
    INTO   v_minutes
    FROM   job_work_days wd
    WHERE  wd.job_id = p_job_id;
    v_minutes := GREATEST(0, floor(COALESCE(NULLIF(v_minutes, 0),
                   extract(epoch FROM now() - v_job.started_at)) / 60))::integer;
    v_duration := CASE
      WHEN v_minutes < 60 THEN v_minutes || 'min'
      ELSE (v_minutes / 60) || 'h' || CASE WHEN v_minutes % 60 > 0
                                           THEN ' ' || (v_minutes % 60) || 'min'
                                           ELSE '' END
    END;
  END IF;

  UPDATE public.job_requests
  SET    status                = 'awaiting_confirmation',
         after_photo_paths     = v_photos,
         completion_photo_path = v_photos[1],
         marked_done_at        = now(),
         updated_at            = now()
  WHERE  id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_marked_done', 'Trabalho concluído!',
    'O profissional terminou o trabalho (' || v_duration || ')'
    || CASE WHEN cardinality(v_photos) > 0 THEN ' e juntou fotos' ELSE '' END
    || '. Confirme se está tudo bem. Sem resposta, fica confirmado em 48 horas.',
    p_job_id, 'job_request');
END;
$function$;

-- send_start_reminders (antes em 0072_start_reminders.sql)
CREATE OR REPLACE FUNCTION public.send_start_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       record;
  v_worker_id uuid;
  v_hour      text;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 1. Uma hora antes.
  FOR v_job IN
    SELECT jr.id, jr.accepted_proposal_id, jr.confirmed_time, jr.location_area, s.starts_at
    FROM   job_requests jr
    CROSS  JOIN LATERAL (
             SELECT (jr.confirmed_date + jr.confirmed_time)
                      AT TIME ZONE 'Europe/Lisbon' AS starts_at) s
    WHERE  jr.status = 'confirmed'
      AND  jr.started_at IS NULL
      AND  jr.confirmed_date IS NOT NULL
      AND  jr.confirmed_time IS NOT NULL
      AND  NOT COALESCE(jr.confirmed_flexible, false)
      AND  now() >= s.starts_at - INTERVAL '1 hour'
      AND  now() <  s.starts_at
      AND  jr.start_reminder_for IS DISTINCT FROM s.starts_at
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    v_hour := to_char(v_job.confirmed_time, 'HH24:MI');
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'O trabalho começa daqui a 1 hora',
        'Está marcado para as ' || v_hour
          || COALESCE(', em ' || NULLIF(v_job.location_area, ''), '')
          || '. Quando chegar, carregue em Iniciar para o cliente saber.',
        v_job.id, 'job_request');
    END IF;

    UPDATE job_requests SET start_reminder_for = v_job.starts_at WHERE id = v_job.id;
  END LOOP;

  -- 2. Trinta minutos depois, sem "Iniciar".
  FOR v_job IN
    SELECT jr.id, jr.accepted_proposal_id, jr.confirmed_time, s.starts_at
    FROM   job_requests jr
    CROSS  JOIN LATERAL (
             SELECT (jr.confirmed_date + jr.confirmed_time)
                      AT TIME ZONE 'Europe/Lisbon' AS starts_at) s
    WHERE  jr.status = 'confirmed'
      AND  jr.started_at IS NULL
      AND  jr.confirmed_date IS NOT NULL
      AND  jr.confirmed_time IS NOT NULL
      AND  NOT COALESCE(jr.confirmed_flexible, false)
      AND  now() >= s.starts_at + INTERVAL '30 minutes'
      AND  now() <  s.starts_at + INTERVAL '6 hours'
      AND  jr.late_start_reminder_for IS DISTINCT FROM s.starts_at
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    v_hour := to_char(v_job.confirmed_time, 'HH24:MI');
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Ainda não iniciou o trabalho',
        'Estava marcado para as ' || v_hour
          || '. Se já está no local, carregue em Iniciar. Se está atrasado, avise o cliente por WhatsApp.',
        v_job.id, 'job_request');
    END IF;

    UPDATE job_requests SET late_start_reminder_for = v_job.starts_at WHERE id = v_job.id;
  END LOOP;
END;
$function$;

-- auto_expire_jobs (antes em 0073_flow_review_part5.sql)
CREATE OR REPLACE FUNCTION public.auto_expire_jobs()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 5.1 Regra antiga: 48h sem nenhuma proposta.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  expires_at     < now()
      AND  proposal_count = 0
      -- 0069: o pedido direto parado tem a regra 5.1b.
      AND  direct_status IS DISTINCT FROM 'on_hold'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Sem resposta',
      'O seu pedido não recebeu propostas em 48h.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.1b (0069) Pedido direto parado (a cliente desligou "mostrar a outros")
  -- que ficou 48h à espera da decisão dela. Nenhum outro jardineiro o viu,
  -- por isso o texto não fala em "sem propostas".
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  direct_status  = 'on_hold'
      AND  expires_at     < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    -- 0073: como nas outras regras de fecho, nenhuma proposta fica pendente
    -- num pedido fechado (o trigger da 0048 avisa cada jardineiro).
    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido fechado',
      'O pedido ficou parado 48h sem ser mostrado a outros profissionais e foi fechado. Pode fazer um pedido novo quando quiser.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.2 Pedido aberto com data fixa que já passou, com ou sem propostas.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  date_mode      = 'fixed'
      AND  preferred_date < today_pt()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    UPDATE job_proposals
    SET    status = 'rejected'
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido expirado',
      'A data do seu pedido passou sem nenhuma proposta aceite. Pode criar um novo pedido.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.3 Trabalho confirmado, 3 dias depois da data, sem ninguém marcar
  -- como concluído: expira.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      -- 0073: "a combinar" já iniciado conta a partir do dia em que começou.
      AND  (confirmed_date IS NOT NULL OR started_at IS NOT NULL)
      -- 0069: a contar do último dia previsto (trabalho em vários dias).
      AND  job_expected_end_date(id) < today_pt() - 3
      -- Remarcação pendente: dá tempo à outra parte para responder, a não
      -- ser que a data proposta também já tenha passado (0069).
      AND  (reschedule_status IS DISTINCT FROM 'pending'
            OR reschedule_proposed_date < today_pt())
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status        = 'cancelled',
           cancel_reason = 'expired',
           updated_at    = now()
    WHERE  id = v_job.id;

    -- Mesma cascata que cancel_job faz à equipa de ajudantes.
    UPDATE help_requests
    SET    status = 'cancelled'
    WHERE  job_id = v_job.id AND status <> 'cancelled';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = v_job.id)
      AND  status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho expirado',
           'O trabalho em que ias ajudar expirou sem ser concluído.',
           v_job.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id = v_job.id AND ha.status = 'accepted';

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_cancelled', 'Trabalho expirado',
      'Passaram 3 dias da data combinada sem o trabalho ser marcado como concluído. O pedido foi fechado.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_cancelled', 'Trabalho expirado',
        'Passaram 3 dias da data combinada sem marcar o trabalho como concluído. O pedido foi fechado.',
        v_job.id, 'job_request');
    END IF;
  END LOOP;

  -- 5.4 Pedido sem data fixa, com propostas, aberto há mais de 14 dias
  -- sem o cliente escolher: fecha. O pedido passa a no_response antes de
  -- rejeitar as propostas, para o trigger da 0048 (secção 11 desta)
  -- avisar cada jardineiro.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'open'
      AND  date_mode     <> 'fixed'
      AND  proposal_count > 0
      AND  accepted_proposal_id IS NULL
      AND  created_at     < now() - INTERVAL '14 days'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = v_job.id AND status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Pedido fechado',
      'O seu pedido esteve 14 dias sem escolher uma proposta e foi fechado. Pode publicá-lo de novo.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.5 (0073) "A combinar" nunca iniciado: fecha 30 dias depois de a
  -- proposta ser aceite (decisão do Henrique, 12/11). Aviso 3 dias antes
  -- em send_job_reminders (7.3).
  FOR v_job IN
    SELECT jr.*
    FROM   job_requests jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.status = 'confirmed'
      AND  jr.confirmed_date IS NULL
      AND  jr.started_at IS NULL
      AND  jr.reschedule_status IS DISTINCT FROM 'pending'
      AND  COALESCE(jp.accepted_at, jr.updated_at) < now() - INTERVAL '30 days'
      -- Só depois do aviso de 3 dias (os antigos também o recebem primeiro).
      AND  jr.undated_expiry_warned_at < now() - INTERVAL '3 days'
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status        = 'cancelled',
           cancel_reason = 'expired',
           updated_at    = now()
    WHERE  id = v_job.id;

    UPDATE help_requests
    SET    status = 'cancelled'
    WHERE  job_id = v_job.id AND status <> 'cancelled';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id IN (SELECT id FROM help_requests WHERE job_id = v_job.id)
      AND  status = 'pending';

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho expirado',
           'O trabalho em que ias ajudar expirou sem ser feito.',
           v_job.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id = v_job.id AND ha.status = 'accepted';

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_cancelled', 'Trabalho expirado',
      'O trabalho ficou 30 dias sem data e sem ser iniciado, por isso foi fechado. Se ainda precisar, faça um pedido novo.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_cancelled', 'Trabalho expirado',
        'O trabalho ficou 30 dias sem data e sem ser iniciado, por isso foi fechado.',
        v_job.id, 'job_request');
    END IF;
  END LOOP;
END;
$function$;

-- send_job_reminders (antes em 0073_flow_review_part5.sql)
CREATE OR REPLACE FUNCTION public.send_job_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today     date := today_pt();
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
  v_when      text;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  -- 7.1 Manhã do dia do trabalho, ao cliente, ao worker e aos ajudantes.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      AND  confirmed_date = v_today
      AND  day_reminder_sent_on IS DISTINCT FROM v_today
    FOR UPDATE SKIP LOCKED
  LOOP
    v_when := CASE
      WHEN v_job.confirmed_flexible OR v_job.confirmed_time IS NULL THEN 'hoje'
      ELSE 'hoje às ' || to_char(v_job.confirmed_time, 'HH24:MI')
    END;

    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'O trabalho é hoje',
      'Lembrete: o profissional vem ' || v_when || '.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Tem um trabalho hoje',
        'Lembrete: trabalho marcado para ' || v_when || '. Abra a app para ver a morada.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT DISTINCT ha.worker_id, 'job_reminder', 'Vai ajudar num trabalho hoje',
           'Lembrete: trabalho marcado para ' || v_when || '. Abra a app para ver a morada.',
           v_job.id, 'job_request'
    FROM   help_acceptances ha
    JOIN   help_requests    hr ON hr.id = ha.help_request_id
    WHERE  hr.job_id      = v_job.id
      AND  hr.proposal_id = v_job.accepted_proposal_id
      AND  ha.status      = 'accepted';

    UPDATE job_requests SET day_reminder_sent_on = v_today WHERE id = v_job.id;
  END LOOP;

  -- 7.2 A data passou e ninguém marcou como concluído (uma vez só).
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      -- 0073: "a combinar" já iniciado conta a partir do dia em que começou.
      AND  (confirmed_date IS NOT NULL OR started_at IS NOT NULL)
      -- 0069: a contar do último dia previsto (trabalho em vários dias).
      AND  job_expected_end_date(id) < v_today
      AND  overdue_notified_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Marque o trabalho como concluído',
        'A data do trabalho já passou. Se já o fez, marque-o como concluído. Sem isso, o pedido expira 3 dias depois da data.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'O trabalho foi feito?',
      'A data do trabalho já passou e o profissional ainda não o marcou como concluído. Fale com ele pelo WhatsApp ou remarque. O pedido expira 3 dias depois da data.',
      v_job.id, 'job_request');

    UPDATE job_requests SET overdue_notified_at = now() WHERE id = v_job.id;
  END LOOP;

  -- 7.3 (0073) "A combinar" nunca iniciado: aviso 3 dias antes de fechar
  -- (auto_expire_jobs 5.5, 30 dias depois de aceite), uma vez só.
  FOR v_job IN
    SELECT jr.*
    FROM   job_requests jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.status = 'confirmed'
      AND  jr.confirmed_date IS NULL
      AND  jr.started_at IS NULL
      AND  jr.reschedule_status IS DISTINCT FROM 'pending'
      AND  COALESCE(jp.accepted_at, jr.updated_at) < now() - INTERVAL '27 days'
      AND  jr.undated_expiry_warned_at IS NULL
    FOR UPDATE OF jr SKIP LOCKED
  LOOP
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Trabalho sem data',
        'Este trabalho ainda não tem data nem foi iniciado. Combine o dia com o cliente por WhatsApp e proponha a data na app. Se não for iniciado, fecha daqui a 3 dias.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'Trabalho sem data',
      'O trabalho ainda não tem data nem foi iniciado. Combine o dia com o profissional por WhatsApp. Se não for iniciado, fecha daqui a 3 dias.',
      v_job.id, 'job_request');

    UPDATE job_requests SET undated_expiry_warned_at = now() WHERE id = v_job.id;
  END LOOP;
END;
$function$;

-- job_photos_before_insert (antes em 0074_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.job_photos_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_client uuid;
  v_status text;
BEGIN
  -- 0074: um envio de cada vez por pedido, para a contagem do máximo de 2
  -- fotos não falhar com dois envios ao mesmo tempo. Advisory lock porque a
  -- cliente não tem permissão de UPDATE no pedido (FOR UPDATE não veria a linha).
  PERFORM pg_advisory_xact_lock(hashtextextended('job_photos:' || NEW.job_id::text, 0));

  SELECT client_id, status INTO v_client, v_status
  FROM   job_requests WHERE id = NEW.job_id;

  IF v_status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Só pode juntar fotos a um pedido aberto.';
  END IF;
  -- Ficheiros do próprio cliente (o cancel_job copia as linhas do pedido
  -- original, que estão na mesma pasta).
  IF NEW.storage_path IS NULL
     OR NEW.storage_path NOT LIKE v_client::text || '/%' THEN
    RAISE EXCEPTION 'Foto inválida.';
  END IF;
  IF (SELECT count(*) FROM job_photos WHERE job_id = NEW.job_id) >= 2 THEN
    RAISE EXCEPTION 'Cada pedido pode ter no máximo 2 fotos.';
  END IF;
  RETURN NEW;
END;
$function$;

-- submit_client_rating (antes em 0074_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.submit_client_rating(p_job_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
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
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Proposta aceite não encontrada.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliou esta pessoa neste trabalho.';
  END IF;
END;
$function$;

-- submit_helper_rating (antes em 0074_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.submit_helper_rating(p_job_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliou esta pessoa neste trabalho.';
  END IF;
END;
$function$;

-- submit_principal_rating (antes em 0074_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.submit_principal_rating(p_job_id uuid, p_ratee_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_valid     boolean := false;
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
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o prestador principal pode submeter esta avaliação.';
  END IF;

  IF p_ratee_id = v_job.client_id THEN v_valid := true; END IF;

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

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliou esta pessoa neste trabalho.';
  END IF;
END;
$function$;

-- withdraw_proposal (antes em 0074_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.withdraw_proposal(p_proposal_id uuid, p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  -- Mesma ordem de bloqueio do accept_proposal (pedido, depois proposta):
  -- se a cliente estiver a aceitar ao mesmo tempo, espera-se por ela e
  -- volta-se a ver o estado já atualizado.
  SELECT client_id INTO v_client_id
  FROM   job_requests WHERE id = p_job_id
  FOR UPDATE;

  PERFORM 1 FROM job_proposals
  WHERE  id        = p_proposal_id
    AND  job_id    = p_job_id
    AND  worker_id = auth.uid()
    AND  status    = 'pending'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou não pode ser retirada.';
  END IF;

  UPDATE job_proposals
  SET status = 'superseded', updated_at = now()
  WHERE id = p_proposal_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou não pode ser retirada.';
  END IF;

  UPDATE job_requests
  SET proposal_count = GREATEST(proposal_count - 1, 0),
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_client_id,
    'proposal_withdrawn',
    'Proposta retirada',
    'Um profissional retirou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$function$;

-- admin_get_worker (antes em 0078_admin_support_tracking.sql)
CREATE OR REPLACE FUNCTION public.admin_get_worker(p_worker_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_worker_id AND role = 'worker') THEN
    RAISE EXCEPTION 'Profissional não encontrado.';
  END IF;

  PERFORM public.admin_log('view_worker', p_worker_id, '{}'::jsonb);

  WITH principal AS (
    -- Trabalhos em que foi o responsável (proposta aceite).
    SELECT jr.*, jp.hourly_rate, jp.estimated_hours_min, jp.estimated_hours_max,
           jp.accepted_at, jp.pricing_mode, jp.total_price
    FROM   job_requests jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jp.worker_id = p_worker_id
  ), completed AS (
    -- Horas: soma dos dias de trabalho (0058); trabalhos antigos sem dias
    -- registados usam o início e a conclusão.
    SELECT pr.*,
           COALESCE(
             (SELECT sum(extract(epoch FROM wd.ended_at - wd.started_at)) / 3600
              FROM job_work_days wd
              WHERE wd.job_id = pr.id AND wd.ended_at IS NOT NULL),
             CASE WHEN pr.started_at IS NOT NULL AND pr.marked_done_at IS NOT NULL
                       AND pr.marked_done_at > pr.started_at
                  THEN extract(epoch FROM pr.marked_done_at - pr.started_at) / 3600 END
           ) AS tracked_hours
    FROM   principal pr
    WHERE  status = 'completed'
  ), proposals AS (
    SELECT jp.*, jr.created_at AS job_created_at
    FROM   job_proposals jp
    JOIN   job_requests jr ON jr.id = jp.job_id
    WHERE  jp.worker_id = p_worker_id
  )
  SELECT jsonb_build_object(
    'worker_id',       p.id,
    'full_name',       p.full_name,
    'phone',           public.admin_mask_phone(p.phone),
    'has_phone',       btrim(COALESCE(p.phone, '')) <> '',
    'avatar_url',      p.avatar_url,
    'created_at',      p.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'location_name',   wpr.location_name,
    'radius_km',       wpr.radius_km,
    'services',        COALESCE((
                         SELECT jsonb_agg(st.name ORDER BY st.sort_order, st.name)
                         FROM worker_service_types wst
                         JOIN service_types st ON st.id = wst.service_type_id
                         WHERE wst.worker_id = p.id), '[]'::jsonb),
    'proposals_sent',  (SELECT count(*) FROM proposals),
    'proposals_accepted', (SELECT count(*) FROM proposals WHERE status = 'accepted'),
    'avg_response_hours', (SELECT round((avg(extract(epoch FROM created_at - job_created_at))
                                         / 3600)::numeric, 1) FROM proposals),
    'jobs_completed',  (SELECT count(*) FROM completed),
    'jobs_active',     (SELECT count(*) FROM principal
                        WHERE status IN ('confirmed', 'awaiting_confirmation')),
    'jobs_cancelled_by_worker',
                       (SELECT count(*) FROM job_requests jr
                        WHERE jr.cancelled_by = p_worker_id),
    'tracked_hours',   (SELECT round(COALESCE(sum(tracked_hours), 0)::numeric, 1) FROM completed),
    -- Valor fechado conta o total; por hora, as horas registadas (ou o
    -- meio da estimativa).
    'estimated_revenue', (SELECT round(COALESCE(sum(
                            CASE WHEN pricing_mode = 'fixed_total' THEN total_price
                                 ELSE hourly_rate * COALESCE(
                                   tracked_hours,
                                   (estimated_hours_min + COALESCE(estimated_hours_max, estimated_hours_min)) / 2,
                                   0)
                            END), 0)::numeric, 0)
                          FROM completed),
    'helper_jobs',     (SELECT count(*) FROM help_acceptances ha
                        WHERE ha.worker_id = p_worker_id AND ha.status = 'accepted'),
    'avg_rating',      (SELECT round(avg(r.stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = p.id),
    'rating_count',    (SELECT count(*) FROM ratings r WHERE r.ratee_id = p.id),
    'jobs_this_month', public.worker_jobs_accepted_this_month(p.id),
    'monthly_jobs',    COALESCE((
                         SELECT jsonb_agg(jsonb_build_object('month', m.month, 'count', m.cnt)
                                          ORDER BY m.month)
                         FROM (
                           SELECT to_char(gs, 'YYYY-MM') AS month,
                                  (SELECT count(*) FROM principal pr
                                   WHERE pr.accepted_at >= gs
                                     AND pr.accepted_at <  gs + interval '1 month') AS cnt
                           FROM generate_series(
                                  date_trunc('month', now()) - interval '5 months',
                                  date_trunc('month', now()),
                                  interval '1 month') AS gs
                         ) m), '[]'::jsonb),
    'plan',            jsonb_build_object(
                         'active_tier', public.worker_active_tier(p.id),
                         'tier',        pl.tier,
                         'starts_at',   pl.starts_at,
                         'ends_at',     pl.ends_at,
                         'verified_at', pl.verified_at,
                         'notes',       pl.notes,
                         'updated_at',  pl.updated_at),
    'plan_history',    COALESCE((
                         SELECT jsonb_agg(jsonb_build_object(
                                  'created_at', a.created_at,
                                  'details',    a.details) ORDER BY a.created_at DESC)
                         FROM (SELECT * FROM admin_actions
                               WHERE target_id = p.id AND action = 'set_worker_plan'
                               ORDER BY created_at DESC LIMIT 20) a), '[]'::jsonb)
  ) INTO v_result
  FROM   profiles p
  LEFT JOIN worker_profiles wpr ON wpr.profile_id = p.id
  LEFT JOIN worker_plans    pl  ON pl.worker_id  = p.id
  LEFT JOIN auth.users      u   ON u.id          = p.id
  WHERE  p.id = p_worker_id;

  RETURN v_result;
END;
$function$;

-- admin_assert_reason (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_assert_reason(p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN (
       'user_request', 'app_error', 'terms_violation', 'illegal_content',
       'personal_data', 'duplicate', 'other') THEN
    RAISE EXCEPTION 'Escolhe um motivo da lista.';
  END IF;
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreva uma nota com o que aconteceu (5 carateres ou mais).';
  END IF;
END;
$function$;

-- admin_cancel_job (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_cancel_job(
  p_job_id         uuid,
  p_reason         text,
  p_note           text,
  p_public_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests;
  v_worker uuid;
  v_msg    text := NULLIF(btrim(left(COALESCE(p_public_message, ''), 500)), '');
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status NOT IN ('open', 'confirmed', 'awaiting_confirmation') THEN
    RAISE EXCEPTION 'Este pedido já está fechado.';
  END IF;
  v_worker := public.job_accepted_worker_id(p_job_id);

  UPDATE job_requests
  SET status               = 'cancelled',
      cancelled_by         = NULL,
      cancel_reason        = 'support',
      cancel_reason_detail = v_msg,
      cancelled_worker_id  = NULL,
      updated_at           = now()
  WHERE id = p_job_id;

  UPDATE job_proposals SET status = 'rejected', updated_at = now()
  WHERE job_id = p_job_id AND status = 'pending';

  UPDATE help_requests SET status = 'cancelled'
  WHERE job_id = p_job_id AND status <> 'cancelled';

  UPDATE help_acceptances SET status = 'rejected'
  WHERE help_request_id IN (SELECT id FROM help_requests WHERE job_id = p_job_id)
    AND status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_job_cancelled', 'Trabalho cancelado',
         'O trabalho em que ias ajudar foi cancelado pelo suporte.', p_job_id, 'job_request'
  FROM help_acceptances ha
  JOIN help_requests hr ON hr.id = ha.help_request_id
  WHERE hr.job_id = p_job_id AND ha.status = 'accepted';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT uid, 'job_cancelled', 'Pedido cancelado pelo suporte',
         COALESCE(v_msg, 'O suporte da ProJardim cancelou este pedido. Se tiver dúvidas, escreva para suporte@projardim.pt.'),
         p_job_id, 'job_request'
  FROM (SELECT v_job.client_id AS uid UNION SELECT v_worker) s
  WHERE uid IS NOT NULL;

  PERFORM public.admin_log('cancel_job', p_job_id, jsonb_strip_nulls(jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note), 'from', v_job.status,
    'public_message', v_msg)));
END;
$function$;

-- admin_hide_photo (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_hide_photo(
  p_job_id       uuid,
  p_storage_path text,
  p_reason       text,
  p_note         text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job   job_requests;
  v_kind  text;
  v_taken timestamptz;
  v_owner uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;

  IF EXISTS (SELECT 1 FROM job_photos WHERE job_id = p_job_id AND storage_path = p_storage_path) THEN
    v_kind := 'request';
    SELECT min(created_at) INTO v_taken FROM job_photos
    WHERE job_id = p_job_id AND storage_path = p_storage_path;
    DELETE FROM job_photos WHERE job_id = p_job_id AND storage_path = p_storage_path;
    v_owner := v_job.client_id;
  ELSIF p_storage_path = ANY (COALESCE(v_job.before_photo_paths, '{}')) THEN
    v_kind := 'before';
    v_taken := v_job.started_at;
    UPDATE job_requests SET before_photo_paths = array_remove(before_photo_paths, p_storage_path)
    WHERE id = p_job_id;
  ELSIF p_storage_path = ANY (COALESCE(v_job.after_photo_paths, '{}')) THEN
    v_kind := 'after';
    v_taken := v_job.marked_done_at;
    UPDATE job_requests SET after_photo_paths = array_remove(after_photo_paths, p_storage_path)
    WHERE id = p_job_id;
  ELSIF v_job.completion_photo_path = p_storage_path THEN
    v_kind := 'completion';
    v_taken := v_job.marked_done_at;
    UPDATE job_requests SET completion_photo_path = NULL WHERE id = p_job_id;
  ELSE
    RAISE EXCEPTION 'Foto não encontrada neste pedido.';
  END IF;
  v_owner := COALESCE(v_owner, public.job_accepted_worker_id(p_job_id));

  INSERT INTO job_photos_hidden (job_id, kind, storage_path, taken_at,
                                 hidden_by, hidden_reason, hidden_note)
  VALUES (p_job_id, v_kind, p_storage_path, v_taken, auth.uid(), p_reason, btrim(p_note));

  IF v_owner IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_owner, 'support_notice', 'Foto ocultada',
            'O suporte da ProJardim ocultou uma foto deste pedido. Se não concordar, responda para suporte@projardim.pt nos próximos 6 meses.',
            p_job_id, 'job_request');
  END IF;

  PERFORM public.admin_log('hide_photo', p_job_id, jsonb_build_object(
    'kind', v_kind, 'path', p_storage_path, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;

-- admin_hide_rating (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_hide_rating(p_rating_id uuid, p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rating ratings;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_rating FROM ratings WHERE id = p_rating_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avaliação não encontrada (pode já estar oculta).';
  END IF;

  INSERT INTO ratings_hidden (id, job_id, rater_id, ratee_id, stars, comment, created_at,
                              hidden_by, hidden_reason, hidden_note)
  VALUES (v_rating.id, v_rating.job_id, v_rating.rater_id, v_rating.ratee_id,
          v_rating.stars, v_rating.comment, v_rating.created_at,
          auth.uid(), p_reason, btrim(p_note));
  DELETE FROM ratings WHERE id = p_rating_id;

  IF v_rating.rater_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_rating.rater_id, 'support_notice', 'Avaliação ocultada',
            'O suporte da ProJardim ocultou uma avaliação sua por ' || CASE p_reason
              WHEN 'terms_violation' THEN 'não cumprir os Termos de Utilização'
              WHEN 'illegal_content' THEN 'conter conteúdo ilegal'
              WHEN 'personal_data'   THEN 'conter dados pessoais'
              WHEN 'user_request'    THEN 'pedido seu'
              ELSE 'decisão do suporte' END
            || '. Se não concordar, responda para suporte@projardim.pt nos próximos 6 meses.',
            v_rating.job_id, 'job_request');
  END IF;

  PERFORM public.admin_log('hide_rating', COALESCE(v_rating.job_id, p_rating_id), jsonb_build_object(
    'rating_id', p_rating_id, 'reason', p_reason, 'note', btrim(p_note),
    'stars', v_rating.stars, 'rater_id', v_rating.rater_id, 'ratee_id', v_rating.ratee_id));
END;
$function$;

-- admin_reopen_job (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_reopen_job(p_job_id uuid, p_reason text, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job job_requests;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'no_response' THEN
    RAISE EXCEPTION 'Só se reabrem pedidos que expiraram sem resposta.';
  END IF;

  UPDATE job_requests
  SET status                   = 'open',
      expires_at               = now() + interval '48 hours',
      proposal_count           = 0,
      date_mode                = CASE WHEN date_mode = 'fixed'
                                       AND (preferred_date IS NULL OR preferred_date < today_pt())
                                      THEN 'flexible' ELSE date_mode END,
      preferred_date           = CASE WHEN date_mode = 'fixed'
                                       AND (preferred_date IS NULL OR preferred_date < today_pt())
                                      THEN NULL ELSE preferred_date END,
      direct_status            = CASE WHEN direct_status IS NULL THEN NULL ELSE 'released' END,
      direct_until             = NULL,
      direct_hold_reason       = NULL,
      followup_stage           = 0,
      no_proposals_nudged_at   = NULL,
      undated_expiry_warned_at = NULL,
      updated_at               = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_job.client_id, 'job_reopened', 'Pedido reaberto pelo suporte',
          'O seu pedido voltou a estar aberto a propostas durante 48 horas.',
          p_job_id, 'job_request');

  PERFORM public.admin_log('reopen_job', p_job_id, jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;

-- admin_restore_rating (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_restore_rating(p_rating_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hidden ratings_hidden;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreva uma nota com o motivo (5 carateres ou mais).';
  END IF;
  SELECT * INTO v_hidden FROM ratings_hidden WHERE id = p_rating_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avaliação oculta não encontrada.';
  END IF;

  DELETE FROM ratings_hidden WHERE id = p_rating_id;
  INSERT INTO ratings (id, job_id, rater_id, ratee_id, stars, comment, created_at)
  VALUES (v_hidden.id, v_hidden.job_id, v_hidden.rater_id, v_hidden.ratee_id,
          v_hidden.stars, v_hidden.comment, v_hidden.created_at);

  PERFORM public.admin_log('restore_rating', COALESCE(v_hidden.job_id, p_rating_id), jsonb_build_object(
    'rating_id', p_rating_id, 'note', btrim(p_note)));
END;
$function$;

-- admin_set_job_status (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_set_job_status(
  p_job_id uuid,
  p_status text,
  p_reason text,
  p_note   text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job    job_requests;
  v_worker uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  v_worker := public.job_accepted_worker_id(p_job_id);

  IF p_status = 'completed' THEN
    IF v_job.status NOT IN ('confirmed', 'awaiting_confirmation') THEN
      RAISE EXCEPTION 'Só se marca como concluído um trabalho confirmado ou à espera de confirmação.';
    END IF;
    UPDATE job_requests
    SET status         = 'completed',
        started_at     = COALESCE(started_at, now()),
        marked_done_at = COALESCE(marked_done_at, now()),
        updated_at     = now()
    WHERE id = p_job_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT uid, 'job_completed', 'Trabalho concluído',
           'O suporte da ProJardim marcou este trabalho como concluído.', p_job_id, 'job_request'
    FROM (SELECT v_job.client_id AS uid UNION SELECT v_worker) s
    WHERE uid IS NOT NULL;

  ELSIF p_status = 'awaiting_confirmation' THEN
    IF v_job.status <> 'completed' THEN
      RAISE EXCEPTION 'Só se anula a confirmação de um trabalho concluído.';
    END IF;
    UPDATE job_requests
    SET status                        = 'awaiting_confirmation',
        marked_done_at                = now(),
        confirmation_reminder_sent_at = NULL,
        updated_at                    = now()
    WHERE id = p_job_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_marked_done', 'Confirme o trabalho',
            'O suporte da ProJardim voltou a pôr este trabalho à espera da sua confirmação. Tem 7 dias.',
            p_job_id, 'job_request');
    IF v_worker IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker, 'support_notice', 'Trabalho à espera de confirmação',
              'O suporte da ProJardim voltou a pôr este trabalho à espera da confirmação da cliente.',
              p_job_id, 'job_request');
    END IF;
  ELSE
    RAISE EXCEPTION 'Estado inválido.';
  END IF;

  PERFORM public.admin_log('set_job_status', p_job_id, jsonb_build_object(
    'from', v_job.status, 'to', p_status, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;

-- admin_set_report_status (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.admin_set_report_status(p_report_id uuid, p_status text, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_report job_reports;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT * INTO v_report FROM job_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reporte não encontrado.';
  END IF;
  IF p_status NOT IN ('new', 'in_review', 'resolved', 'dismissed') THEN
    RAISE EXCEPTION 'Estado inválido.';
  END IF;
  IF p_status IN ('resolved', 'dismissed') AND length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreva uma nota com a decisão (5 carateres ou mais).';
  END IF;

  UPDATE job_reports
  SET status = p_status,
      resolved_at = CASE WHEN p_status IN ('resolved', 'dismissed') THEN now() END
  WHERE id = p_report_id;

  PERFORM public.admin_log('report_status', v_report.job_id, jsonb_strip_nulls(jsonb_build_object(
    'report_id', p_report_id, 'from', v_report.status, 'to', p_status,
    'note', NULLIF(btrim(COALESCE(p_note, '')), ''))));
END;
$function$;

-- block_rating_while_hidden (antes em 0079_admin_support_resolve.sql)
CREATE OR REPLACE FUNCTION public.block_rating_while_hidden()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM ratings_hidden h
             WHERE h.job_id = NEW.job_id AND h.rater_id = NEW.rater_id
               AND h.ratee_id = NEW.ratee_id) THEN
    RAISE EXCEPTION 'Já avaliou este trabalho.';
  END IF;
  RETURN NEW;
END;
$function$;

-- account_delete_core (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.account_delete_core(p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := p_uid;
  v_email     text;
  v_old_email text;
  v_pwd       text;
  v_blocker   text;
  r           record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Conta não encontrada.';
  END IF;

  PERFORM 1 FROM profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conta não encontrada.';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Esta conta já foi eliminada.';
  END IF;

  -- ── Trabalho em curso: recusa ──────────────────────────────────
  v_blocker := account_deletion_blocker(v_uid);
  IF v_blocker IS NOT NULL THEN
    RAISE EXCEPTION '%', v_blocker;
  END IF;

  -- 0080: uma conta suspensa também se pode eliminar; o trigger
  -- block_suspended_writes deixa passar o resto desta transação.
  PERFORM set_config('projardim.allow_suspended', 'on', true);

  -- ── Como cliente: cancela os pedidos abertos ───────────────────
  -- O pedido fica cancelled antes de as propostas passarem a rejected,
  -- para o trigger da 0048 avisar cada jardineiro com o texto certo.
  FOR r IN
    SELECT id FROM job_requests
    WHERE  client_id = v_uid AND status = 'open'
    FOR UPDATE
  LOOP
    UPDATE job_requests
    SET    status        = 'cancelled',
           cancelled_by  = v_uid,
           cancel_reason = 'no_longer_needed',
           updated_at    = now()
    WHERE  id = r.id;

    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = r.id AND status = 'pending';
  END LOOP;

  -- ── Como jardineiro: retira as propostas pendentes ─────────────
  -- Mesmo efeito que withdraw_proposal (superseded, contador, aviso).
  FOR r IN
    SELECT jp.id, jp.job_id, jr.client_id, jr.status AS job_status
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    WHERE  jp.worker_id = v_uid AND jp.status = 'pending'
    FOR UPDATE OF jp
  LOOP
    UPDATE job_proposals
    SET    status = 'superseded', updated_at = now()
    WHERE  id = r.id;

    UPDATE job_requests
    SET    proposal_count = GREATEST(proposal_count - 1, 0),
           updated_at     = now()
    WHERE  id = r.job_id;

    IF r.job_status = 'open' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.client_id, 'proposal_withdrawn', 'Proposta retirada',
        'Um profissional retirou a proposta que lhe tinha feito.',
        r.job_id, 'job_request');
    END IF;
  END LOOP;

  -- ── 0070: pedidos diretos à espera deste jardineiro ────────────
  -- Antes ficavam reservados até 24h a uma conta que já não existe.
  -- Mesmo efeito que "Não posso": mostra a outros ou para e avisa a
  -- cliente, conforme ela escolheu. Corre antes de apagar o nome.
  FOR r IN
    SELECT id FROM job_requests
    WHERE  direct_worker_id = v_uid
      AND  status = 'open'
      AND  direct_status = 'waiting'
    FOR UPDATE
  LOOP
    PERFORM end_direct_reservation(r.id, 'declined');
  END LOOP;

  -- ── Candidaturas a ajudante ainda por decidir ──────────────────
  UPDATE help_acceptances
  SET    status = 'cancelled'
  WHERE  worker_id = v_uid AND status = 'pending';

  -- ── Pedidos de ajuda do próprio ainda por preencher ────────────
  FOR r IN
    SELECT hr.id
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  jp.worker_id = v_uid
      AND  hr.status IN ('pending_approval', 'open')
    FOR UPDATE OF hr
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O profissional responsável fechou o pedido de ajuda.',
           r.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = r.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = r.id AND status = 'pending';

    UPDATE help_requests SET status = 'cancelled' WHERE id = r.id;
  END LOOP;

  -- ── Dados pessoais (sem DELETE do perfil: há FKs sem cascade) ──
  PERFORM erase_account_data(v_uid);

  -- ── auth: bloqueia o email 90 dias, depois tira-o da conta ─────
  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE 'SELECT email FROM auth.users WHERE id = $1'
      INTO v_old_email USING v_uid;

    IF public.email_block_hash(v_old_email) IS NOT NULL THEN
      INSERT INTO deleted_account_emails (email_hash, deleted_at, blocked_until)
      VALUES (public.email_block_hash(v_old_email), now(), now() + interval '90 days')
      ON CONFLICT (email_hash) DO UPDATE
        SET deleted_at    = EXCLUDED.deleted_at,
            blocked_until = EXCLUDED.blocked_until;
    END IF;
  END IF;

  v_email := 'eliminado+' || v_uid::text || '@invalid.local';

  IF to_regprocedure('extensions.crypt(text,text)') IS NOT NULL
     AND to_regprocedure('extensions.gen_salt(text)') IS NOT NULL THEN
    EXECUTE 'SELECT extensions.crypt($1, extensions.gen_salt(''bf''))'
      INTO v_pwd USING gen_random_uuid()::text;
  ELSIF to_regprocedure('public.crypt(text,text)') IS NOT NULL
     AND to_regprocedure('public.gen_salt(text)') IS NOT NULL THEN
    EXECUTE 'SELECT public.crypt($1, public.gen_salt(''bf''))'
      INTO v_pwd USING gen_random_uuid()::text;
  ELSE
    -- Não é um hash bcrypt válido: nenhuma palavra-passe lhe corresponde.
    v_pwd := 'deleted:' || md5(gen_random_uuid()::text || clock_timestamp()::text);
  END IF;

  IF to_regclass('auth.users') IS NOT NULL THEN
    -- banned_until a 1000 anos em vez de 'infinity': o GoTrue lê esta
    -- coluna para time.Time e um timestamp infinito dá erro ao ler o
    -- utilizador.
    EXECUTE $sql$
      UPDATE auth.users
      SET    email              = $2,
             phone              = NULL,
             raw_user_meta_data = '{}'::jsonb,
             encrypted_password = $3,
             banned_until       = now() + interval '1000 years',
             updated_at         = now()
      WHERE  id = $1
    $sql$ USING v_uid, v_email, v_pwd;

    -- Colunas que só existem em versões do GoTrue: limpa-as se existirem.
    BEGIN
      EXECUTE 'UPDATE auth.users SET email_change = '''', phone_change = '''' WHERE id = $1'
        USING v_uid;
    EXCEPTION WHEN undefined_column THEN
      NULL;
    END;
  END IF;

  -- identities guarda o email (provider_id/identity_data); refresh_tokens
  -- tem user_id em varchar, por isso a comparação é sempre em texto.
  IF to_regclass('auth.identities') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.identities WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.refresh_tokens') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.refresh_tokens WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.sessions') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.sessions WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.mfa_factors') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.mfa_factors WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.one_time_tokens') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.one_time_tokens WHERE user_id::text = $1' USING v_uid::text;
  END IF;
END;
$function$;

-- account_suspend_core (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.account_suspend_core(
  p_uid     uuid,
  p_reason  text,
  p_message text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r       record;
  v_open  integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_uid AND deleted_at IS NULL) THEN
    RETURN 0;
  END IF;
  INSERT INTO account_status (profile_id, suspended_at, suspended_reason, suspended_message)
  VALUES (p_uid, now(), p_reason, p_message)
  ON CONFLICT (profile_id) DO UPDATE
    SET suspended_at = now(), suspended_reason = p_reason,
        suspended_message = p_message, updated_at = now()
    WHERE account_status.suspended_at IS NULL;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  -- Como cliente: pedidos abertos fecham. O pedido fica cancelado antes de
  -- as propostas passarem a recusadas, para o aviso dizer que foi o suporte.
  FOR r IN SELECT id FROM job_requests
           WHERE client_id = p_uid AND status = 'open' FOR UPDATE
  LOOP
    UPDATE job_requests
    SET status = 'cancelled', cancelled_by = NULL,
        cancel_reason = 'account_suspended', updated_at = now()
    WHERE id = r.id;
    UPDATE job_proposals SET status = 'rejected', updated_at = now()
    WHERE job_id = r.id AND status = 'pending';
  END LOOP;

  -- Como jardineiro: propostas pendentes retiradas (como withdraw_proposal).
  FOR r IN
    SELECT jp.id, jp.job_id, jr.client_id, jr.status AS job_status
    FROM job_proposals jp JOIN job_requests jr ON jr.id = jp.job_id
    WHERE jp.worker_id = p_uid AND jp.status = 'pending'
    FOR UPDATE OF jp
  LOOP
    UPDATE job_proposals SET status = 'superseded', updated_at = now() WHERE id = r.id;
    UPDATE job_requests SET proposal_count = GREATEST(proposal_count - 1, 0), updated_at = now()
    WHERE id = r.job_id;
    IF r.job_status = 'open' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.client_id, 'proposal_withdrawn', 'Proposta retirada',
              'Um profissional deixou de estar disponível e a proposta saiu do seu pedido.',
              r.job_id, 'job_request');
    END IF;
  END LOOP;

  -- Pedidos diretos à espera deste jardineiro: como "Não posso".
  FOR r IN SELECT id FROM job_requests
           WHERE direct_worker_id = p_uid AND status = 'open' AND direct_status = 'waiting'
           FOR UPDATE
  LOOP
    PERFORM end_direct_reservation(r.id, 'declined');
  END LOOP;

  UPDATE help_acceptances SET status = 'cancelled'
  WHERE worker_id = p_uid AND status = 'pending';

  -- Pedidos de ajuda dele ainda por preencher fecham (como ao eliminar).
  FOR r IN
    SELECT hr.id FROM help_requests hr JOIN job_proposals jp ON jp.id = hr.proposal_id
    WHERE jp.worker_id = p_uid AND hr.status IN ('pending_approval', 'open')
    FOR UPDATE OF hr
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O pedido de ajuda fechou.', r.id, 'help_request'
    FROM help_acceptances ha WHERE ha.help_request_id = r.id AND ha.status = 'pending';
    UPDATE help_acceptances SET status = 'rejected'
    WHERE help_request_id = r.id AND status = 'pending';
    UPDATE help_requests SET status = 'cancelled' WHERE id = r.id;
  END LOOP;

  SELECT count(*) INTO v_open
  FROM job_requests jr
  LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
  WHERE (jr.client_id = p_uid OR jp.worker_id = p_uid)
    AND jr.status IN ('confirmed', 'awaiting_confirmation');

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_uid, 'support_notice', 'Conta suspensa',
          COALESCE(p_message, 'A sua conta ProJardim foi suspensa pelo suporte.')
          || ' Para contestar, responda para suporte@projardim.pt nos próximos 6 meses.');
  RETURN v_open;
END;
$function$;

-- admin_cancel_closure (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_cancel_closure(p_target_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreva uma nota com o motivo (5 carateres ou mais).';
  END IF;
  UPDATE account_status
  SET closing_at = NULL, closing_reason = NULL, closing_message = NULL, updated_at = now()
  WHERE profile_id = p_target_id AND closing_at IS NOT NULL AND suspended_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta conta não tem encerramento marcado.';
  END IF;

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_target_id, 'support_notice', 'Encerramento cancelado',
          'O encerramento da sua conta ProJardim foi cancelado. A conta continua ativa.');

  PERFORM public.admin_log('cancel_closure', p_target_id, jsonb_build_object('note', btrim(p_note)));
END;
$function$;

-- admin_erase_user (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_erase_user(p_target_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_paths jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreve uma nota com o pedido (quem pediu, quando, por onde).';
  END IF;
  IF p_target_id = auth.uid() THEN
    RAISE EXCEPTION 'Para eliminar a sua conta, use a app.';
  END IF;
  IF EXISTS (SELECT 1 FROM admin_users WHERE user_id = p_target_id) THEN
    RAISE EXCEPTION 'Esta conta é de administrador; retira-a de admin_users primeiro.';
  END IF;

  -- Antes de apagar: os caminhos ainda estão nos pedidos.
  v_paths := public.account_storage_paths(p_target_id);
  PERFORM public.account_delete_core(p_target_id);

  PERFORM public.admin_log('erase_user', p_target_id, jsonb_build_object(
    'note', btrim(p_note), 'storage', v_paths));
  RETURN v_paths;
END;
$function$;

-- admin_hide_profile_photo (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_hide_profile_photo(
  p_target_id uuid,
  p_url       text,
  p_reason    text,
  p_note      text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_kind text;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);

  IF EXISTS (SELECT 1 FROM profiles WHERE id = p_target_id AND avatar_url = p_url) THEN
    v_kind := 'avatar';
    UPDATE profiles SET avatar_url = NULL, updated_at = now() WHERE id = p_target_id;
  ELSIF EXISTS (SELECT 1 FROM worker_profiles WHERE profile_id = p_target_id
                AND p_url = ANY (COALESCE(photos, '{}'))) THEN
    v_kind := 'portfolio';
    UPDATE worker_profiles SET photos = array_remove(photos, p_url), updated_at = now()
    WHERE profile_id = p_target_id;
  ELSE
    RAISE EXCEPTION 'Foto não encontrada neste perfil.';
  END IF;

  INSERT INTO profile_photos_hidden (profile_id, kind, url, hidden_by, hidden_reason, hidden_note)
  VALUES (p_target_id, v_kind, p_url, auth.uid(), p_reason, btrim(p_note));

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_target_id, 'support_notice', 'Foto retirada',
          CASE v_kind WHEN 'avatar'
            THEN 'O suporte da ProJardim retirou a sua foto de perfil. Pode colocar outra que cumpra os Termos.'
            ELSE 'O suporte da ProJardim retirou uma foto do seu perfil.' END
          || ' Se não concordar, responda para suporte@projardim.pt nos próximos 6 meses.');

  PERFORM public.admin_log('hide_profile_photo', p_target_id, jsonb_build_object(
    'kind', v_kind, 'url', p_url, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;

-- admin_reactivate_user (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_reactivate_user(p_target_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status account_status;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreva uma nota com o motivo (5 carateres ou mais).';
  END IF;
  SELECT * INTO v_status FROM account_status WHERE profile_id = p_target_id FOR UPDATE;
  IF NOT FOUND OR v_status.suspended_at IS NULL THEN
    RAISE EXCEPTION 'Esta conta não está suspensa.';
  END IF;

  UPDATE account_status
  SET suspended_at = NULL, suspended_reason = NULL, suspended_message = NULL,
      -- Um encerramento já cumprido não volta a disparar.
      closing_at      = CASE WHEN closing_at <= now() THEN NULL ELSE closing_at END,
      closing_reason  = CASE WHEN closing_at <= now() THEN NULL ELSE closing_reason END,
      closing_message = CASE WHEN closing_at <= now() THEN NULL ELSE closing_message END,
      updated_at = now()
  WHERE profile_id = p_target_id;

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_target_id, 'support_notice', 'Conta reativada',
          'A sua conta ProJardim voltou a estar ativa.');

  PERFORM public.admin_log('reactivate_user', p_target_id, jsonb_build_object(
    'note', btrim(p_note), 'suspended_reason', v_status.suspended_reason));
END;
$function$;

-- admin_schedule_closure (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_schedule_closure(
  p_target_id      uuid,
  p_reason         text,
  p_note           text,
  p_public_message text DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_profile profiles;
  v_at      timestamptz := now() + interval '30 days';
  v_msg     text := NULLIF(btrim(left(COALESCE(p_public_message, ''), 500)), '');
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);
  IF p_target_id = auth.uid() THEN
    RAISE EXCEPTION 'Não pode encerrar a sua própria conta.';
  END IF;
  SELECT * INTO v_profile FROM profiles WHERE id = p_target_id FOR UPDATE;
  IF NOT FOUND OR v_profile.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Conta não encontrada ou eliminada.';
  END IF;
  IF public.is_account_suspended(p_target_id) THEN
    RAISE EXCEPTION 'Esta conta já está suspensa.';
  END IF;
  IF EXISTS (SELECT 1 FROM account_status WHERE profile_id = p_target_id AND closing_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Já há um encerramento marcado para esta conta.';
  END IF;

  INSERT INTO account_status (profile_id, closing_at, closing_reason, closing_message)
  VALUES (p_target_id, v_at, p_reason, v_msg)
  ON CONFLICT (profile_id) DO UPDATE
    SET closing_at = v_at, closing_reason = p_reason, closing_message = v_msg, updated_at = now();

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_target_id, 'support_notice', 'Aviso de encerramento da conta',
          'A ProJardim vai encerrar a sua conta a '
          || to_char(v_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY') || '. '
          || COALESCE(v_msg || ' ', '')
          || 'Até lá pode continuar a usar a app. Para contestar, responda para suporte@projardim.pt.');

  PERFORM public.admin_log('schedule_closure', p_target_id, jsonb_strip_nulls(jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note), 'public_message', v_msg, 'closing_at', v_at)));
  RETURN v_at;
END;
$function$;

-- admin_suspend_user (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_suspend_user(
  p_target_id      uuid,
  p_reason         text,
  p_note           text,
  p_public_message text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_profile profiles;
  v_open    integer;
  v_msg     text := NULLIF(btrim(left(COALESCE(p_public_message, ''), 500)), '');
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_assert_reason(p_reason, p_note);
  IF p_target_id = auth.uid() THEN
    RAISE EXCEPTION 'Não pode suspender a sua própria conta.';
  END IF;
  SELECT * INTO v_profile FROM profiles WHERE id = p_target_id FOR UPDATE;
  IF NOT FOUND OR v_profile.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Conta não encontrada ou eliminada.';
  END IF;
  IF public.is_account_suspended(p_target_id) THEN
    RAISE EXCEPTION 'Esta conta já está suspensa.';
  END IF;

  v_open := public.account_suspend_core(p_target_id, p_reason, v_msg);

  PERFORM public.admin_log('suspend_user', p_target_id, jsonb_strip_nulls(jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note), 'public_message', v_msg,
    'jobs_in_progress', v_open)));
  RETURN v_open;
END;
$function$;

-- block_suspended_writes (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.block_suspended_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  -- account_delete_core liga isto: quem está suspenso pode eliminar a conta.
  IF current_setting('projardim.allow_suspended', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF v_uid IS NOT NULL AND public.is_account_suspended(v_uid) THEN
    RAISE EXCEPTION 'A sua conta está suspensa. Escreva para suporte@projardim.pt.';
  END IF;
  -- IFs separados: NEW.direct_* só existe em job_requests.
  IF TG_TABLE_NAME = 'job_requests' AND TG_OP = 'INSERT' THEN
    IF public.is_account_suspended(NEW.direct_worker_id)
       OR public.is_account_suspended(NEW.direct_card_worker_id) THEN
      RAISE EXCEPTION 'Este profissional não está disponível.';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

-- notify_proposal_closed_with_job (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.notify_proposal_closed_with_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_status    text;
  v_cancel_reason text;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
    SELECT status, cancel_reason INTO v_job_status, v_cancel_reason
    FROM job_requests WHERE id = NEW.job_id;

    IF v_job_status = 'cancelled' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido cancelado',
        CASE WHEN v_cancel_reason IN ('support', 'account_suspended')
             THEN 'O suporte da ProJardim cancelou o pedido a que fez uma proposta.'
             ELSE 'O cliente cancelou o pedido a que fez uma proposta.' END,
        NEW.job_id, 'job_request');
    ELSIF v_job_status = 'no_response' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido fechado',
        'O pedido fechou sem o cliente escolher a sua proposta.',
        NEW.job_id, 'job_request');
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

-- process_account_closures (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.process_account_closures()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r   record;
  v_n integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;
  FOR r IN SELECT s.profile_id AS id, s.closing_reason, s.closing_message
           FROM account_status s JOIN profiles p ON p.id = s.profile_id
           WHERE s.closing_at <= now() AND s.suspended_at IS NULL AND p.deleted_at IS NULL
           FOR UPDATE OF s SKIP LOCKED
  LOOP
    PERFORM public.account_suspend_core(
      r.id, COALESCE(r.closing_reason, 'other'),
      COALESCE(r.closing_message, 'A sua conta ProJardim foi encerrada, como avisámos há 30 dias.'));
    INSERT INTO admin_actions (admin_id, action, target_id, details)
    VALUES (NULL, 'closure_done', r.id, jsonb_build_object('reason', r.closing_reason));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- admin_check_notice_audience (antes em 0081_admin_growth.sql)
CREATE OR REPLACE FUNCTION public.admin_check_notice_audience(p_role text, p_tiers text[])
RETURNS void
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('worker', 'client') THEN
    RAISE EXCEPTION 'Escolha para quem é o aviso: profissionais ou clientes.';
  END IF;
  IF p_tiers IS NOT NULL AND NOT (p_tiers <@ ARRAY['free', 'pro', 'pro_plus']) THEN
    RAISE EXCEPTION 'Plano inválido.';
  END IF;
END;
$function$;

-- admin_export_rows (antes em 0081_admin_growth.sql)
CREATE OR REPLACE FUNCTION public.admin_export_rows(p_kind text, p_days integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_from    timestamptz := public.admin_period_start(p_days);
  v_columns jsonb;
  v_rows    jsonb;
BEGIN
  PERFORM public.assert_verified_admin();

  IF p_kind = 'jobs' THEN
    v_columns := '["id","criado","estado","servico","localidade","data","propostas","profissional","motivo_cancelamento","pedido_direto"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.created_at, x.status, x.service, x.area, x.when_text, x.proposal_count,
             x.worker, x.cancel_reason, x.direct) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT jr.id, jr.created_at, jr.status, st.name AS service, jr.location_area AS area,
             COALESCE(jr.confirmed_date::text, jr.preferred_date::text, jr.date_mode) AS when_text,
             jr.proposal_count, wp.full_name AS worker, jr.cancel_reason,
             (jr.direct_worker_id IS NOT NULL OR jr.direct_card_worker_id IS NOT NULL) AS direct
      FROM job_requests jr
      LEFT JOIN service_types st ON st.id = jr.service_type_id
      LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
      LEFT JOIN profiles wp ON wp.id = jp.worker_id
      WHERE jr.created_at >= v_from
      ORDER BY jr.created_at DESC
      LIMIT 10000
    ) x;

  ELSIF p_kind = 'clients' THEN
    v_columns := '["id","nome","registo","pedidos","concluidos","cancelados","ultimo_pedido","estado"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.full_name, x.created_at, x.jobs, x.completed, x.cancelled, x.last_job, x.state)
             ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT p.id, p.full_name, p.created_at,
             count(jr.id) AS jobs,
             count(jr.id) FILTER (WHERE jr.status = 'completed') AS completed,
             count(jr.id) FILTER (WHERE jr.status = 'cancelled') AS cancelled,
             max(jr.created_at) AS last_job,
             CASE WHEN p.deleted_at IS NOT NULL THEN 'eliminada'
                  WHEN s.suspended_at IS NOT NULL THEN 'suspensa'
                  ELSE 'ativa' END AS state
      FROM profiles p
      LEFT JOIN job_requests jr ON jr.client_id = p.id
      LEFT JOIN account_status s ON s.profile_id = p.id
      WHERE p.role = 'client' AND p.created_at >= v_from
        AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)
      GROUP BY p.id, s.suspended_at
      ORDER BY p.created_at DESC
      LIMIT 10000
    ) x;

  ELSIF p_kind = 'workers' THEN
    v_columns := '["id","nome","registo","localidade","raio_km","plano","servicos","propostas","aceites","concluidos","media","avaliacoes","estado"]';
    SELECT COALESCE(jsonb_agg(jsonb_build_array(
             x.id, x.full_name, x.created_at, x.location_name, x.radius_km, x.tier, x.services,
             x.proposals, x.accepted, x.completed, x.avg_rating, x.ratings, x.state)
             ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT p.id, p.full_name, p.created_at, wp.location_name, wp.radius_km,
             public.worker_active_tier(p.id) AS tier,
             (SELECT count(*) FROM worker_service_types wst WHERE wst.worker_id = p.id) AS services,
             (SELECT count(*) FROM job_proposals jp WHERE jp.worker_id = p.id) AS proposals,
             (SELECT count(*) FROM job_requests jr JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
              WHERE jp.worker_id = p.id) AS accepted,
             (SELECT count(*) FROM job_requests jr JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
              WHERE jp.worker_id = p.id AND jr.status = 'completed') AS completed,
             (SELECT round(avg(stars)::numeric, 2) FROM ratings r WHERE r.ratee_id = p.id) AS avg_rating,
             (SELECT count(*) FROM ratings r WHERE r.ratee_id = p.id) AS ratings,
             CASE WHEN p.deleted_at IS NOT NULL THEN 'eliminada'
                  WHEN EXISTS (SELECT 1 FROM account_status s
                               WHERE s.profile_id = p.id AND s.suspended_at IS NOT NULL) THEN 'suspensa'
                  ELSE 'ativa' END AS state
      FROM profiles p
      LEFT JOIN worker_profiles wp ON wp.profile_id = p.id
      WHERE p.role = 'worker' AND p.created_at >= v_from
        AND NOT EXISTS (SELECT 1 FROM admin_users a WHERE a.user_id = p.id)
      ORDER BY p.created_at DESC
      LIMIT 10000
    ) x;

  ELSE
    RAISE EXCEPTION 'Tipo de exportação inválido.';
  END IF;

  PERFORM public.admin_log('export_csv', NULL, jsonb_build_object(
    'kind', p_kind, 'days', p_days, 'rows', jsonb_array_length(v_rows)));
  RETURN jsonb_build_object('columns', v_columns, 'rows', v_rows);
END;
$function$;

-- admin_review_fleet_card (antes em 0082_admin_partners_zones.sql)
CREATE OR REPLACE FUNCTION public.admin_review_fleet_card(
  p_card_id  uuid,
  p_decision text,
  p_reason   text DEFAULT NULL,
  p_message  text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_card    worker_fleet_cards%ROWTYPE;
  v_latest  uuid;
  v_message text := NULLIF(btrim(COALESCE(p_message, '')), '');
  v_action  text;
BEGIN
  PERFORM public.assert_verified_admin();

  SELECT * INTO v_card FROM worker_fleet_cards WHERE id = p_card_id FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM profiles
                              WHERE id = v_card.worker_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Cartão não encontrado.';
  END IF;

  SELECT fc.id INTO v_latest FROM worker_fleet_cards fc
  WHERE fc.worker_id = v_card.worker_id
  ORDER BY fc.created_at DESC, fc.id DESC LIMIT 1;
  IF v_latest <> v_card.id THEN
    RAISE EXCEPTION 'O profissional já pediu outro cartão depois deste. Decida o mais recente.';
  END IF;

  IF p_decision = 'active' THEN
    IF v_card.status <> 'pending' THEN
      RAISE EXCEPTION 'Este cartão já não está à espera de aprovação.';
    END IF;
    v_action := 'fleet_card_approved';
    v_message := NULL;
  ELSIF p_decision = 'rejected' THEN
    IF v_card.status = 'rejected' THEN
      RAISE EXCEPTION 'Este cartão já está recusado.';
    END IF;
    IF p_reason IS NULL OR p_reason NOT IN ('unreadable', 'not_eligible', 'partner_refused', 'other') THEN
      RAISE EXCEPTION 'Escolhe um motivo da lista.';
    END IF;
    IF p_reason = 'other' AND length(COALESCE(v_message, '')) < 10 THEN
      RAISE EXCEPTION 'Escreva ao profissional o motivo (10 carateres ou mais).';
    END IF;
    IF length(COALESCE(v_message, '')) > 300 THEN
      RAISE EXCEPTION 'A mensagem tem de ter até 300 carateres.';
    END IF;
    v_message := COALESCE(v_message, CASE p_reason
      WHEN 'unreadable' THEN 'Não conseguimos ler os dados do cartão. Fotografa-o outra vez, com boa luz.'
      WHEN 'not_eligible' THEN 'O cartão frota é um benefício do plano Pro+.'
      WHEN 'partner_refused' THEN 'A gasolineira parceira não aceitou este cartão.'
    END);
    v_action := CASE WHEN v_card.status = 'active' THEN 'fleet_card_revoked' ELSE 'fleet_card_rejected' END;
  ELSE
    RAISE EXCEPTION 'Decisão desconhecida.';
  END IF;

  UPDATE worker_fleet_cards
  SET status = p_decision, reviewed_at = now(), review_message = v_message
  WHERE id = v_card.id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_card.worker_id, 'fleet_card_reviewed',
          CASE v_action
            WHEN 'fleet_card_approved' THEN 'Cartão frota ativo'
            WHEN 'fleet_card_revoked' THEN 'Cartão frota desativado'
            ELSE 'Cartão frota recusado' END,
          CASE v_action
            WHEN 'fleet_card_approved' THEN 'O seu cartão frota foi aprovado. Já o pode mostrar na gasolineira.'
            ELSE v_message END,
          v_card.id, 'fleet_card');

  PERFORM public.admin_log(v_action, v_card.worker_id,
    jsonb_build_object('card_id', v_card.id, 'reason', p_reason, 'message', v_message));
  RETURN p_decision;
END;
$function$;

-- admin_send_notice (antes em 0082_admin_partners_zones.sql)
CREATE OR REPLACE FUNCTION public.admin_send_notice(
  p_title           text,
  p_body            text,
  p_role            text,
  p_tiers           text[],
  p_service_type_id uuid,
  p_area            text,
  p_expected        integer,
  p_partner_id      uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_title    text := btrim(COALESCE(p_title, ''));
  v_body     text := btrim(COALESCE(p_body, ''));
  v_n        integer;
  v_id       uuid;
  v_audience jsonb;
  v_partner  text;
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_check_notice_audience(p_role, p_tiers);
  IF length(v_title) < 3 OR length(v_title) > 80 THEN
    RAISE EXCEPTION 'O título tem de ter entre 3 e 80 carateres.';
  END IF;
  IF length(v_body) < 10 OR length(v_body) > 500 THEN
    RAISE EXCEPTION 'O texto tem de ter entre 10 e 500 carateres.';
  END IF;
  IF p_partner_id IS NOT NULL THEN
    IF p_role <> 'worker' THEN
      RAISE EXCEPTION 'Os avisos de parceiro são só para profissionais.';
    END IF;
    SELECT pa.name INTO v_partner FROM partners pa
    WHERE pa.id = p_partner_id AND pa.status = 'active' AND pa.visible_in_app
      AND (pa.valid_until IS NULL OR pa.valid_until >= CURRENT_DATE);
    IF v_partner IS NULL THEN
      RAISE EXCEPTION 'Este parceiro não aparece na app (tem de estar "Parceiro", com "Mostrar na app" e dentro da validade).';
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM admin_notices
             WHERE title = v_title AND body = v_body AND created_at > now() - interval '24 hours') THEN
    RAISE EXCEPTION 'Este aviso já foi enviado nas últimas 24 horas.';
  END IF;

  SELECT count(*) INTO v_n
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area);
  IF v_n = 0 THEN
    RAISE EXCEPTION 'Ninguém corresponde a estes filtros.';
  END IF;
  IF p_expected IS DISTINCT FROM v_n THEN
    RAISE EXCEPTION 'O número de destinatários mudou (agora %). Conta outra vez antes de enviar.', v_n;
  END IF;

  v_audience := jsonb_strip_nulls(jsonb_build_object(
    'role', p_role, 'tiers', to_jsonb(NULLIF(p_tiers, '{}')),
    'service_type_id', p_service_type_id, 'area', NULLIF(btrim(COALESCE(p_area, '')), '')));
  INSERT INTO admin_notices (title, body, audience, recipients, created_by, partner_id)
  VALUES (v_title, v_body, v_audience, v_n, auth.uid(), p_partner_id)
  RETURNING id INTO v_id;

  -- Com parceiro, relatedId é o parceiro (a app abre-o); sem parceiro, é o
  -- envio, como na 0081.
  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT r.user_id,
         CASE WHEN p_partner_id IS NULL THEN 'admin_notice' ELSE 'partner_new' END,
         v_title, v_body,
         COALESCE(p_partner_id, v_id),
         CASE WHEN p_partner_id IS NULL THEN 'admin_notice' ELSE 'partner' END
  FROM public.admin_notice_recipients(p_role, p_tiers, p_service_type_id, p_area) r;

  PERFORM public.admin_log('send_notice', v_id, v_audience || jsonb_strip_nulls(jsonb_build_object(
    'title', v_title, 'recipients', v_n, 'partner', v_partner)));
  RETURN v_n;
END;
$function$;

-- accept_reschedule (antes em 0069_multi_day_and_started_job_rules.sql)
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
  -- 0069: trabalho já iniciado, ou data proposta que entretanto passou.
  IF v_job.started_at IS NOT NULL THEN
    RAISE EXCEPTION 'O trabalho já começou e já não pode ser cancelado nem remarcado.';
  END IF;
  IF v_job.reschedule_proposed_date < today_pt() THEN
    RAISE EXCEPTION 'A data proposta já passou. Recuse esta remarcação e proponha outra.';
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
        overdue_notified_at      = null,
        updated_at               = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_accepted', 'Remarcação aceite',
    'A nova data foi aceite.', p_job_id, 'job_request');
END;
$function$;


-- start_work_day (antes em 0058_proposal_pricing_and_work_days.sql)
CREATE OR REPLACE FUNCTION public.start_work_day(p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_next integer;
BEGIN
  PERFORM lock_started_job_for_worker(p_job_id);

  IF EXISTS (
    SELECT 1 FROM job_work_days WHERE job_id = p_job_id AND ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Termine primeiro o dia em curso.';
  END IF;

  SELECT COALESCE(max(day_number), 0) + 1 INTO v_next
  FROM   job_work_days WHERE job_id = p_job_id;

  INSERT INTO job_work_days (job_id, day_number, started_at)
  VALUES (p_job_id, v_next, now());
END;
$function$;


-- split_calendar_series (antes em 0064_worker_agenda.sql)
CREATE OR REPLACE FUNCTION public.split_calendar_series(p_entry_id uuid, p_from_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_entry worker_calendar_entries%ROWTYPE;
  v_new   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry
  FROM   worker_calendar_entries
  WHERE  id = p_entry_id AND worker_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrada não encontrada' USING ERRCODE = 'P0002';
  END IF;
  IF v_entry.recurrence = 'none' THEN
    RAISE EXCEPTION 'Esta entrada não se repete' USING ERRCODE = '22023';
  END IF;
  IF p_from_date <= v_entry.starts_on THEN
    RAISE EXCEPTION 'Para mudar a série toda, edite a entrada' USING ERRCODE = '22023';
  END IF;
  IF v_entry.recurrence_until IS NOT NULL AND p_from_date > v_entry.recurrence_until THEN
    RAISE EXCEPTION 'A série já acabou nesse dia' USING ERRCODE = '22023';
  END IF;

  INSERT INTO worker_calendar_entries (
    worker_id, kind, title, service_type_id, person_name, person_phone,
    location_label, location_lat, location_lng, starts_on, start_time,
    duration_minutes, ends_on, recurrence, recurrence_until, amount, notes, status
  ) VALUES (
    v_uid, v_entry.kind, v_entry.title, v_entry.service_type_id,
    v_entry.person_name, v_entry.person_phone, v_entry.location_label,
    v_entry.location_lat, v_entry.location_lng, p_from_date, v_entry.start_time,
    v_entry.duration_minutes,
    CASE WHEN v_entry.ends_on IS NULL THEN NULL
         ELSE p_from_date + (v_entry.ends_on - v_entry.starts_on) END,
    v_entry.recurrence, v_entry.recurrence_until, v_entry.amount, v_entry.notes,
    v_entry.status
  )
  RETURNING id INTO v_new;

  UPDATE worker_calendar_entries
  SET    recurrence_until = p_from_date - 1
  WHERE  id = p_entry_id;

  UPDATE worker_calendar_exceptions
  SET    entry_id = v_new
  WHERE  entry_id = p_entry_id AND occurrence_date >= p_from_date;

  RETURN v_new;
END;
$function$;


-- block_past_proposal_date (antes em 0068_flow_review_fixes.sql)
CREATE OR REPLACE FUNCTION public.block_past_proposal_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.scheduled_date IS NOT NULL AND NEW.scheduled_date < today_pt() THEN
    RAISE EXCEPTION 'O dia proposto já passou. Escolha hoje ou um dia a seguir.';
  END IF;
  RETURN NEW;
END;
$function$;


-- notify_job_report (antes em 0071_day_jobs_reports_and_agenda.sql)
CREATE OR REPLACE FUNCTION public.notify_job_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_worker_id uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = NEW.job_id;
  IF NOT FOUND OR v_job.status <> 'awaiting_confirmation'
     OR NEW.reporter_id <> v_job.client_id THEN
    RETURN NEW;
  END IF;

  SELECT worker_id INTO v_worker_id
  FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

  IF v_worker_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_worker_id, 'job_reminder', 'O cliente reportou um problema',
      'Fale com o cliente por WhatsApp para resolver. Se não confirmar antes, o trabalho fica confirmado a '
        || to_char((COALESCE(v_job.marked_done_at, now()) + interval '7 days')
                   AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '.',
      v_job.id, 'job_request');
  END IF;
  RETURN NEW;
END;
$function$;


-- job_request_track_visibility (antes em 0075_web_test_fixes.sql)
CREATE OR REPLACE FUNCTION public.job_request_track_visibility()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- 0074: um pedido criado pela app nasce sem nada da execução nem dos
    -- lembretes, e com data fixa nunca no passado. As funções do servidor
    -- (cancel_job ao reabrir) correm como dono e não passam por aqui.
    IF current_user IN ('authenticated', 'anon') THEN
      IF NEW.date_mode = 'fixed' AND NEW.preferred_date < today_pt() THEN
        RAISE EXCEPTION 'A data do pedido já passou. Escolha outra data.';
      END IF;
      -- 0075 (W-2): sem morada o pedido não se pode editar depois
      -- (update_job_request exige-a) e o jardineiro não sabe a zona.
      IF btrim(COALESCE(NEW.address_text, '')) = '' THEN
        RAISE EXCEPTION 'Indique a morada.';
      END IF;
      NEW.started_at                    := NULL;
      NEW.marked_done_at                := NULL;
      NEW.completion_photo_path         := NULL;
      NEW.before_photo_paths            := '{}';
      NEW.after_photo_paths             := '{}';
      NEW.day_reminder_sent_on          := NULL;
      NEW.overdue_notified_at           := NULL;
      NEW.confirmation_reminder_sent_at := NULL;
      NEW.start_reminder_for            := NULL;
      NEW.late_start_reminder_for       := NULL;
      NEW.undated_expiry_warned_at      := NULL;
    END IF;
    NEW.search_extra_km        := 0;
    NEW.followup_stage         := 0;
    NEW.no_proposals_nudged_at := NULL;
    NEW.visible_to_all_at :=
      CASE WHEN COALESCE(NEW.direct_status, '') IN ('waiting', 'on_hold')
           THEN NULL ELSE now() END;
    RETURN NEW;
  END IF;

  -- A app (cliente com sessão) não mexe nestes campos: só as RPCs e o cron.
  IF current_setting('request.jwt.claim.sub', true) IS NOT NULL
     AND current_user IN ('authenticated', 'anon')
     AND (NEW.search_extra_km        IS DISTINCT FROM OLD.search_extra_km
       OR NEW.followup_stage         IS DISTINCT FROM OLD.followup_stage
       OR NEW.no_proposals_nudged_at IS DISTINCT FROM OLD.no_proposals_nudged_at
       OR NEW.visible_to_all_at      IS DISTINCT FROM OLD.visible_to_all_at)
  THEN
    RAISE EXCEPTION 'Estes dados do pedido não se podem alterar.';
  END IF;

  -- Fim da reserva do pedido direto: o relógio dos lembretes começa agora.
  IF COALESCE(OLD.direct_status, '') IN ('waiting', 'on_hold')
     AND COALESCE(NEW.direct_status, '') NOT IN ('waiting', 'on_hold')
  THEN
    NEW.visible_to_all_at := now();
  END IF;
  RETURN NEW;
END;
$function$;


-- admin_search (antes em 0078_admin_support_tracking.sql)
CREATE OR REPLACE FUNCTION public.admin_search(p_q text)
 RETURNS TABLE(kind text, target_id uuid, title text, subtitle text, status text, matched text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_q      text := btrim(COALESCE(p_q, ''));
  v_lower  text := lower(btrim(COALESCE(p_q, '')));
  v_digits text := regexp_replace(COALESCE(p_q, ''), '\D', '', 'g');
  v_hex    text := lower(regexp_replace(btrim(COALESCE(p_q, '')), '^#', ''));
  v_is_hex boolean;
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(v_q) < 2 THEN
    RETURN;
  END IF;
  v_is_hex := v_hex ~ '^[0-9a-f-]{6,36}$';

  PERFORM public.admin_log('search', NULL, jsonb_build_object('q', left(v_q, 120)));

  RETURN QUERY
  WITH people AS (
    SELECT p.id, p.role, p.full_name, p.deleted_at, u.email,
           CASE
             WHEN v_is_hex AND p.id::text LIKE v_hex || '%' THEN 'id'
             WHEN u.email IS NOT NULL AND lower(u.email) = v_lower THEN 'email'
             WHEN v_lower LIKE '%@%' AND lower(COALESCE(u.email, '')) LIKE '%' || v_lower || '%' THEN 'email'
             WHEN length(v_digits) >= 6
                  AND regexp_replace(COALESCE(p.phone, ''), '\D', '', 'g') LIKE '%' || v_digits || '%' THEN 'phone'
             WHEN p.full_name ILIKE '%' || v_q || '%' THEN 'name'
             WHEN v_lower NOT LIKE '%@%' AND length(v_q) >= 3
                  AND lower(COALESCE(u.email, '')) LIKE v_lower || '%' THEN 'email'
           END AS matched
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.role IN ('client', 'worker')
  ), jobs AS (
    SELECT jr.id, jr.status, jr.created_at, jr.location_area,
           st.name AS service_name, c.full_name AS client_name
    FROM job_requests jr
    LEFT JOIN service_types st ON st.id = jr.service_type_id
    LEFT JOIN profiles c ON c.id = jr.client_id
    WHERE v_is_hex AND jr.id::text LIKE v_hex || '%'
  )
  SELECT * FROM (
    SELECT 'job'::text AS r_kind, j.id AS r_id,
           COALESCE(j.service_name, 'Pedido') AS r_title,
           concat_ws(' · ', '#' || left(j.id::text, 8), j.client_name, j.location_area,
                     to_char(j.created_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY')) AS r_subtitle,
           j.status AS r_status, 'id'::text AS r_matched
    FROM jobs j
    UNION ALL
    SELECT pe.role, pe.id,
           COALESCE(NULLIF(btrim(pe.full_name), ''), 'Sem nome'),
           concat_ws(' · ', CASE pe.role WHEN 'client' THEN 'Cliente' ELSE 'Profissional' END,
                     pe.email, CASE WHEN pe.deleted_at IS NOT NULL THEN 'conta eliminada' END),
           CASE WHEN pe.deleted_at IS NOT NULL THEN 'deleted' ELSE 'active' END,
           pe.matched
    FROM people pe
    WHERE pe.matched IS NOT NULL
  ) r
  ORDER BY CASE r.r_matched WHEN 'id' THEN 0 WHEN 'email' THEN 1 WHEN 'phone' THEN 2 ELSE 3 END
  LIMIT 20;
END;
$function$;


-- admin_map_points (antes em 0080_admin_accounts.sql)
CREATE OR REPLACE FUNCTION public.admin_map_points(p_days integer DEFAULT 30)
 RETURNS TABLE(kind text, id uuid, lat double precision, lng double precision, radius_km integer, label text, status text, service text, plan text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  PERFORM public.admin_log('view_map', NULL, jsonb_build_object('days', p_days));

  RETURN QUERY
  SELECT 'job'::text, jr.id, jr.location_lat::double precision, jr.location_lng::double precision,
         NULL::integer, COALESCE(jr.location_area, 'Pedido'), jr.status, st.name, NULL::text,
         jr.created_at
  FROM job_requests jr
  LEFT JOIN service_types st ON st.id = jr.service_type_id
  WHERE jr.location_lat IS NOT NULL AND jr.location_lng IS NOT NULL
    AND (jr.status IN ('open', 'confirmed', 'awaiting_confirmation')
         OR (jr.status = 'completed'
             AND jr.updated_at >= now() - make_interval(days => LEAST(GREATEST(COALESCE(p_days, 30), 1), 365))))
  UNION ALL
  SELECT 'worker'::text, wp.profile_id, wp.base_lat::double precision, wp.base_lng::double precision,
         LEAST(GREATEST(wp.radius_km, 1), 50), COALESCE(p.full_name, 'Profissional'),
         CASE WHEN s.suspended_at IS NOT NULL THEN 'suspended' ELSE 'active' END,
         NULL::text, COALESCE(pl.tier, 'free'), p.created_at
  FROM worker_profiles wp
  JOIN profiles p ON p.id = wp.profile_id AND p.deleted_at IS NULL
  LEFT JOIN worker_plans pl ON pl.worker_id = wp.profile_id
  LEFT JOIN account_status s ON s.profile_id = wp.profile_id
  WHERE NOT (wp.base_lat = 0 AND wp.base_lng = 0);
END;
$function$;


-- admin_list_fleet_cards (antes em 0082_admin_partners_zones.sql)
CREATE OR REPLACE FUNCTION public.admin_list_fleet_cards(p_status text DEFAULT 'pending'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, worker_id uuid, worker_name text, location_name text, plan text, worker_suspended boolean, card_number text, holder_name text, barcode_value text, status text, created_at timestamp with time zone, reviewed_at timestamp with time zone, review_message text, attempts integer, is_latest boolean, total_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  IF p_status IS NOT NULL AND p_status NOT IN ('pending', 'active', 'rejected') THEN
    RAISE EXCEPTION 'Estado de cartão desconhecido.';
  END IF;
  PERFORM public.admin_log('view_fleet_cards', NULL,
    jsonb_build_object('status', p_status));

  RETURN QUERY
  WITH c AS (
    SELECT fc.*,
           count(*) OVER (PARTITION BY fc.worker_id)::integer AS n_attempts,
           row_number() OVER (PARTITION BY fc.worker_id
                              ORDER BY fc.created_at DESC, fc.id DESC) = 1 AS latest
    FROM worker_fleet_cards fc
  )
  SELECT c.id, c.worker_id, COALESCE(p.full_name, 'Profissional'), wp.location_name,
         COALESCE(pl.tier, 'free'), (s.suspended_at IS NOT NULL),
         c.card_number, c.holder_name, c.barcode_value, c.status, c.created_at,
         c.reviewed_at, c.review_message, c.n_attempts, c.latest,
         count(*) OVER ()
  FROM c
  JOIN profiles p ON p.id = c.worker_id AND p.deleted_at IS NULL
  LEFT JOIN worker_profiles wp ON wp.profile_id = c.worker_id
  LEFT JOIN worker_plans pl ON pl.worker_id = c.worker_id
  LEFT JOIN account_status s ON s.profile_id = c.worker_id
  WHERE (p_status IS NULL OR c.status = p_status)
  ORDER BY c.latest DESC,
           CASE WHEN c.status = 'pending' THEN c.created_at END ASC,
           c.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
