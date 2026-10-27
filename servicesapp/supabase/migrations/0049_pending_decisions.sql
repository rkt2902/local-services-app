-- ══════════════════════════════════════════════════════════════
-- 0049 — Decisões pendentes: conta, edição de pedido, equipa e avisos
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0048
-- (redefine notify_proposal_closed_with_job, que nasce na 0048, e conta
-- com o trigger trg_notify_proposal_closed_with_job da 0048 para avisar
-- os jardineiros das propostas rejeitadas aqui).
-- Pode correr-se mais do que uma vez sem erro.
--
-- Secções:
--   1. delete_my_account(): elimina a conta do próprio. Recusa se houver
--      trabalho em curso; fecha pedidos, propostas e candidaturas abertas;
--      anonimiza o perfil (não apaga, para não partir o histórico dos
--      outros: avaliações, reports, cancelamentos) e bloqueia o login.
--      Coluna nova profiles.deleted_at; worker_public_card esconde contas
--      eliminadas.
--   2. update_job_request(...): o cliente edita o pedido enquanto está
--      aberto; quem já propôs é avisado (tipo job_updated).
--   3. Gestão da equipa pelo jardineiro responsável:
--      cancel_help_request, remove_help_helper, update_help_request_slots.
--   4. get_my_help_acceptances ganha payment_per_helper (no fim).
--   5. Notificações dizem de que trabalho são: trigger BEFORE INSERT que
--      acrescenta " (Serviço, DD/MM)" ao corpo. Notificações para contas
--      eliminadas deixam de ser gravadas.
--   6. Ajudantes aceites passam a ser avisados quando a data muda, quando
--      o trabalho é marcado como concluído e quando é confirmado; e
--      recebem o lembrete da manhã do dia (send_job_reminders).
--   7. propose_reschedule: com o trabalho atrasado (data já passou e
--      ainda confirmado) volta a ser possível propor nova data.
--      accept_reschedule limpa o aviso de atraso para a nova data.
--   8. auto_expire_jobs 5.4: pedido sem data fixa, com propostas, aberto
--      há mais de 14 dias sem escolha: fecha (no_response).
--   9. auto_confirm_completed_jobs: um problema reportado depois de o
--      trabalho ser marcado como concluído suspende a confirmação
--      automática.
--  10. submit_client_rating deixa de copiar a nota para os ajudantes.
--  11. notify_proposal_closed_with_job: texto de no_response genérico
--      (serve a data passada e os 14 dias da secção 8).
--
-- O que a app precisa desta migration:
--   - RPCs novas: delete_my_account(), update_job_request(...),
--     cancel_help_request(uuid), remove_help_helper(uuid),
--     update_help_request_slots(uuid, integer).
--   - get_my_help_acceptances devolve payment_per_helper.
--   - Tipos de notificação novos: job_updated, help_removed,
--     help_job_rescheduled, help_job_done, help_job_completed
--     (help_rejected, job_reminder e job_no_response já existiam).
--   - Depois de delete_my_account a app deve fazer signOut local: a
--     sessão é apagada no servidor e o login fica bloqueado.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- 1. delete_my_account
-- ══════════════════════════════════════════════════════════════

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- Mesmas colunas da 0033, só deixa de mostrar contas eliminadas.
CREATE OR REPLACE VIEW public.worker_public_card AS
SELECT
  wp.profile_id AS worker_id,
  p.full_name,
  p.avatar_url,
  wp.bio,
  wp.location_name,
  COALESCE(
    array_agg(DISTINCT st.name) FILTER (WHERE st.name IS NOT NULL),
    ARRAY[]::text[]
  ) AS service_names,
  COALESCE(AVG(r.stars), 0)::numeric(3, 2) AS avg_rating,
  COUNT(DISTINCT r.id) AS rating_count
FROM worker_profiles wp
JOIN profiles p ON p.id = wp.profile_id
LEFT JOIN worker_service_types wst ON wst.worker_id = wp.profile_id
LEFT JOIN service_types st ON st.id = wst.service_type_id
LEFT JOIN ratings r ON r.ratee_id = wp.profile_id
WHERE p.deleted_at IS NULL
GROUP BY wp.profile_id, p.full_name, p.avatar_url, wp.bio, wp.location_name;

