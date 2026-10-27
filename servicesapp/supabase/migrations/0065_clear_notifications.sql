-- ══════════════════════════════════════════════════════════════
-- 0065 — Notificações: "Limpar tudo" com "Desfazer" (design A11, N2/N3)
-- ══════════════════════════════════════════════════════════════
--
-- NOVA, NÃO APLICADA. Aplicar manualmente via SQL Editor. Independente da
-- 0064. Pode correr-se mais do que uma vez.
--
-- 1. `notifications.cleared_at`: limpar não apaga logo. As notificações
--    limpas ficam escondidas (a app filtra-as) e ficam lidas, para o sino
--    deixar de as contar.
-- 2. `clear_my_notifications()`: limpa todas as notificações do próprio
--    (auth.uid(), nunca um id vindo da app) e devolve os ids limpos, para o
--    "Desfazer" dos 6 s. Aproveita para apagar de vez as que foram limpas há
--    mais de 1 dia, que já não se podem repor.
-- 3. `restore_my_notifications(p_ids)`: o "Desfazer". Só repõe notificações
--    do próprio que estejam limpas.
--
-- Trabalhos, pedidos e propostas não mudam: só a tabela notifications.
-- A app funciona sem esta migration (lê a coluna se existir); só o "Limpar
-- tudo" dá erro até ela ser aplicada.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS cleared_at timestamptz;

CREATE OR REPLACE FUNCTION public.clear_my_notifications()
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ids uuid[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  DELETE FROM notifications
  WHERE  user_id = v_uid
    AND  cleared_at IS NOT NULL
    AND  cleared_at < now() - interval '1 day';

  WITH cleared AS (
    UPDATE notifications
    SET    cleared_at = now(),
           read       = true
    WHERE  user_id = v_uid
      AND  cleared_at IS NULL
    RETURNING id
  )
  SELECT coalesce(array_agg(id), '{}') INTO v_ids FROM cleared;

  RETURN v_ids;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_my_notifications(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE notifications
  SET    cleared_at = NULL
  WHERE  user_id = v_uid
    AND  id = ANY (p_ids)
    AND  cleared_at IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.clear_my_notifications() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.restore_my_notifications(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_my_notifications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_my_notifications(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
