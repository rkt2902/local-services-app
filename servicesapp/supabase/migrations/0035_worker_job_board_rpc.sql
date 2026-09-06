-- ============================================================
-- 0035_worker_job_board_rpc.sql
-- NOT APLICADA — aplicar manualmente via SQL Editor.
--
-- Contexto: "Os meus trabalhos" (worker_jobs_screen.dart) mostrava 3 tabs
-- (Pendentes/Agendados/Concluídos) alimentadas só pelo papel de responsável
-- (job_proposals). Quando os trabalhos de ajudante (help_acceptances) foram
-- adicionados às mesmas tabs, a fusão foi feita client-side: a lista de
-- ajudante (sem paginação) era carregada inteira e anexada depois das
-- páginas de responsável — sem ordenação cronológica coerente entre as
-- duas fontes, e sem paginação real do lado do ajudante.
--
-- Esta migration substitui isso por uma única RPC que faz UNION ALL das
-- duas fontes, com paginação e ordenação verdadeiramente server-side.
--
-- Segurança: sem parâmetro p_worker_id — filtra sempre por auth.uid(),
-- exatamente como get_my_help_acceptances(). Migration 0032 corrigiu vários
-- RPCs (accept_proposal, create_proposal, sync_worker_service_types) que
-- aceitavam um p_worker_id espofável; esta função nasce já sem essa classe
-- de vulnerabilidade.
--
-- Mapeamento de bucket (idêntico à lógica client-side que substitui):
--   pending   — proposta pending                    | candidatura pending
--   scheduled — proposta accepted + job confirmed/awaiting_confirmation
--             | candidatura accepted + job confirmed/awaiting_confirmation
--   completed — proposta accepted + job completed    | candidatura accepted + job completed
--   (tudo o resto — rejected/superseded/cancelled — fica fora das 3 tabs,
--    igual ao comportamento anterior; candidaturas rejected/cancelled
--    continuam visíveis só em "As minhas candidaturas" → Histórico)
--
-- Ordenação por tab (chave partilhada entre as duas fontes sempre que
-- possível, para a lista ficar cronologicamente coerente):
--   pending   — created_at DESC (própria linha: proposta ou candidatura).
--               Mesma convenção já usada em fetchPendingWorkerProposals e
--               em get_my_help_acceptances.
--   scheduled — job_requests.confirmed_date ASC NULLS LAST, depois
--               confirmed_time ASC NULLS LAST. Coluna do job, portanto
--               naturalmente igual para responsável e ajudante do mesmo
--               job — não há ambiguidade a resolver.
--   completed — job_requests.updated_at DESC. Um job completed não sofre
--               mais nenhum UPDATE (mesma lógica já documentada em
--               state_machine.md para awaiting_confirmation), por isso
--               updated_at é um proxy fiável de "quando terminou". É uma
--               pequena mudança de comportamento face ao
--               fetchCompletedWorkerProposals antigo (ordenava por
--               job_proposals.created_at DESC — data da proposta, não da
--               conclusão); a nova ordem é mais correta para uma tab
--               "Concluídos" e, tal como confirmed_date, é uma coluna do
--               job — igual para as duas fontes.
--
-- total_count: COUNT(*) OVER() sobre o conjunto já filtrado pelo bucket,
-- antes do LIMIT/OFFSET — dá ao Flutter o total exato da tab sem query
-- extra, para os badges das tabs continuarem exatos com paginação real
-- (antes, Pendentes/Agendados não eram paginadas — o badge era sempre
-- exato só porque a lista vinha inteira; passar a paginar sem isto
-- degradaria o badge para "quantos já carreguei", não o total real).
-- ============================================================

