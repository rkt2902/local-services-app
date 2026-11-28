-- 0085: convites por email a partir do painel de admin (/admin/convites).
--
-- O admin escreve o nome e o email de um Profissional que quer convidar,
-- escolhe o modelo (convite com design, convite só texto ou lembrete),
-- pré-visualiza e envia. O envio é feito pela Edge Function
-- `send-invite` (API transacional do Brevo, chave só nos segredos do
-- Supabase), que chama estas RPCs com o JWT do admin:
--
--   1. admin_invite_create  regista o envio como 'pending' e devolve o
--                           token de "não quero receber" deste email;
--   2. (a função envia pelo Brevo)
--   3. admin_invite_finish  marca 'sent' ou 'failed'.
--
-- RGPD: só se escreve para contactos que o admin introduz à mão, um de
-- cada vez. Cada email leva um link para deixar de receber
-- (/sem-convites?t=<token>, RPC anónima invite_optout) e quem pede fica
-- em email_optouts para sempre (é o que garante que não volta a
-- receber). O histórico de convites apaga-se ao fim de 12 meses (cron).
--
-- Tudo com auth.uid(): nenhuma RPC recebe o id do admin. Pode correr-se
-- mais do que uma vez.

-- ── 1. Tabelas ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_invites (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  template            text        NOT NULL
                      CHECK (template IN ('founder_invite', 'founder_invite_plain', 'founder_reminder')),
  recipient_name      text        NOT NULL,
  recipient_email     text        NOT NULL,
  subject             text        NOT NULL,
  body_text           text        NOT NULL,
  status              text        NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'sent', 'failed')),
  provider_message_id text,
  error               text,
  optout_token        uuid        NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_by          uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  sent_at             timestamptz
);
CREATE INDEX IF NOT EXISTS admin_invites_email_idx ON public.admin_invites (recipient_email, created_at DESC);
CREATE INDEX IF NOT EXISTS admin_invites_created_idx ON public.admin_invites (created_at DESC);
ALTER TABLE public.admin_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_invites FROM anon, authenticated;