GRANT SELECT ON public.worker_public_card TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_email text;
  v_pwd   text;
  r       record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  PERFORM 1 FROM profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Esta conta já foi eliminada.';
  END IF;

  -- ── Trabalho em curso: recusa ──────────────────────────────────
  IF EXISTS (
       SELECT 1 FROM job_requests
       WHERE  client_id = v_uid
         AND  status IN ('confirmed', 'awaiting_confirmation')
     )
     OR EXISTS (
       SELECT 1
       FROM   job_proposals jp
       JOIN   job_requests  jr ON jr.id = jp.job_id
       WHERE  jp.worker_id = v_uid
         AND  jp.status    = 'accepted'
         AND  jr.status IN ('confirmed', 'awaiting_confirmation')
     )
     OR EXISTS (
       SELECT 1
       FROM   help_acceptances ha
       JOIN   help_requests    hr ON hr.id = ha.help_request_id
       JOIN   job_requests     jr ON jr.id = hr.job_id
       WHERE  ha.worker_id = v_uid
         AND  ha.status    = 'accepted'
         AND  jr.status    = 'confirmed'
     )
  THEN
    RAISE EXCEPTION 'Tens trabalhos em curso. Conclui-os ou cancela-os antes de eliminar a conta.';
  END IF;

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
        'Um jardineiro retirou a proposta que te tinha feito.',
        r.job_id, 'job_request');
    END IF;
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
           'O jardineiro responsável fechou o pedido de ajuda.',
           r.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = r.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = r.id AND status = 'pending';

    UPDATE help_requests SET status = 'cancelled' WHERE id = r.id;
  END LOOP;

  -- ── Anonimização (sem DELETE: há FKs sem cascade para profiles) ─
  UPDATE profiles
  SET    full_name  = 'Conta eliminada',
         phone      = NULL,
         avatar_url = NULL,
         deleted_at = now(),
         updated_at = now()
  WHERE  id = v_uid;

  -- base_lat/base_lng são NOT NULL e são a morada de casa: vão para 0,0,
  -- o que também tira o perfil de qualquer raio em Portugal.
  UPDATE worker_profiles
  SET    bio                 = NULL,
         default_hourly_rate = NULL,
         location_name       = NULL,
         base_lat            = 0,
         base_lng            = 0,
         tools               = '{}',
         photos              = '{}',
         updated_at          = now()
  WHERE  profile_id = v_uid;

  DELETE FROM worker_service_types WHERE worker_id = v_uid;
  DELETE FROM device_tokens        WHERE user_id   = v_uid;
  DELETE FROM worker_fleet_cards   WHERE worker_id = v_uid;
  DELETE FROM notifications        WHERE user_id   = v_uid;

  -- ── auth: email e telefone fora, sem login possível ────────────
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

REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_my_account() TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 2. update_job_request
-- ══════════════════════════════════════════════════════════════
-- Mesmas regras da criação (ecrãs do assistente + CHECK de date_mode):
-- descrição 10 a 500 caracteres, data fixa obrigatória e não passada,
-- morada e coordenadas obrigatórias. preferred_date só fica guardada no
-- modo 'fixed', como na criação.

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
    RAISE EXCEPTION 'Só podes alterar um pedido enquanto está aberto.';
  END IF;

  IF length(v_description) < 10 OR length(v_description) > 500 THEN
    RAISE EXCEPTION 'A descrição tem de ter entre 10 e 500 caracteres.';
  END IF;
  IF p_date_mode IS NULL OR p_date_mode NOT IN ('fixed', 'flexible', 'availability') THEN
    RAISE EXCEPTION 'Modo de data inválido.';
  END IF;
  IF p_date_mode = 'fixed'
     AND (p_preferred_date IS NULL OR p_preferred_date < today_pt()) THEN
    RAISE EXCEPTION 'Escolhe uma data a partir de hoje.';
  END IF;
  IF p_date_mode = 'availability' AND v_availability IS NULL THEN
    RAISE EXCEPTION 'Indica a tua disponibilidade.';
  END IF;
  IF v_address = '' THEN
    RAISE EXCEPTION 'Indica a morada.';
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
         'O cliente alterou o pedido a que fizeste uma proposta. Vê se a tua proposta ainda serve.',
         p_job_id, 'job_request'
  FROM   job_proposals jp
  WHERE  jp.job_id = p_job_id AND jp.status = 'pending';
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_job_request(uuid, text, text, date, text, text, double precision, double precision, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.update_job_request(uuid, text, text, date, text, text, double precision, double precision, text) TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 3. Equipa: só o jardineiro responsável (auth.uid() = worker da
--    proposta do pedido de ajuda) e só com o trabalho confirmado.
-- ══════════════════════════════════════════════════════════════

-- ── 3a. cancel_help_request ─────────────────────────────────────

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
    RAISE EXCEPTION 'Só o jardineiro responsável pode gerir a equipa.';
  END IF;
  IF v_hr_status NOT IN ('pending_approval', 'open', 'filled') THEN
    RAISE EXCEPTION 'Este pedido de ajuda já está fechado.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só podes mudar a equipa com o trabalho por fazer.';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
         'O jardineiro responsável fechou o pedido de ajuda.',
         p_help_request_id, 'help_request'
  FROM   help_acceptances ha
  WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'pending';

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  SELECT ha.worker_id, 'help_removed', 'Já não fazes parte da equipa',
         'O jardineiro responsável fechou a equipa e já não precisa da tua ajuda neste trabalho.',
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

REVOKE EXECUTE ON FUNCTION public.cancel_help_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancel_help_request(uuid) TO authenticated, service_role;


-- ── 3b. remove_help_helper ──────────────────────────────────────

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
  v_job_status      text;
BEGIN
  SELECT jp.worker_id, ha.worker_id, ha.help_request_id, ha.status, hr.status, jr.status
  INTO   v_principal, v_helper, v_help_request_id, v_ha_status, v_hr_status, v_job_status
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
    RAISE EXCEPTION 'Só o jardineiro responsável pode gerir a equipa.';
  END IF;
  IF v_ha_status <> 'accepted' THEN
    RAISE EXCEPTION 'Este ajudante já não está na equipa.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só podes mudar a equipa com o trabalho por fazer.';
  END IF;

  UPDATE help_acceptances SET status = 'cancelled' WHERE id = p_help_acceptance_id;

  -- Vaga volta a abrir; quem tinha sido recusado fica a saber (como em
  -- withdraw_help_acceptance).
  IF v_hr_status = 'filled' THEN
    UPDATE help_requests SET status = 'open' WHERE id = v_help_request_id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_request_reopened', 'Vaga disponível novamente',
           'Uma vaga de ajudante a que te candidataste voltou a abrir. Podes candidatar-te outra vez.',
           v_help_request_id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_help_request_id AND ha.status = 'rejected';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_helper, 'help_removed', 'Já não fazes parte da equipa',
    'O jardineiro responsável tirou-te da equipa deste trabalho.',
    v_help_request_id, 'help_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.remove_help_helper(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.remove_help_helper(uuid) TO authenticated, service_role;


-- ── 3c. update_help_request_slots ───────────────────────────────

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
    RAISE EXCEPTION 'Só o jardineiro responsável pode gerir a equipa.';
  END IF;
  IF v_hr_status NOT IN ('pending_approval', 'open', 'filled') THEN
    RAISE EXCEPTION 'Este pedido de ajuda já está fechado.';
  END IF;
  IF v_job_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só podes mudar a equipa com o trabalho por fazer.';
  END IF;

  SELECT COUNT(*)::integer INTO v_accepted
  FROM   help_acceptances
  WHERE  help_request_id = p_help_request_id AND status = 'accepted';

  IF p_slots < v_accepted THEN
    RAISE EXCEPTION 'Já tens % ajudantes aceites. Tira alguém da equipa antes de reduzir as vagas.', v_accepted;
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
             'Uma vaga de ajudante a que te candidataste voltou a abrir. Podes candidatar-te outra vez.',
             p_help_request_id, 'help_request'
      FROM   help_acceptances ha
      WHERE  ha.help_request_id = p_help_request_id AND ha.status = 'rejected';
    END IF;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_help_request_slots(uuid, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.update_help_request_slots(uuid, integer) TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 4. get_my_help_acceptances + payment_per_helper
-- ══════════════════════════════════════════════════════════════
-- Igual à 0043, com a coluna nova no fim (mesma fórmula de
-- get_help_requests_in_radius). RETURNS TABLE muda: DROP explícito.

DROP FUNCTION IF EXISTS public.get_my_help_acceptances();

CREATE FUNCTION public.get_my_help_acceptances()
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
  principal_worker_id uuid,
  confirmed_date      date,
  confirmed_time      time,
  address_text        text,
  location_lat        numeric,
  location_lng        numeric,
  principal_phone     text,
  payment_per_helper  numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.status, ha.agreed_rate, ha.brought_equipment, ha.created_at,
    st.name         AS service_type_name,
    p.full_name     AS principal_name,
    jr.status       AS job_status,
    jr.id           AS job_id,
    jp.worker_id    AS principal_worker_id,
    jr.confirmed_date, jr.confirmed_time,
    CASE WHEN ha.status = 'accepted' THEN jr.address_text
         ELSE job_area_label(jr.location_area) END,
    CASE WHEN ha.status = 'accepted' THEN jr.location_lat
         ELSE round(jr.location_lat, 2) END,
    CASE WHEN ha.status = 'accepted' THEN jr.location_lng
         ELSE round(jr.location_lng, 2) END,
    CASE WHEN ha.status = 'accepted' THEN p.phone ELSE NULL END AS principal_phone,
    CASE WHEN hr.equipment_required THEN jp.hourly_rate
         ELSE jp.hourly_rate * 0.7
    END AS payment_per_helper
  FROM   help_acceptances ha
  JOIN   help_requests    hr ON hr.id  = ha.help_request_id
  JOIN   job_requests     jr ON jr.id  = hr.job_id
  JOIN   service_types    st ON st.id  = jr.service_type_id
  JOIN   job_proposals    jp ON jp.id  = hr.proposal_id
  JOIN   profiles          p ON p.id   = jp.worker_id
  WHERE  ha.worker_id = auth.uid()
  ORDER  BY ha.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_help_acceptances() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_help_acceptances() TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 5. Notificações com o trabalho a que se referem
-- ══════════════════════════════════════════════════════════════
-- BEFORE INSERT: acrescenta " (Serviço, DD/MM)" ao corpo quando a
-- notificação aponta para um job_request ou help_request. A data é a
-- confirmada ou, se não houver, a preferida; sem data fica só o serviço.
-- Nunca faz falhar o INSERT: qualquer erro na procura deixa a notificação
-- como veio. Também deixa de gravar notificações para contas eliminadas
-- (RETURN NULL salta a linha sem erro).

CREATE OR REPLACE FUNCTION public.notifications_add_job_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_id  uuid;
  v_service text;
  v_date    date;
  v_context text;
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

REVOKE EXECUTE ON FUNCTION public.notifications_add_job_context() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notifications_add_job_context ON public.notifications;
CREATE TRIGGER trg_notifications_add_job_context
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_add_job_context();


-- ══════════════════════════════════════════════════════════════
-- 6. Avisos aos ajudantes aceites
-- ══════════════════════════════════════════════════════════════

-- ── 6.1 Data mudou / marcado como concluído / confirmado ────────

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

  IF OLD.status = 'confirmed' AND NEW.status = 'confirmed'
     AND (OLD.confirmed_date IS DISTINCT FROM NEW.confirmed_date
          OR OLD.confirmed_time IS DISTINCT FROM NEW.confirmed_time) THEN
    v_type  := 'help_job_rescheduled';
    v_title := 'Data do trabalho mudou';
    v_body  := CASE
      WHEN NEW.confirmed_date IS NULL THEN
        'O trabalho em que vais ajudar mudou de data. Abre a app para ver a nova data.'
      WHEN NEW.confirmed_flexible OR NEW.confirmed_time IS NULL THEN
        'O trabalho em que vais ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM') || '.'
      ELSE
        'O trabalho em que vais ajudar passou para ' || to_char(NEW.confirmed_date, 'DD/MM')
          || ' às ' || to_char(NEW.confirmed_time, 'HH24:MI') || '.'
    END;
  ELSIF NEW.status = 'awaiting_confirmation' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_done';
    v_title := 'Trabalho marcado como concluído';
    v_body  := 'O jardineiro responsável marcou como concluído o trabalho em que ajudaste.';
  ELSIF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status THEN
    v_type  := 'help_job_completed';
    v_title := 'Trabalho concluído';
    v_body  := 'O trabalho em que ajudaste ficou confirmado. Já podes avaliar o jardineiro responsável.';
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

REVOKE EXECUTE ON FUNCTION public.notify_helpers_on_job_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_helpers_on_job_change ON job_requests;
CREATE TRIGGER trg_notify_helpers_on_job_change
  AFTER UPDATE OF status, confirmed_date, confirmed_time ON job_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_helpers_on_job_change();


-- ── 6.2 send_job_reminders: lembrete da manhã também aos ajudantes ─
-- Igual à 0046; só o passo 7.1 ganha o INSERT para os ajudantes aceites.

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
      'Lembrete: o jardineiro vem ' || v_when || '.',
      v_job.id, 'job_request');

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Tens um trabalho hoje',
        'Lembrete: trabalho marcado para ' || v_when || '. Abre a app para ver a morada.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT DISTINCT ha.worker_id, 'job_reminder', 'Vais ajudar num trabalho hoje',
           'Lembrete: trabalho marcado para ' || v_when || '. Abre a app para ver a morada.',
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
      AND  confirmed_date IS NOT NULL
      AND  confirmed_date < v_today
      AND  overdue_notified_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    SELECT worker_id INTO v_worker_id
    FROM   job_proposals WHERE id = v_job.accepted_proposal_id;

    IF v_worker_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_worker_id, 'job_reminder', 'Marca o trabalho como concluído',
        'A data do trabalho já passou. Se já o fizeste, marca-o como concluído. Sem isso, o pedido expira 3 dias depois da data.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'O trabalho foi feito?',
      'A data do trabalho já passou e o jardineiro ainda não o marcou como concluído. Fala com ele pelo WhatsApp ou remarca. O pedido expira 3 dias depois da data.',
      v_job.id, 'job_request');

    UPDATE job_requests SET overdue_notified_at = now() WHERE id = v_job.id;
  END LOOP;

  -- 7.3 Marcado como concluído há mais de 1 dia e o cliente não confirmou.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status = 'awaiting_confirmation'
      AND  COALESCE(marked_done_at, updated_at) < now() - INTERVAL '1 day'
      AND  confirmation_reminder_sent_at IS NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_reminder', 'Confirma o trabalho',
      'O jardineiro marcou o trabalho como concluído. Confirma ou reporta um problema. Sem resposta, fica confirmado automaticamente 3 dias depois.',
      v_job.id, 'job_request');

    UPDATE job_requests SET confirmation_reminder_sent_at = now() WHERE id = v_job.id;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_job_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_job_reminders() TO service_role;


