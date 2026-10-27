-- ============================================================
-- 0041_push_notifications.sql
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor.
--
-- Contexto: notificações push grátis via Firebase Cloud Messaging (FCM).
-- Até aqui as notificações só existiam na tabela `notifications` e só
-- chegavam ao utilizador com a app aberta (stream Realtime em
-- notification_repository.dart). Os jardineiros perdiam pedidos.
--
-- Desenho: TODAS as notificações já são criadas por INSERT em
-- `notifications` (funções SECURITY DEFINER). Por isso basta um trigger
-- AFTER INSERT nessa tabela que chama a Edge Function `send-push`
-- (supabase/functions/send-push) via pg_net. A Edge Function lê os tokens
-- do destinatário em `device_tokens` e envia para o FCM (HTTP v1). Nenhuma
-- função de negócio existente precisa de mudar.
--
-- O que esta migration cria:
--   1) Tabela `device_tokens` (1 linha por token FCM de dispositivo).
--   2) RPCs `register_device_token` / `unregister_device_token`
--      (SECURITY DEFINER, sem parâmetro de identidade: usam auth.uid()).
--   3) Trigger `notifications_send_push` → net.http_post para a Edge
--      Function, com URL e segredo lidos do Vault.
--
-- Pré-requisitos (fazer ANTES de aplicar):
--   a) Extensão pg_net ativa (Database → Extensions → pg_net). O CREATE
--      EXTENSION abaixo também a tenta ativar.
--   b) Dois segredos no Vault (SQL Editor):
--        select vault.create_secret(
--          'https://<PROJECT_REF>.supabase.co/functions/v1/send-push',
--          'push_function_url');
--        select vault.create_secret('<SEGREDO_ALEATORIO>', 'push_webhook_secret');
--      O mesmo <SEGREDO_ALEATORIO> vai para a Edge Function como
--      PUSH_WEBHOOK_SECRET (supabase secrets set ...).
--   Sem estes segredos o trigger não faz nada (não falha o INSERT).
--
-- Segurança: o trigger nunca deixa falhar o INSERT da notificação (erros
-- viram WARNING). `device_tokens` só é legível pelo próprio dono; escrita
-- só via RPC. A Edge Function rejeita pedidos sem o segredo correto.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── 1) device_tokens ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.device_tokens (
  token       text        PRIMARY KEY,
  user_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  platform    text        NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
  ON public.device_tokens (user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Utilizador vê os seus tokens" ON public.device_tokens;
CREATE POLICY "Utilizador vê os seus tokens"
  ON public.device_tokens FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Sem INSERT/UPDATE/DELETE para authenticated: só via RPCs abaixo.

-- ── 2) RPCs ──────────────────────────────────────────────────

-- Regista (ou reatribui) o token ao utilizador atual. Um token é do
-- dispositivo, não da conta: se outra conta fizer login no mesmo
-- telemóvel, o token passa para essa conta (a anterior deixa de receber).
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token    text,
  p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_token IS NULL OR length(p_token) = 0 THEN
    RAISE EXCEPTION 'token is required';
  END IF;

  INSERT INTO public.device_tokens (token, user_id, platform)
  VALUES (p_token, auth.uid(), p_platform)
  ON CONFLICT (token) DO UPDATE
    SET user_id    = EXCLUDED.user_id,
        platform   = EXCLUDED.platform,
        updated_at = now();
END;
$$;

-- Remove o token (chamado no logout, antes de terminar a sessão).
CREATE OR REPLACE FUNCTION public.unregister_device_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.device_tokens
  WHERE token = p_token
    AND user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.register_device_token(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_device_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_device_token(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text) TO authenticated;

-- ── 3) Trigger → Edge Function ───────────────────────────────

CREATE OR REPLACE FUNCTION public.notifications_send_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  -- Ninguém com token → nada a enviar (evita chamadas inúteis, ex.:
  -- notify_workers_new_job a notificar jardineiros sem app instalada).
  IF NOT EXISTS (SELECT 1 FROM public.device_tokens WHERE user_id = NEW.user_id) THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'push_function_url';
  SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets WHERE name = 'push_webhook_secret';

  IF v_url IS NULL OR v_secret IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    body    := jsonb_build_object('notification_id', NEW.id),
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- O push é "best effort": nunca deixar falhar a transação de negócio.
  RAISE WARNING 'notifications_send_push failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notifications_send_push() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS notifications_send_push ON public.notifications;
CREATE TRIGGER notifications_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notifications_send_push();

NOTIFY pgrst, 'reload schema';
