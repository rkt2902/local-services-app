-- ============================================================
-- 0034_helper_discovery_payment_and_message.sql
-- NOT APLICADA — aplicar manualmente via SQL Editor.
--
-- Contexto: hoje um worker candidata-se a um pedido de ajuda
-- (get_help_requests_in_radius) sem saber quanto vai receber nem em que
-- data/hora o trabalho está agendado — esses dados só aparecem depois de
-- aceite, via get_my_help_acceptances (migration 0022). Esta migration expõe
-- os dois campos ANTES da candidatura, e acrescenta um campo de mensagem
-- opcional do candidato para o principal.
--
-- 1) get_help_requests_in_radius — DROP + CREATE (não CREATE OR REPLACE):
--    RETURNS TABLE muda de shape (2 colunas novas), mesma restrição já
--    documentada para get_my_help_acceptances em 0022/0021.
--    Colunas novas:
--      - payment_per_helper: valor real que o candidato vai receber por
--        hora se aceite. Fórmula igual à já usada em
--        WorkerHelpRequestsLobbyScreen._suggestedRate (client-side, Dart) —
--        NÃO o factor 0.75 documentado em database_schema.md para a
--        estimativa de custo total mostrada ao cliente (esse é só uma
--        margem de exibição). Aqui replicamos a mesma regra do pagamento
--        real: se o pedido exige equipamento próprio do ajudante
--        (equipment_required = true), paga-se a taxa cheia; caso contrário,
--        70% da taxa — hoje `applyToHelpRequest` copia sempre
--        brought_equipment = equipment_required, por isso o valor é
--        determinístico nesta fase (antes de existir uma acceptance).
--      - confirmed_date / confirmed_time: horário já confirmado do job,
--        mesmas colunas que get_my_help_acceptances já expõe pós-aceitação.
--
-- 2) help_acceptances.message — coluna nova, nullable, sem default.
--    RLS: as policies existentes em help_acceptances são todas row-level
--    (worker_id = auth.uid() / is_principal_worker_for_help_request),
--    nenhuma restringe colunas específicas — a policy de INSERT
--    ("Worker candidata-se a help_request") só verifica worker_id e status,
--    por isso cobre a coluna nova sem alterações. Não é necessário tocar em
--    nenhuma policy.
-- ============================================================

-- ── 1. get_help_requests_in_radius ──────────────────────────────

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

-- ── 2. help_acceptances.message ─────────────────────────────────

ALTER TABLE help_acceptances ADD COLUMN IF NOT EXISTS message text;
