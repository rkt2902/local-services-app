-- ══════════════════════════════════════════════════════════════
-- 0066 — Eliminar conta: apagar o que ficava para trás e bloquear o
--        mesmo email durante 90 dias
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor, depois da 0065.
-- Pode correr-se mais do que uma vez.
--
-- 1. `deleted_account_emails`: guarda só o hash SHA-256 do email
--    normalizado (minúsculas, sem espaços, sem "+etiqueta") e até quando
--    fica bloqueado. Nem o email em claro nem o id da conta: o registo não
--    diz a quem pertenceu. Sem policies, só o SQL Editor lê.
-- 2. Trigger em auth.users (BEFORE INSERT e mudança de email): recusa
--    criar conta, ou mudar para um email, que esteja bloqueado. Apanha o
--    registo por email e por Google/Facebook. O GoTrue devolve à app
--    "Database error saving new user" (a app mostra uma mensagem própria).
-- 3. Cron diário `cleanup-deleted-account-emails`: apaga os hashes cujo
--    prazo passou.
-- 4. `check_can_delete_my_account()`: a app pergunta antes de apagar os
--    ficheiros do Storage, para não os perder se a eliminação for recusada
--    (trabalho em curso). Mesma regra que delete_my_account.
-- 5. `delete_my_account()` (mesma assinatura da 0049) passa a:
--    - guardar o hash do email por 90 dias antes de o trocar;
--    - apagar destaques e redes sociais (0051), agenda (0064), plano
--      (0060), visitas ao cartão e indicações (0059), preferências de
--      avisos (0062) e o registo de admin, se for o caso;
--    - tirar dos pedidos dele como cliente a morada exata (fica a
--      localidade), a descrição, a disponibilidade e as fotos;
--      coordenadas arredondadas a ~1 km;
--    - tirar as notas das propostas e a mensagem das candidaturas dele;
--    - tirar as fotos de antes/depois dos trabalhos que fez (os ficheiros
--      estão na pasta dele no Storage, que a app apaga);
--    - apagar o comentário das avaliações que escreveu (as estrelas ficam,
--      contam para a média de outra pessoa).
--    O que fica: o esqueleto dos trabalhos (serviço, datas, preço,
--    estado) no histórico da outra parte, as estrelas das avaliações e os
--    reports de problemas (podem ser precisos num litígio).
-- 6. Contas já eliminadas antes desta migration: a limpeza da secção 5 é
--    aplicada já. O email delas já não existe, por isso não ficam
--    bloqueadas, e os ficheiros do Storage delas não se apagam por SQL.
--
-- Ficheiros do Storage: o Supabase não deixa apagar storage.objects por
-- SQL, por isso é a app que apaga avatars/<id>.jpg e job-photos/<id>/...
-- (as policies de dono já o permitem) entre o passo 4 e o 5.
--
-- Identidade sempre por auth.uid(); nenhuma RPC recebe ids de utilizador.
-- As funções internas que recebem um id não são executáveis pela app.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Emails bloqueados ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.deleted_account_emails (
  email_hash    text        PRIMARY KEY,
  deleted_at    timestamptz NOT NULL DEFAULT now(),
  blocked_until timestamptz NOT NULL
);

ALTER TABLE public.deleted_account_emails ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.deleted_account_emails FROM PUBLIC, anon, authenticated;

-- Normaliza e faz o hash. "+etiqueta" sai para "ana+x@" e "ana@" contarem
-- como o mesmo email.
CREATE OR REPLACE FUNCTION public.email_block_hash(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_email IS NULL OR btrim(p_email) = '' THEN NULL
    ELSE encode(
      sha256(convert_to(
        regexp_replace(lower(btrim(p_email)), '\+[^@]*@', '@'),
        'UTF8')),
      'hex')
  END;
$function$;

REVOKE EXECUTE ON FUNCTION public.email_block_hash(text) FROM PUBLIC, anon, authenticated;


-- ── 2. Trigger em auth.users ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.block_recently_deleted_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.email IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.email IS NOT DISTINCT FROM OLD.email THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.deleted_account_emails
    WHERE  email_hash    = public.email_block_hash(NEW.email)
      AND  blocked_until > now()
  ) THEN
    RAISE EXCEPTION 'email_recently_deleted'
      USING HINT = 'Este email pertenceu a uma conta eliminada há menos de 90 dias.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.block_recently_deleted_email() FROM PUBLIC, anon, authenticated;

DO $do$
BEGIN
  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_block_recently_deleted_email ON auth.users';
    EXECUTE 'CREATE TRIGGER trg_block_recently_deleted_email
               BEFORE INSERT OR UPDATE OF email ON auth.users
               FOR EACH ROW EXECUTE FUNCTION public.block_recently_deleted_email()';
  END IF;
END;
$do$;


-- ── 3. Limpeza diária dos prazos que passaram ───────────────────

CREATE OR REPLACE FUNCTION public.cleanup_deleted_account_emails()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Esta função é apenas para execução via cron.';
  END IF;

  DELETE FROM deleted_account_emails WHERE blocked_until <= now();
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.cleanup_deleted_account_emails() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'cleanup-deleted-account-emails',
  '45 3 * * *',
  'SELECT cleanup_deleted_account_emails()'
);