-- Quem não quer receber mais emails (pelo link ou porque respondeu "não").
-- O email fica sempre em minúsculas.
CREATE TABLE IF NOT EXISTS public.email_optouts (
  email       text        PRIMARY KEY CHECK (email = lower(email)),
  source      text        NOT NULL CHECK (source IN ('link', 'admin')),
  invite_id   uuid        REFERENCES public.admin_invites(id) ON DELETE SET NULL,
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.email_optouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.email_optouts FROM anon, authenticated;

-- ── 2. Auxiliares ───────────────────────────────────────────────

-- Máximo de convites por dia (todos os admins juntos). Protege a
-- reputação do domínio e fica muito abaixo dos 300/dia do Brevo grátis.
CREATE OR REPLACE FUNCTION public.admin_invite_daily_limit()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$ SELECT 40 $function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_daily_limit() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_invite_normalize_email(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$ SELECT lower(btrim(COALESCE(p_email, ''))) $function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_normalize_email(text) FROM PUBLIC, anon, authenticated;

-- ── 3. Antes de enviar: o que se sabe deste email ───────────────

DROP FUNCTION IF EXISTS public.admin_invite_status(text);
CREATE FUNCTION public.admin_invite_status(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := public.admin_invite_normalize_email(p_email);
  v_out   jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  SELECT jsonb_build_object(
    'opted_out', EXISTS (SELECT 1 FROM email_optouts o WHERE o.email = v_email),
    'opted_out_at', (SELECT o.created_at FROM email_optouts o WHERE o.email = v_email),
    'sent_count', (SELECT count(*) FROM admin_invites i
                   WHERE i.recipient_email = v_email AND i.status = 'sent'),
    'last_sent_at', (SELECT max(i.sent_at) FROM admin_invites i
                     WHERE i.recipient_email = v_email AND i.status = 'sent'),
    'last_template', (SELECT i.template FROM admin_invites i
                      WHERE i.recipient_email = v_email AND i.status = 'sent'
                      ORDER BY i.sent_at DESC LIMIT 1),
    'sent_today', (SELECT count(*) FROM admin_invites i
                   WHERE i.status IN ('pending', 'sent')
                     AND i.created_at > now() - interval '24 hours'),
    'daily_limit', public.admin_invite_daily_limit()
  ) INTO v_out;
  RETURN v_out;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_status(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_invite_status(text) TO authenticated, service_role;

-- ── 4. Registar um envio (chamada pela Edge Function) ───────────

DROP FUNCTION IF EXISTS public.admin_invite_create(text, text, text, text, text);
CREATE FUNCTION public.admin_invite_create(
  p_template        text,
  p_recipient_name  text,
  p_recipient_email text,
  p_subject         text,
  p_body_text       text
)
RETURNS TABLE(id uuid, optout_token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_name    text := btrim(COALESCE(p_recipient_name, ''));
  v_email   text := public.admin_invite_normalize_email(p_recipient_email);
  v_subject text := btrim(COALESCE(p_subject, ''));
  v_body    text := btrim(COALESCE(p_body_text, ''));
  v_id      uuid;
  v_token   uuid;
BEGIN
  PERFORM public.assert_verified_admin();
  IF p_template IS NULL OR p_template NOT IN ('founder_invite', 'founder_invite_plain', 'founder_reminder') THEN
    RAISE EXCEPTION 'Modelo de email inválido.';
  END IF;
  IF length(v_name) < 2 OR length(v_name) > 80 THEN
    RAISE EXCEPTION 'O nome tem de ter entre 2 e 80 carateres.';
  END IF;
  IF length(v_email) > 254 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'O email não parece válido.';
  END IF;
  IF length(v_subject) < 3 OR length(v_subject) > 150 THEN
    RAISE EXCEPTION 'O assunto tem de ter entre 3 e 150 carateres.';
  END IF;
  IF length(v_body) < 20 OR length(v_body) > 6000 THEN
    RAISE EXCEPTION 'O texto do email está vazio ou é demasiado longo.';
  END IF;
  IF EXISTS (SELECT 1 FROM email_optouts o WHERE o.email = v_email) THEN
    RAISE EXCEPTION 'Este email pediu para não receber mais mensagens. Não é possível enviar.';
  END IF;
  -- Duplo clique, ou o mesmo modelo outra vez no mesmo dia. Um envio
  -- 'pending' com mais de 10 minutos ficou a meio e já não conta.
  IF EXISTS (SELECT 1 FROM admin_invites i
             WHERE i.recipient_email = v_email
               AND i.template = p_template
               AND i.created_at > now() - interval '24 hours'
               AND (i.status = 'sent'
                    OR (i.status = 'pending' AND i.created_at > now() - interval '10 minutes'))) THEN
    RAISE EXCEPTION 'Este email já recebeu este modelo nas últimas 24 horas.';
  END IF;
  IF (SELECT count(*) FROM admin_invites i
      WHERE i.status IN ('pending', 'sent')
        AND i.created_at > now() - interval '24 hours') >= public.admin_invite_daily_limit() THEN
    RAISE EXCEPTION 'Chegou ao limite de % convites em 24 horas. Tente amanhã.',
      public.admin_invite_daily_limit();
  END IF;

  INSERT INTO admin_invites (template, recipient_name, recipient_email, subject, body_text, created_by)
  VALUES (p_template, v_name, v_email, v_subject, v_body, auth.uid())
  RETURNING admin_invites.id, admin_invites.optout_token INTO v_id, v_token;

  PERFORM public.admin_log('invite_create', v_id, jsonb_build_object(
    'template', p_template, 'domain', split_part(v_email, '@', 2)));

  id := v_id;
  optout_token := v_token;
  RETURN NEXT;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_create(text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_invite_create(text, text, text, text, text) TO authenticated, service_role;

-- Resultado do envio. Só o admin que o criou, e só enquanto 'pending'.
DROP FUNCTION IF EXISTS public.admin_invite_finish(uuid, boolean, text, text);
CREATE FUNCTION public.admin_invite_finish(
  p_id                  uuid,
  p_ok                  boolean,
  p_provider_message_id text DEFAULT NULL,
  p_error               text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_verified_admin();
  UPDATE admin_invites i
  SET status = CASE WHEN p_ok THEN 'sent' ELSE 'failed' END,
      provider_message_id = left(p_provider_message_id, 200),
      error = CASE WHEN p_ok THEN NULL ELSE left(COALESCE(p_error, 'Erro desconhecido.'), 500) END,
      sent_at = CASE WHEN p_ok THEN now() ELSE NULL END
  WHERE i.id = p_id
    AND i.status = 'pending'
    AND i.created_by = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Este envio já não está pendente.';
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_finish(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_invite_finish(uuid, boolean, text, text) TO authenticated, service_role;

-- ── 5. Histórico ────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_list_invites(text, integer, integer);
CREATE FUNCTION public.admin_list_invites(
  p_search text    DEFAULT NULL,
  p_limit  integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id              uuid,
  template        text,
  recipient_name  text,
  recipient_email text,
  subject         text,
  status          text,
  error           text,
  created_at      timestamptz,
  sent_at         timestamptz,
  opted_out_at    timestamptz,
  admin_email     text,
  total_count     bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_q text := NULLIF(btrim(COALESCE(p_search, '')), '');
BEGIN
  PERFORM public.assert_verified_admin();
  RETURN QUERY
  SELECT i.id, i.template, i.recipient_name, i.recipient_email, i.subject,
         i.status, i.error, i.created_at, i.sent_at, o.created_at,
         u.email::text, count(*) OVER ()
  FROM admin_invites i
  LEFT JOIN email_optouts o ON o.email = i.recipient_email
  LEFT JOIN auth.users u ON u.id = i.created_by
  WHERE v_q IS NULL
     OR i.recipient_email ILIKE '%' || v_q || '%'
     OR i.recipient_name ILIKE '%' || v_q || '%'
  ORDER BY i.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_list_invites(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_invites(text, integer, integer) TO authenticated, service_role;

-- ── 6. Não quero receber ────────────────────────────────────────

-- O admin regista quem respondeu "não" (ou pediu por outra via).
DROP FUNCTION IF EXISTS public.admin_invite_set_optout(text, text);
CREATE FUNCTION public.admin_invite_set_optout(p_email text, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := public.admin_invite_normalize_email(p_email);
BEGIN
  PERFORM public.assert_verified_admin();
  IF length(v_email) > 254 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'O email não parece válido.';
  END IF;
  INSERT INTO email_optouts (email, source, note)
  VALUES (v_email, 'admin', NULLIF(left(btrim(COALESCE(p_note, '')), 300), ''))
  ON CONFLICT (email) DO NOTHING;
  PERFORM public.admin_log('invite_optout', NULL, jsonb_build_object(
    'domain', split_part(v_email, '@', 2)));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_invite_set_optout(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_invite_set_optout(text, text) TO authenticated, service_role;

-- O link do email (/sem-convites?t=<token>), aberto sem sessão. Devolve
-- false se o token não existir. Pedir duas vezes não faz mal.
DROP FUNCTION IF EXISTS public.invite_optout(uuid);
CREATE FUNCTION public.invite_optout(p_token uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_invite admin_invites%ROWTYPE;
BEGIN
  IF p_token IS NULL THEN
    RETURN false;
  END IF;
  SELECT * INTO v_invite FROM admin_invites i WHERE i.optout_token = p_token;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  INSERT INTO email_optouts (email, source, invite_id)
  VALUES (v_invite.recipient_email, 'link', v_invite.id)
  ON CONFLICT (email) DO NOTHING;
  RETURN true;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.invite_optout(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_optout(uuid) TO anon, authenticated, service_role;

-- ── 7. Apagar o histórico com mais de 12 meses ──────────────────
-- email_optouts fica (sem ele, a pessoa voltava a receber).

CREATE OR REPLACE FUNCTION public.purge_old_admin_invites()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  DELETE FROM admin_invites WHERE created_at < now() - interval '12 months';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.purge_old_admin_invites() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_admin_invites() TO service_role;

-- cron.schedule faz upsert pelo nome. Verificar depois de aplicar:
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'admin-invites-purge';
SELECT cron.schedule('admin-invites-purge', '40 3 * * 0', 'SELECT purge_old_admin_invites()');

NOTIFY pgrst, 'reload schema';