-- ══════════════════════════════════════════════════════════════
-- 7. Remarcar um trabalho atrasado
-- ══════════════════════════════════════════════════════════════
-- propose_reschedule (0042): mesma assinatura. Continua recusado no
-- próprio dia (mesma mensagem, que a app já traduz para "até à
-- véspera"); com data futura continua possível até à véspera; com a data
-- já passada (trabalho atrasado, ainda confirmado) passa a ser possível.
-- A nova data tem de ser pelo menos amanhã. "Hoje" passa a ser today_pt().

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
  v_today         date := today_pt();
  v_job           public.job_requests;
  v_is_client     boolean;
  v_is_worker     boolean;
  v_other_user_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.job_requests WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.status != 'confirmed' THEN
    RAISE EXCEPTION 'Só jobs confirmados podem ser remarcados';
  END IF;
  IF v_job.confirmed_date IS NOT NULL AND v_job.confirmed_date = v_today THEN
    RAISE EXCEPTION 'Não pode remarcar com menos de 24h de antecedência';
  END IF;
  IF p_new_date IS NULL OR p_new_date - v_today < 1 THEN
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

REVOKE EXECUTE ON FUNCTION public.propose_reschedule(uuid, date, time, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.propose_reschedule(uuid, date, time, boolean) TO authenticated, service_role;

-- accept_reschedule (0042): não bloqueava trabalhos atrasados. Igual,
-- mais o reset de overdue_notified_at, para o aviso de atraso (7.2 de
-- send_job_reminders) voltar a valer para a nova data.

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
        overdue_notified_at      = null,
        updated_at               = now()
    WHERE id = p_job_id;

  INSERT INTO public.notifications (user_id, type, title, body, related_id, related_type)
  VALUES (v_proposer_id, 'reschedule_accepted', 'Remarcação aceite',
    'A nova data foi aceite.', p_job_id, 'job_request');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.accept_reschedule(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.accept_reschedule(uuid) TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 8. auto_expire_jobs: 5.4 propostas sem escolha há 14 dias
-- ══════════════════════════════════════════════════════════════
-- 5.1 a 5.3 iguais à 0046.

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
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE job_requests
    SET    status = 'no_response', updated_at = now()
    WHERE  id = v_job.id;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_no_response', 'Sem resposta',
      'O teu pedido não recebeu propostas em 48h.',
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
      'A data do teu pedido passou sem nenhuma proposta aceite. Podes criar um novo pedido.',
      v_job.id, 'job_request');
  END LOOP;

  -- 5.3 Trabalho confirmado, 3 dias depois da data, sem ninguém marcar
  -- como concluído: expira.
  FOR v_job IN
    SELECT * FROM job_requests
    WHERE  status         = 'confirmed'
      AND  confirmed_date IS NOT NULL
      AND  confirmed_date < today_pt() - 3
      -- Remarcação pendente: dá tempo à outra parte para responder.
      AND  reschedule_status IS DISTINCT FROM 'pending'
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
        'Passaram 3 dias da data combinada sem marcares o trabalho como concluído. O pedido foi fechado.',
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
      'O teu pedido esteve 14 dias sem escolheres uma proposta e foi fechado. Podes publicá-lo de novo.',
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.auto_expire_jobs() FROM PUBLIC, anon, authenticated;


-- ══════════════════════════════════════════════════════════════
-- 9. auto_confirm_completed_jobs: problema reportado suspende
-- ══════════════════════════════════════════════════════════════
-- Igual à 0046, mais o NOT EXISTS: um job_reports criado depois de o
-- trabalho ser marcado como concluído deixa o pedido à espera do cliente
-- (que continua a poder confirmar à mão).

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

  FOR v_job IN
    SELECT * FROM job_requests jr
    WHERE  jr.status = 'awaiting_confirmation'
      AND  COALESCE(jr.marked_done_at, jr.updated_at) < now() - INTERVAL '3 days'
      AND  NOT EXISTS (
        SELECT 1 FROM job_reports rp
        WHERE  rp.job_id     = jr.id
          AND  rp.created_at >= COALESCE(jr.marked_done_at, jr.updated_at)
      )
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
        'Passaram 3 dias sem confirmação. O trabalho foi confirmado automaticamente.',
        v_job.id, 'job_request');
    END IF;

    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    VALUES (v_job.client_id, 'job_completed', 'Trabalho confirmado automaticamente',
      'Passaram 3 dias sem resposta. O trabalho foi confirmado automaticamente.',
      v_job.id, 'job_request');
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.auto_confirm_completed_jobs() FROM PUBLIC, anon, authenticated;


-- ══════════════════════════════════════════════════════════════
-- 10. submit_client_rating: só avalia o jardineiro responsável
-- ══════════════════════════════════════════════════════════════
-- Igual ao baseline sem o ciclo que copiava a nota para cada ajudante.

CREATE OR REPLACE FUNCTION public.submit_client_rating(
  p_job_id  uuid,
  p_stars   integer,
  p_comment text DEFAULT NULL
)
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
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.submit_client_rating(uuid, integer, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_client_rating(uuid, integer, text) TO authenticated, service_role;


-- ══════════════════════════════════════════════════════════════
-- 11. notify_proposal_closed_with_job: no_response genérico
-- ══════════════════════════════════════════════════════════════
-- Igual à 0048; o texto de no_response deixa de falar da data, porque o
-- pedido também fecha pelos 14 dias da secção 8. O trigger da 0048 fica
-- como está (aponta para esta função).

CREATE OR REPLACE FUNCTION public.notify_proposal_closed_with_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job_status text;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
    SELECT status INTO v_job_status FROM job_requests WHERE id = NEW.job_id;

    IF v_job_status = 'cancelled' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido cancelado',
        'O cliente cancelou o pedido a que fizeste uma proposta.',
        NEW.job_id, 'job_request');
    ELSIF v_job_status = 'no_response' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (NEW.worker_id, 'proposal_rejected', 'Pedido fechado',
        'O pedido fechou sem o cliente escolher a tua proposta.',
        NEW.job_id, 'job_request');
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.notify_proposal_closed_with_job() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_proposal_closed_with_job ON job_proposals;
CREATE TRIGGER trg_notify_proposal_closed_with_job
  AFTER UPDATE OF status ON job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.notify_proposal_closed_with_job();


NOTIFY pgrst, 'reload schema';
