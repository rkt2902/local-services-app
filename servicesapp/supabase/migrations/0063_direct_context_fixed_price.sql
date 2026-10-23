-- 0063: "Já trabalhaste com..." mostra o valor fechado quando o trabalho
-- anterior foi a valor total (0058).
--
-- Até aqui `get_direct_request_context` (0057) devolvia só `hourly_rate`,
-- que num trabalho a valor fechado é a taxa de referência interna (o total
-- a dividir pelas horas da equipa) e nunca devia aparecer. Agora devolve
-- também `pricing_mode` e `total_price`; a app escolhe o que mostrar.
--
-- RETURNS TABLE muda de forma: DROP explícito antes de recriar.
-- Aplicar depois da 0058. Pode correr-se mais do que uma vez.

DROP FUNCTION IF EXISTS public.get_direct_request_context(uuid);

CREATE FUNCTION public.get_direct_request_context(p_job_id uuid)
RETURNS TABLE(
  client_name     text,
  job_date        date,
  service_type_id uuid,
  hourly_rate     numeric,
  pricing_mode    text,
  total_price     numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.full_name,
         COALESCE(src.confirmed_date, src.updated_at::date),
         src.service_type_id,
         jp.hourly_rate,
         jp.pricing_mode,
         jp.total_price
  FROM   job_requests  jr
  JOIN   job_requests  src ON src.id = jr.direct_source_job_id
  JOIN   job_proposals jp  ON jp.id  = src.accepted_proposal_id
                          AND jp.worker_id = auth.uid()
  LEFT JOIN profiles   p   ON p.id   = jr.client_id
  WHERE  jr.id = p_job_id
    AND  jr.direct_worker_id = auth.uid();
$function$;

REVOKE EXECUTE ON FUNCTION public.get_direct_request_context(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_direct_request_context(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