CREATE FUNCTION public.get_worker_job_board(
  p_tab       text,
  p_page      integer DEFAULT 0,
  p_page_size integer DEFAULT 20
)
RETURNS TABLE(
  entry_id             uuid,
  role                 text,
  job_id               uuid,
  service_type_name    text,
  person_name          text,
  address_text         text,
  preferred_date       date,
  confirmed_date       date,
  confirmed_time       time,
  confirmed_flexible   boolean,
  hourly_rate          numeric,
  estimated_hours_min  numeric,
  estimated_hours_max  numeric,
  agreed_rate          numeric,
  status               text,
  created_at           timestamptz,
  total_count          bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH combined AS (
    -- Fonte A: papel de responsável (job_proposals)
    SELECT
      jp.id                    AS entry_id,
      'responsible'::text      AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      cp.full_name             AS person_name,
      jr.address_text          AS address_text,
      jr.preferred_date        AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      jp.hourly_rate           AS hourly_rate,
      jp.estimated_hours_min   AS estimated_hours_min,
      jp.estimated_hours_max   AS estimated_hours_max,
      NULL::numeric            AS agreed_rate,
      jp.status                AS status,
      jp.created_at            AS created_at,
      jr.updated_at            AS job_updated_at,
      CASE
        WHEN jp.status = 'pending' THEN 'pending'
        WHEN jp.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN jp.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE NULL
      END AS bucket
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    JOIN   service_types st ON st.id = jr.service_type_id
    JOIN   profiles      cp ON cp.id = jr.client_id
    WHERE  jp.worker_id = auth.uid()

    UNION ALL

    -- Fonte B: papel de ajudante (help_acceptances)
    SELECT
      ha.id                    AS entry_id,
      'helper'::text           AS role,
      jr.id                    AS job_id,
      st.name                  AS service_type_name,
      pp.full_name             AS person_name,
      jr.address_text          AS address_text,
      NULL::date               AS preferred_date,
      jr.confirmed_date        AS confirmed_date,
      jr.confirmed_time        AS confirmed_time,
      jr.confirmed_flexible    AS confirmed_flexible,
      NULL::numeric            AS hourly_rate,
      NULL::numeric            AS estimated_hours_min,
      NULL::numeric            AS estimated_hours_max,
      ha.agreed_rate           AS agreed_rate,
      ha.status                AS status,
      ha.created_at            AS created_at,
      jr.updated_at            AS job_updated_at,
      CASE
        WHEN ha.status = 'pending' THEN 'pending'
        WHEN ha.status = 'accepted' AND jr.status IN ('confirmed', 'awaiting_confirmation') THEN 'scheduled'
        WHEN ha.status = 'accepted' AND jr.status = 'completed' THEN 'completed'
        ELSE NULL
      END AS bucket
    FROM   help_acceptances ha
    JOIN   help_requests hr  ON hr.id = ha.help_request_id
    JOIN   job_requests  jr  ON jr.id = hr.job_id
    JOIN   service_types st  ON st.id = jr.service_type_id
    JOIN   job_proposals jpp ON jpp.id = hr.proposal_id
    JOIN   profiles      pp  ON pp.id  = jpp.worker_id
    WHERE  ha.worker_id = auth.uid()
  )
  SELECT
    entry_id, role, job_id, service_type_name, person_name, address_text,
    preferred_date, confirmed_date, confirmed_time, confirmed_flexible,
    hourly_rate, estimated_hours_min, estimated_hours_max, agreed_rate,
    status, created_at,
    COUNT(*) OVER ()::bigint AS total_count
  FROM combined
  WHERE bucket = p_tab
  ORDER BY
    CASE WHEN p_tab = 'scheduled' THEN confirmed_date END ASC NULLS LAST,
    CASE WHEN p_tab = 'scheduled' THEN confirmed_time END ASC NULLS LAST,
    CASE WHEN p_tab = 'completed' THEN job_updated_at END DESC NULLS LAST,
    CASE WHEN p_tab = 'pending'   THEN created_at     END DESC NULLS LAST,
    entry_id
  LIMIT p_page_size OFFSET (p_page * p_page_size);
$function$;
