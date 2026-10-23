-- 0061: correção urgente de job_reserved_for_other (aplicar já, sozinha).
--
-- O problema (desde a 0057, aplicada a 22/10): num pedido normal
-- direct_status é NULL, a função devolve NULL em vez de false, e
-- `NOT job_reserved_for_other(...)` também dá NULL. Resultado: os pedidos
-- normais deixaram de aparecer aos jardineiros (get_jobs_in_radius),
-- can_see_job_summary dá false e get_open_job_client_identity não devolve
-- nada. Só os pedidos que já passaram por pedido direto (released,
-- expired, declined) continuavam visíveis.
--
-- A correção é só embrulhar a expressão em COALESCE(..., false). Serve
-- antes e depois da 0059: se já existe a versão de 5 argumentos (0059),
-- corrige essa; senão corrige a de 4 (0057). Nunca cria as duas, que
-- deixaria as chamadas de 4 argumentos ambíguas. Pode correr mais vezes.

DO $do$
BEGIN
  IF to_regprocedure('public.job_reserved_for_other(text, timestamptz, uuid, uuid, boolean)') IS NOT NULL THEN
    EXECUTE $f$
      CREATE OR REPLACE FUNCTION public.job_reserved_for_other(
        p_direct_status       text,
        p_direct_until        timestamptz,
        p_direct_worker_id    uuid,
        p_worker_id           uuid,
        p_direct_auto_release boolean DEFAULT true
      )
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SET search_path TO 'public'
      AS $b$
        SELECT COALESCE(
          p_direct_worker_id IS DISTINCT FROM p_worker_id
           AND (
             (p_direct_status = 'waiting'
               AND (p_direct_until > now() OR NOT COALESCE(p_direct_auto_release, true)))
             OR p_direct_status = 'on_hold'
           ),
          false);
      $b$;
    $f$;
  ELSE
    EXECUTE $f$
      CREATE OR REPLACE FUNCTION public.job_reserved_for_other(
        p_direct_status    text,
        p_direct_until     timestamptz,
        p_direct_worker_id uuid,
        p_worker_id        uuid
      )
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SET search_path TO 'public'
      AS $b$
        SELECT COALESCE(
          p_direct_status = 'waiting'
           AND p_direct_until  > now()
           AND p_direct_worker_id IS DISTINCT FROM p_worker_id,
          false);
      $b$;
    $f$;
  END IF;
END
$do$;

-- Verificação: tem de dar false (pedido normal, sem pedido direto).
-- SELECT public.job_reserved_for_other(NULL, NULL, NULL, gen_random_uuid());