-- ── 4. Pode eliminar? ───────────────────────────────────────────

-- Interna: mensagem a mostrar se houver trabalho em curso, NULL se não.
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
  THEN 'Tens trabalhos em curso. Conclui-os ou cancela-os antes de eliminar a conta.'
  END;
$function$;

REVOKE EXECUTE ON FUNCTION public.account_deletion_blocker(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.check_can_delete_my_account()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     uuid := auth.uid();
  v_blocker text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Esta conta já foi eliminada.';
  END IF;

  v_blocker := account_deletion_blocker(v_uid);
  IF v_blocker IS NOT NULL THEN
    RAISE EXCEPTION '%', v_blocker;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.check_can_delete_my_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.check_can_delete_my_account() TO authenticated, service_role;


-- ── 5. Apagar os dados da conta ─────────────────────────────────

-- Interna, chamada por delete_my_account e pelo acerto da secção 6.
-- Não mexe em estados nem envia avisos: isso fica em delete_my_account.
CREATE OR REPLACE FUNCTION public.erase_account_data(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Perfil
  UPDATE profiles
  SET    full_name  = 'Conta eliminada',
         phone      = NULL,
         avatar_url = NULL,
         deleted_at = COALESCE(deleted_at, now()),
         updated_at = now()
  WHERE  id = p_uid;

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
         highlights          = '{}',
         social_links        = '[]'::jsonb,
         updated_at          = now()
  WHERE  profile_id = p_uid;

  DELETE FROM worker_service_types       WHERE worker_id = p_uid;
  DELETE FROM device_tokens              WHERE user_id   = p_uid;
  DELETE FROM worker_fleet_cards         WHERE worker_id = p_uid;
  DELETE FROM notifications              WHERE user_id   = p_uid;
  DELETE FROM notification_preferences   WHERE user_id   = p_uid;
  DELETE FROM worker_plans               WHERE worker_id = p_uid;
  DELETE FROM worker_calendar_exceptions WHERE worker_id = p_uid;
  DELETE FROM worker_calendar_entries    WHERE worker_id = p_uid;
  DELETE FROM client_referrals           WHERE client_id = p_uid OR worker_id = p_uid;
  DELETE FROM worker_card_visits         WHERE worker_id = p_uid;
  UPDATE worker_card_visits
  SET    visitor_id = NULL, device_key = NULL
  WHERE  visitor_id = p_uid;
  DELETE FROM admin_users                WHERE user_id   = p_uid;

  -- Pedidos dele como cliente: ficam no histórico de quem lá trabalhou,
  -- sem morada exata, texto nem fotos. location_area é a localidade (0043).
  DELETE FROM job_photos
  WHERE  job_id IN (SELECT id FROM job_requests WHERE client_id = p_uid);

  UPDATE job_requests
  SET    address_text         = COALESCE(NULLIF(btrim(location_area), ''), 'Morada removida'),
         location_lat         = round(location_lat, 2),
         location_lng         = round(location_lng, 2),
         description          = 'Pedido de uma conta eliminada.',
         availability_text    = NULL,
         cancel_reason_detail = NULL,
         updated_at           = now()
  WHERE  client_id = p_uid
    AND  description IS DISTINCT FROM 'Pedido de uma conta eliminada.';

  -- Trabalhos que fez como jardineiro principal: as fotos de antes/depois
  -- estão na pasta dele no Storage, que a app apaga.
  UPDATE job_requests jr
  SET    completion_photo_path = NULL,
         before_photo_paths    = '{}',
         after_photo_paths     = '{}',
         updated_at            = now()
  FROM   job_proposals jp
  WHERE  jp.id        = jr.accepted_proposal_id
    AND  jp.worker_id = p_uid
    AND  (jr.completion_photo_path IS NOT NULL
          OR jr.before_photo_paths <> '{}'
          OR jr.after_photo_paths  <> '{}');

  UPDATE job_proposals
  SET    notes = NULL
  WHERE  worker_id = p_uid AND notes IS NOT NULL;

  UPDATE help_acceptances
  SET    message = NULL
  WHERE  worker_id = p_uid AND message IS NOT NULL;

  -- Avaliações que escreveu: as estrelas ficam (média de outra pessoa),
  -- o texto sai.
  UPDATE ratings
  SET    comment = NULL
  WHERE  rater_id = p_uid AND comment IS NOT NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.erase_account_data(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_email     text;
  v_old_email text;
  v_pwd       text;
  v_blocker   text;
  r           record;
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
  v_blocker := account_deletion_blocker(v_uid);
  IF v_blocker IS NOT NULL THEN
    RAISE EXCEPTION '%', v_blocker;
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

REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_my_account() TO authenticated, service_role;


-- ── 6. Contas eliminadas antes desta migration ──────────────────

DO $do$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT id FROM public.profiles WHERE deleted_at IS NOT NULL LOOP
    PERFORM public.erase_account_data(r.id);
  END LOOP;
END;
$do$;
