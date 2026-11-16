-- ══════════════════════════════════════════════════════════════
-- 0080 — Painel de admin para suporte, fase C (Contas)
-- ══════════════════════════════════════════════════════════════
--
-- NÃO APLICADA. Aplicar à mão no SQL Editor do Supabase, depois da 0079.
-- Pode correr-se mais do que uma vez sem erro.
--
-- O que faz:
--   1. Tabela account_status (suspensão e encerramento marcado), só do
--      servidor. Fora de profiles de propósito: quem tem um trabalho
--      confirmado lê o perfil da outra pessoa e não deve ver motivos.
--   2. Conta suspensa não age: trigger em pedidos, propostas, ajudas,
--      avaliações e fotos recusa escritas feitas por ela; ninguém lhe
--      faz pedidos diretos; não recebe pedidos novos da zona nem mostra
--      o cartão público. A app pergunta get_my_account_status() e mostra
--      "Conta suspensa".
--   3. admin_suspend_user / admin_reactivate_user. Ao suspender: pedidos
--      abertos da pessoa fecham (motivo account_suspended), propostas
--      pendentes dela são retiradas, reservas de pedido direto libertadas,
--      candidaturas a ajudante canceladas. Trabalhos já aceites ficam
--      (o suporte decide um a um na ficha do pedido).
--   4. admin_schedule_closure / admin_cancel_closure: aviso de
--      encerramento com 30 dias (P2B). Cron diário process_account_closures
--      suspende a conta na data.
--   5. admin_export_user_data: JSON com tudo o que se guarda da pessoa.
--   6. admin_erase_user: o mesmo que "Eliminar conta" na app
--      (account_delete_core, agora partilhado com delete_my_account).
--      Os ficheiros no Storage ficam; a RPC devolve as pastas a apagar.
--   7. admin_hide_profile_photo: foto de perfil ou do portefólio passa
--      para profile_photos_hidden (como as fotos dos pedidos na 0079).
--   8. admin_get_account, admin_resend_code (o envio é na app), admin_map_points.
--
-- Regras de sempre: cada admin_* chama assert_verified_admin(); a pessoa
-- alvo vem como p_target_id, quem chama é auth.uid(); toda a mudança fica
-- em admin_actions com motivo e nota.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Estado da conta ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.account_status (
  profile_id        uuid        PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  suspended_at      timestamptz,
  suspended_reason  text,
  suspended_message text,
  closing_at        timestamptz,
  closing_reason    text,
  closing_message   text,
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS account_status_closing_idx ON public.account_status (closing_at)
  WHERE closing_at IS NOT NULL AND suspended_at IS NULL;
ALTER TABLE public.account_status ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_status FROM anon, authenticated;

-- A própria pessoa: está suspensa? encerramento marcado? (ecrã "Conta
-- suspensa" e aviso na app). Sem motivo interno, só a mensagem.
CREATE OR REPLACE FUNCTION public.get_my_account_status()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE((
    SELECT jsonb_build_object(
      'suspended_at', s.suspended_at, 'suspended_message', s.suspended_message,
      'closing_at', s.closing_at, 'closing_message', s.closing_message)
    FROM account_status s WHERE s.profile_id = auth.uid()), '{}'::jsonb);
$function$;
REVOKE EXECUTE ON FUNCTION public.get_my_account_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_account_status() TO authenticated, service_role;


-- ── 2. Conta suspensa não age ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_account_suspended(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM account_status WHERE profile_id = p_uid AND suspended_at IS NOT NULL);
$function$;
REVOKE EXECUTE ON FUNCTION public.is_account_suspended(uuid) FROM PUBLIC, anon, authenticated;

-- Recusa a escrita quando quem a faz (auth.uid()) está suspenso. Os crons
-- (sem auth.uid()) e o admin passam. Em job_requests também recusa um
-- pedido direto a um jardineiro suspenso.
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
    RAISE EXCEPTION 'A tua conta está suspensa. Escreve para suporte@projardim.pt.';
  END IF;
  -- IFs separados: NEW.direct_* só existe em job_requests.
  IF TG_TABLE_NAME = 'job_requests' AND TG_OP = 'INSERT' THEN
    IF public.is_account_suspended(NEW.direct_worker_id)
       OR public.is_account_suspended(NEW.direct_card_worker_id) THEN
      RAISE EXCEPTION 'Este jardineiro não está disponível.';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.block_suspended_writes() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['job_requests', 'job_proposals', 'help_requests',
                           'help_acceptances', 'ratings', 'job_photos', 'job_work_days']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_block_suspended_writes ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_block_suspended_writes
                      BEFORE INSERT OR UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.block_suspended_writes()', t);
  END LOOP;
END $$;

-- Cartão público e pedidos novos da zona: sem contas suspensas.
-- (Iguais à 0074 e à 0070, mais "não suspenso".)
CREATE OR REPLACE FUNCTION public.worker_can_use_public_card(p_worker_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   worker_profiles wp
    JOIN   profiles p ON p.id = wp.profile_id
    WHERE  wp.profile_id = p_worker_id
      AND  p.deleted_at IS NULL
      AND  NOT EXISTS (SELECT 1 FROM account_status s
                       WHERE s.profile_id = p.id AND s.suspended_at IS NOT NULL)
  );
$function$;

CREATE OR REPLACE FUNCTION public.job_candidate_workers(p_job job_requests)
 RETURNS TABLE(worker_id uuid, distance_km double precision, radius_km integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT wp.profile_id,
         km_between(wp.base_lat, wp.base_lng, p_job.location_lat, p_job.location_lng),
         -- 0074: nunca mais de 50 km, como a pesquisa (o CHECK novo já o garante).
         LEAST(GREATEST(wp.radius_km, 1), 50)
  FROM   worker_profiles wp
  JOIN   profiles p ON p.id = wp.profile_id
                   AND p.deleted_at IS NULL
  WHERE  NOT EXISTS (SELECT 1 FROM account_status s
                     WHERE s.profile_id = wp.profile_id AND s.suspended_at IS NOT NULL)
    AND  wp.profile_id <> p_job.client_id
    AND  NOT (wp.profile_id = ANY(COALESCE(p_job.excluded_worker_ids, '{}'::uuid[])))
    AND  (
           EXISTS (SELECT 1 FROM worker_service_types wst
                   WHERE wst.worker_id = wp.profile_id
                     AND wst.service_type_id = p_job.service_type_id)
           OR NOT EXISTS (SELECT 1 FROM worker_service_types wst
                          WHERE wst.worker_id = wp.profile_id)
         )
    AND  NOT EXISTS (SELECT 1 FROM job_proposals jp
                     WHERE jp.job_id = p_job.id AND jp.worker_id = wp.profile_id);
$function$;

-- Aviso às propostas pendentes (0079), mais o pedido fechado por conta
-- suspensa.
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
             THEN 'O suporte da ProJardim cancelou o pedido a que fizeste uma proposta.'
             ELSE 'O cliente cancelou o pedido a que fizeste uma proposta.' END,
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


-- ── 3. Suspender e reativar ─────────────────────────────────────

-- Núcleo partilhado pelo admin e pelo cron do encerramento. Devolve
-- quantos trabalhos já aceites ficaram por decidir.
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
              'Um jardineiro deixou de estar disponível e a proposta saiu do teu pedido.',
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
          COALESCE(p_message, 'A tua conta ProJardim foi suspensa pelo suporte.')
          || ' Para contestar, responde para suporte@projardim.pt nos próximos 6 meses.');
  RETURN v_open;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.account_suspend_core(uuid, text, text) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.admin_suspend_user(uuid, text, text, text);
CREATE FUNCTION public.admin_suspend_user(
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
    RAISE EXCEPTION 'Não podes suspender a tua própria conta.';
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
REVOKE EXECUTE ON FUNCTION public.admin_suspend_user(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suspend_user(uuid, text, text, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_reactivate_user(uuid, text);
CREATE FUNCTION public.admin_reactivate_user(p_target_id uuid, p_note text)
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
    RAISE EXCEPTION 'Escreve uma nota com o motivo (5 carateres ou mais).';
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
          'A tua conta ProJardim voltou a estar ativa.');

  PERFORM public.admin_log('reactivate_user', p_target_id, jsonb_build_object(
    'note', btrim(p_note), 'suspended_reason', v_status.suspended_reason));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_reactivate_user(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_user(uuid, text) TO authenticated, service_role;


-- ── 4. Encerramento com 30 dias ─────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_schedule_closure(uuid, text, text, text);
CREATE FUNCTION public.admin_schedule_closure(
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
    RAISE EXCEPTION 'Não podes encerrar a tua própria conta.';
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
          'A ProJardim vai encerrar a tua conta a '
          || to_char(v_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY') || '. '
          || COALESCE(v_msg || ' ', '')
          || 'Até lá podes continuar a usar a app. Para contestar, responde para suporte@projardim.pt.');

  PERFORM public.admin_log('schedule_closure', p_target_id, jsonb_strip_nulls(jsonb_build_object(
    'reason', p_reason, 'note', btrim(p_note), 'public_message', v_msg, 'closing_at', v_at)));
  RETURN v_at;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_schedule_closure(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_schedule_closure(uuid, text, text, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_cancel_closure(uuid, text);
CREATE FUNCTION public.admin_cancel_closure(p_target_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(btrim(COALESCE(p_note, ''))) < 5 THEN
    RAISE EXCEPTION 'Escreve uma nota com o motivo (5 carateres ou mais).';
  END IF;
  UPDATE account_status
  SET closing_at = NULL, closing_reason = NULL, closing_message = NULL, updated_at = now()
  WHERE profile_id = p_target_id AND closing_at IS NOT NULL AND suspended_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta conta não tem encerramento marcado.';
  END IF;

  INSERT INTO notifications (user_id, type, title, body)
  VALUES (p_target_id, 'support_notice', 'Encerramento cancelado',
          'O encerramento da tua conta ProJardim foi cancelado. A conta continua ativa.');

  PERFORM public.admin_log('cancel_closure', p_target_id, jsonb_build_object('note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_cancel_closure(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_closure(uuid, text) TO authenticated, service_role;

-- Cron: na data marcada a conta fica suspensa com o motivo do aviso.
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
      COALESCE(r.closing_message, 'A tua conta ProJardim foi encerrada, como avisámos há 30 dias.'));
    INSERT INTO admin_actions (admin_id, action, target_id, details)
    VALUES (NULL, 'closure_done', r.id, jsonb_build_object('reason', r.closing_reason));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.process_account_closures() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_account_closures() TO service_role;

-- cron.schedule faz upsert pelo nome. Verificar depois de aplicar:
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'account-closures';
SELECT cron.schedule('account-closures', '20 3 * * *', 'SELECT process_account_closures()');


-- ── 5. Eliminar a pedido ────────────────────────────────────────
-- O corpo de delete_my_account passa para account_delete_core(p_uid),
-- igual linha a linha; delete_my_account só verifica a sessão e chama-o.

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
        'Um jardineiro retirou a proposta que te tinha feito.',
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
           'O jardineiro responsável fechou o pedido de ajuda.',
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
REVOKE EXECUTE ON FUNCTION public.account_delete_core(uuid) FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  PERFORM public.account_delete_core(auth.uid());
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated, service_role;

-- Ficheiros no Storage de uma pessoa (o SQL não os apaga; a app apaga os
-- seus ao eliminar a conta, o painel mostra a lista para apagar à mão).
CREATE OR REPLACE FUNCTION public.account_storage_paths(p_uid uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'avatars', jsonb_build_array(p_uid::text || '.jpg'),
    'job_photos_folder', p_uid::text || '/',
    'job_photos', COALESCE((
      SELECT jsonb_agg(DISTINCT path ORDER BY path) FROM (
        SELECT jp.storage_path AS path
        FROM job_photos jp JOIN job_requests jr ON jr.id = jp.job_id
        WHERE jr.client_id = p_uid
        UNION
        SELECT unnest(jr.before_photo_paths || jr.after_photo_paths
                      || COALESCE(ARRAY[jr.completion_photo_path], '{}'))
        FROM job_requests jr JOIN job_proposals pr ON pr.id = jr.accepted_proposal_id
        WHERE pr.worker_id = p_uid
      ) x WHERE path IS NOT NULL), '[]'::jsonb));
$function$;
REVOKE EXECUTE ON FUNCTION public.account_storage_paths(uuid) FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.admin_erase_user(uuid, text);
CREATE FUNCTION public.admin_erase_user(p_target_id uuid, p_note text)
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
    RAISE EXCEPTION 'Para eliminar a tua conta usa a app.';
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
REVOKE EXECUTE ON FUNCTION public.admin_erase_user(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_erase_user(uuid, text) TO authenticated, service_role;


-- ── 6. Exportar os dados da pessoa (RGPD, art. 15 e 20) ─────────
-- Tudo o que a ProJardim guarda sobre ela, em JSON. Dados de terceiros
-- ficam de fora (quem a avaliou, a morada exata dos pedidos onde
-- trabalhou), exceto o que ela própria escreveu na Agenda. As notas
-- internas do suporte não entram.

DROP FUNCTION IF EXISTS public.admin_export_user_data(uuid);
CREATE FUNCTION public.admin_export_user_data(p_target_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_out   jsonb;
  v_email text;
  v_auth  jsonb := '{}'::jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Conta não encontrada.';
  END IF;

  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE $q$SELECT jsonb_build_object('email', email, 'created_at', created_at,
                 'email_confirmed_at', email_confirmed_at, 'last_sign_in_at', last_sign_in_at)
               FROM auth.users WHERE id = $1$q$
      INTO v_auth USING p_target_id;
  END IF;

  SELECT jsonb_build_object(
    'exported_at', now(),
    'about', 'Dados guardados pela ProJardim sobre esta conta. Datas em UTC.',
    'account', COALESCE(v_auth, '{}'::jsonb),
    'profile', (SELECT to_jsonb(p) - 'id' FROM profiles p WHERE p.id = p_target_id),
    'account_status', (SELECT to_jsonb(s) - 'profile_id' FROM account_status s
                       WHERE s.profile_id = p_target_id),
    'worker_profile', (SELECT to_jsonb(w) - 'profile_id' FROM worker_profiles w
                       WHERE w.profile_id = p_target_id),
    'worker_services', COALESCE((SELECT jsonb_agg(st.name ORDER BY st.name)
                       FROM worker_service_types wst JOIN service_types st ON st.id = wst.service_type_id
                       WHERE wst.worker_id = p_target_id), '[]'::jsonb),
    'plan', (SELECT jsonb_build_object('tier', tier, 'starts_at', starts_at, 'ends_at', ends_at,
                                       'verified_at', verified_at)
             FROM worker_plans WHERE worker_id = p_target_id),
    'jobs_as_client', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', jr.id, 'service', st.name, 'status', jr.status, 'created_at', jr.created_at,
        'address', jr.address_text, 'area', jr.location_area,
        'lat', jr.location_lat, 'lng', jr.location_lng,
        'description', jr.description, 'availability', jr.availability_text,
        'preferred_date', jr.preferred_date, 'confirmed_date', jr.confirmed_date,
        'cancel_reason', jr.cancel_reason, 'cancel_detail', jr.cancel_reason_detail,
        'photos', COALESCE((SELECT jsonb_agg(ph.storage_path) FROM job_photos ph
                            WHERE ph.job_id = jr.id), '[]'::jsonb))
        ORDER BY jr.created_at)
      FROM job_requests jr LEFT JOIN service_types st ON st.id = jr.service_type_id
      WHERE jr.client_id = p_target_id), '[]'::jsonb),
    -- Como jardineiro: as propostas dele; do pedido só a localidade.
    'proposals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'job_id', pr.job_id, 'service', st.name, 'area', jr.location_area,
        'status', pr.status, 'created_at', pr.created_at, 'pricing_mode', pr.pricing_mode,
        'hourly_rate', pr.hourly_rate, 'total_price', pr.total_price,
        'estimated_hours_min', pr.estimated_hours_min, 'estimated_hours_max', pr.estimated_hours_max,
        'estimated_days_min', pr.estimated_days_min, 'estimated_days_max', pr.estimated_days_max,
        'scheduled_date', pr.scheduled_date, 'scheduled_time', pr.scheduled_time,
        'notes', pr.notes, 'job_status', jr.status,
        'before_photos', CASE WHEN jr.accepted_proposal_id = pr.id THEN jr.before_photo_paths END,
        'after_photos',  CASE WHEN jr.accepted_proposal_id = pr.id THEN jr.after_photo_paths END)
        ORDER BY pr.created_at)
      FROM job_proposals pr JOIN job_requests jr ON jr.id = pr.job_id
      LEFT JOIN service_types st ON st.id = jr.service_type_id
      WHERE pr.worker_id = p_target_id), '[]'::jsonb),
    'help_requests', COALESCE((SELECT jsonb_agg(to_jsonb(hr) - 'proposal_id' ORDER BY hr.created_at)
      FROM help_requests hr JOIN job_proposals pr ON pr.id = hr.proposal_id
      WHERE pr.worker_id = p_target_id), '[]'::jsonb),
    'help_applications', COALESCE((SELECT jsonb_agg(to_jsonb(ha) - 'worker_id' ORDER BY ha.created_at)
      FROM help_acceptances ha WHERE ha.worker_id = p_target_id), '[]'::jsonb),
    'ratings_given', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'job_id', r.job_id, 'stars', r.stars, 'comment', r.comment, 'created_at', r.created_at)
        ORDER BY r.created_at)
      FROM (SELECT job_id, stars, comment, created_at FROM ratings WHERE rater_id = p_target_id
            UNION ALL
            SELECT job_id, stars, comment, created_at FROM ratings_hidden WHERE rater_id = p_target_id) r),
      '[]'::jsonb),
    'ratings_received', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'job_id', r.job_id, 'stars', r.stars, 'comment', r.comment, 'created_at', r.created_at,
        'hidden_by_support', r.hidden)
        ORDER BY r.created_at)
      FROM (SELECT job_id, stars, comment, created_at, false AS hidden FROM ratings WHERE ratee_id = p_target_id
            UNION ALL
            SELECT job_id, stars, comment, created_at, true FROM ratings_hidden WHERE ratee_id = p_target_id) r),
      '[]'::jsonb),
    'problem_reports', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'job_id', job_id, 'description', description, 'created_at', created_at, 'status', status)
        ORDER BY created_at)
      FROM job_reports WHERE reporter_id = p_target_id), '[]'::jsonb),
    'support_cases', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'number', number, 'kind', kind, 'status', status, 'summary', summary,
        'decision', decision, 'created_at', created_at, 'closed_at', closed_at)
        ORDER BY created_at)
      FROM support_cases WHERE person_id = p_target_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type', type, 'title', title, 'body', body, 'read', read, 'created_at', created_at)
        ORDER BY created_at)
      FROM notifications WHERE user_id = p_target_id), '[]'::jsonb),
    'notification_preferences', (SELECT to_jsonb(np) - 'user_id' FROM notification_preferences np
                                 WHERE np.user_id = p_target_id),
    'devices', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'platform', platform, 'created_at', created_at, 'updated_at', updated_at))
      FROM device_tokens WHERE user_id = p_target_id), '[]'::jsonb),
    'fleet_cards', COALESCE((SELECT jsonb_agg(to_jsonb(f) - 'worker_id')
      FROM worker_fleet_cards f WHERE f.worker_id = p_target_id), '[]'::jsonb),
    'card_visits', (SELECT jsonb_build_object('count', count(*), 'first', min(created_at),
                                              'last', max(created_at))
                    FROM worker_card_visits WHERE worker_id = p_target_id),
    -- Agenda do jardineiro: só aqui, a pedido da própria pessoa. O painel
    -- nunca a mostra (T-SUP-42 abre exceção só para esta função).
    'calendar', jsonb_build_object(
      'entries', COALESCE((SELECT jsonb_agg(to_jsonb(e) - 'worker_id' ORDER BY e.starts_on)
                 FROM worker_calendar_entries e WHERE e.worker_id = p_target_id), '[]'::jsonb),
      'exceptions', COALESCE((SELECT jsonb_agg(to_jsonb(x) - 'worker_id' ORDER BY x.occurrence_date)
                 FROM worker_calendar_exceptions x WHERE x.worker_id = p_target_id), '[]'::jsonb)),
    'storage', public.account_storage_paths(p_target_id)
  ) INTO v_out;

  PERFORM public.admin_log('export_user', p_target_id, '{}'::jsonb);
  RETURN v_out;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_export_user_data(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_export_user_data(uuid) TO authenticated, service_role;


-- ── 7. Foto de perfil e portefólio ──────────────────────────────

CREATE TABLE IF NOT EXISTS public.profile_photos_hidden (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id    uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind          text        NOT NULL CHECK (kind IN ('avatar', 'portfolio')),
  url           text        NOT NULL,
  hidden_at     timestamptz NOT NULL DEFAULT now(),
  hidden_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  hidden_reason text        NOT NULL,
  hidden_note   text
);
CREATE INDEX IF NOT EXISTS profile_photos_hidden_profile_idx ON public.profile_photos_hidden (profile_id);
ALTER TABLE public.profile_photos_hidden ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.profile_photos_hidden FROM anon, authenticated;

-- p_url: o avatar_url atual ou um dos URLs em worker_profiles.photos.
DROP FUNCTION IF EXISTS public.admin_hide_profile_photo(uuid, text, text, text);
CREATE FUNCTION public.admin_hide_profile_photo(
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
            THEN 'O suporte da ProJardim retirou a tua foto de perfil. Podes pôr outra que cumpra os Termos.'
            ELSE 'O suporte da ProJardim retirou uma foto do teu perfil.' END
          || ' Se não concordares, responde para suporte@projardim.pt nos próximos 6 meses.');

  PERFORM public.admin_log('hide_profile_photo', p_target_id, jsonb_build_object(
    'kind', v_kind, 'url', p_url, 'reason', p_reason, 'note', btrim(p_note)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_hide_profile_photo(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_hide_profile_photo(uuid, text, text, text) TO authenticated, service_role;


-- ── 8. Estado da conta, reenviar código, mapa ───────────────────

-- O que o cartão "Conta" da ficha precisa. Email mascarado; o completo
-- só sai por admin_resend_code (fica registado).
DROP FUNCTION IF EXISTS public.admin_get_account(uuid);
CREATE FUNCTION public.admin_get_account(p_target_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p    profiles;
  v_s    account_status;
  v_auth record;
  v_out  jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT * INTO v_p FROM profiles WHERE id = p_target_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conta não encontrada.';
  END IF;
  SELECT * INTO v_s FROM account_status WHERE profile_id = p_target_id;

  v_out := jsonb_build_object(
    'id', v_p.id, 'role', v_p.role, 'deleted_at', v_p.deleted_at,
    'suspended_at', v_s.suspended_at, 'suspended_reason', v_s.suspended_reason,
    'suspended_message', v_s.suspended_message,
    'closing_at', v_s.closing_at, 'closing_reason', v_s.closing_reason,
    'closing_message', v_s.closing_message,
    'avatar_url', v_p.avatar_url,
    'portfolio', COALESCE((SELECT to_jsonb(photos) FROM worker_profiles
                           WHERE profile_id = p_target_id), '[]'::jsonb),
    'is_admin', EXISTS (SELECT 1 FROM admin_users WHERE user_id = p_target_id),
    'deletion_blocker', CASE WHEN v_p.deleted_at IS NULL
                             THEN public.account_deletion_blocker(p_target_id) END,
    'jobs_in_progress', (SELECT count(*) FROM job_requests jr
                         LEFT JOIN job_proposals jp ON jp.id = jr.accepted_proposal_id
                         WHERE (jr.client_id = p_target_id OR jp.worker_id = p_target_id)
                           AND jr.status IN ('confirmed', 'awaiting_confirmation')));

  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE 'SELECT email, email_confirmed_at, last_sign_in_at FROM auth.users WHERE id = $1'
      INTO v_auth USING p_target_id;
    v_out := v_out || jsonb_build_object(
      'email_masked', CASE WHEN v_auth.email IS NULL THEN NULL
                           ELSE left(v_auth.email, 1) || '***' || substr(v_auth.email, strpos(v_auth.email, '@')) END,
      'email_confirmed', v_auth.email_confirmed_at IS NOT NULL,
      'last_sign_in_at', v_auth.last_sign_in_at);
  END IF;
  RETURN v_out;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_account(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_account(uuid) TO authenticated, service_role;

-- Reenviar o código de confirmação: o envio é feito pela app
-- (auth.resend), que precisa do email. Esta RPC regista e devolve-o.
DROP FUNCTION IF EXISTS public.admin_resend_code(uuid);
CREATE FUNCTION public.admin_resend_code(p_target_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email     text;
  v_confirmed timestamptz;
BEGIN
  PERFORM public.assert_verified_admin();
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Sem tabela de autenticação.';
  END IF;
  EXECUTE 'SELECT email, email_confirmed_at FROM auth.users WHERE id = $1'
    INTO v_email, v_confirmed USING p_target_id;
  IF v_email IS NULL OR v_email LIKE 'eliminado+%' THEN
    RAISE EXCEPTION 'Conta não encontrada ou eliminada.';
  END IF;
  IF v_confirmed IS NOT NULL THEN
    RAISE EXCEPTION 'Este email já está confirmado.';
  END IF;
  PERFORM public.admin_log('resend_code', p_target_id, '{}'::jsonb);
  RETURN v_email;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_resend_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resend_code(uuid) TO authenticated, service_role;

-- Mapa: pedidos ativos (e concluídos nos últimos p_days) e jardineiros
-- com o raio. A app liga e desliga as camadas.
DROP FUNCTION IF EXISTS public.admin_map_points(integer);
CREATE FUNCTION public.admin_map_points(p_days integer DEFAULT 30)
RETURNS TABLE(
  kind       text,
  id         uuid,
  lat        double precision,
  lng        double precision,
  radius_km  integer,
  label      text,
  status     text,
  service    text,
  plan       text,
  created_at timestamptz
)
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
         LEAST(GREATEST(wp.radius_km, 1), 50), COALESCE(p.full_name, 'Jardineiro'),
         CASE WHEN s.suspended_at IS NOT NULL THEN 'suspended' ELSE 'active' END,
         NULL::text, COALESCE(pl.tier, 'free'), p.created_at
  FROM worker_profiles wp
  JOIN profiles p ON p.id = wp.profile_id AND p.deleted_at IS NULL
  LEFT JOIN worker_plans pl ON pl.worker_id = wp.profile_id
  LEFT JOIN account_status s ON s.profile_id = wp.profile_id
  WHERE NOT (wp.base_lat = 0 AND wp.base_lng = 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_map_points(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_map_points(integer) TO authenticated, service_role;
