-- ══════════════════════════════════════════════════════════════
-- 0047 — Mensagem do candidato a ajudante visível ao principal
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor. Pode ser
-- aplicada várias vezes sem erro, antes ou depois da app nova (a app
-- nova lê a coluna se existir; a antiga ignora-a).
--
-- Contexto: a 0034 criou help_acceptances.message e o ecrã de
-- candidatura grava-a, mas get_candidates_for_help_request (0040) não a
-- devolvia, por isso o jardineiro principal nunca via o que o candidato
-- escreveu (ARCHITECTURE.md secção 16, ponto 4).
--
-- O RETURNS TABLE muda de forma (coluna nova), por isso DROP explícito
-- antes de recriar. Mesma autorização de sempre: só o principal do
-- pedido de ajuda (is_principal_worker_for_help_request, auth.uid()).
-- ══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_candidates_for_help_request(uuid);

CREATE FUNCTION public.get_candidates_for_help_request(p_help_request_id uuid)
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  worker_id         uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  worker_name       text,
  worker_avatar_url text,
  message           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.worker_id, ha.status, ha.agreed_rate,
    ha.brought_equipment, ha.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url,
    ha.message
  FROM   help_acceptances ha
  JOIN   profiles         p ON p.id = ha.worker_id
  WHERE  ha.help_request_id = p_help_request_id
    AND  is_principal_worker_for_help_request(p_help_request_id)
  ORDER BY ha.created_at ASC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_candidates_for_help_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_candidates_for_help_request(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
