-- ============================================================
-- 0039_help_request_principal_avatar.sql
-- NOVA — NÃO APLICADA. Aplicar manualmente via SQL Editor.
--
-- Contexto: auditoria de avatar/nome em falta (2026-09-28) encontrou que o
-- card de descoberta de pedidos de ajuda (_HelpRequestCard, tab "Descobrir"
-- de worker_help_requests_screen.dart) já renderiza um UserAvatarWithName
-- para o worker principal, mas get_help_requests_in_radius nunca devolveu
-- o avatar_url — apesar de já fazer JOIN a `profiles p` para o full_name.
-- O card mostrava sempre o placeholder de inicial, nunca a foto real.
--
-- DROP + CREATE (não CREATE OR REPLACE): RETURNS TABLE muda de shape (1
-- coluna nova), mesma restrição já documentada em 0022/0021/0034 para as
-- RPCs irmãs desta família.
--
-- Fora de âmbito desta migration (decisão deliberada, ver relatório da
-- auditoria): get_my_help_acceptances / HelpAcceptanceSummary (tab "As
-- minhas candidaturas", _PendingCard/_AcceptedCard) não têm nenhum círculo
-- de avatar no layout — mostram o principal via ícone+texto (_Meta), não
-- via UserAvatarWithName. Não há aqui um placeholder vazio a corrigir,
-- por isso esta migration não mexe nessa RPC.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_help_requests_in_radius(double precision, double precision, integer);

CREATE FUNCTION public.get_help_requests_in_radius(
  worker_lat double precision,
  worker_lng double precision,
  radius_km  integer
)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  proposal_id               uuid,
  slots_needed              integer,
  status                    text,
  equipment_required        boolean,
  created_post_confirmation boolean,
  created_at                timestamptz,
  location_lat              double precision,
  location_lng              double precision,
  service_type_id           uuid,
  principal_name            text,
  principal_avatar_url      text,
  payment_per_helper        numeric,
  confirmed_date            date,
  confirmed_time            time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
    hr.equipment_required, hr.created_post_confirmation, hr.created_at,
    jr.location_lat::double precision, jr.location_lng::double precision,
    jr.service_type_id, p.full_name AS principal_name,
    p.avatar_url AS principal_avatar_url,
    CASE WHEN hr.equipment_required THEN jp.hourly_rate
         ELSE jp.hourly_rate * 0.7
    END AS payment_per_helper,
    jr.confirmed_date, jr.confirmed_time
  FROM   help_requests  hr
  JOIN   job_requests   jr ON jr.id = hr.job_id
  JOIN   job_proposals  jp ON jp.id = hr.proposal_id
  JOIN   profiles        p ON p.id  = jp.worker_id
  WHERE  hr.status = 'open'
    AND  jr.status NOT IN ('cancelled', 'completed')
    AND  jp.worker_id <> auth.uid()
    AND  NOT EXISTS (
      SELECT 1 FROM help_acceptances ha
      WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid()
    )
    AND (
      2 * 6371 * asin(sqrt(
        power(sin(radians((jr.location_lat::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(jr.location_lat::double precision))
          * power(sin(radians((jr.location_lng::double precision - worker_lng) / 2)), 2)
      )) <= radius_km
    );
$function$;
