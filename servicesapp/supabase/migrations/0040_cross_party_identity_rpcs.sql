-- ============================================================
-- 0040_cross_party_identity_rpcs.sql
-- NOVA — NÃO APLICADA. Aplicar manualmente via SQL Editor.
--
-- Contexto: auditoria de foto/nome em falta nos dois sentidos (worker ↔
-- cliente), 2026-10-15. A migration 0032 (hardening de segurança, aplicada
-- 2026-09-09) substituiu a policy `USING(true)` de `profiles` por 3
-- policies granulares — correto para a maior parte da app, mas partiu
-- silenciosamente todo o código que lia nome/avatar da CONTRAPARTE através
-- de um embedded join do PostgREST (`profiles!<fk>(full_name, avatar_url)`)
-- fora das relações que essas 3 policies cobrem (dono do perfil; worker↔
-- cliente só depois de proposta `accepted`/job confirmado). Nenhum destes
-- 4 pontos foi testado de novo depois do hardening — o join passou a
-- devolver sempre `null`, sem erro, por isso ninguém reparou.
--
-- As 4 funções abaixo seguem o mesmo padrão já usado em
-- `get_help_requests_in_radius` (0039) e `get_worker_job_board` (0035):
-- SECURITY DEFINER, expõem SÓ nome+avatar (nunca telefone/coordenadas), e
-- replicam inline a mesma condição de autorização que a policy já exigia
-- para a linha "principal" — nunca um alargamento geral de `profiles`.
--
-- 1) get_open_job_client_identity — worker vê nome/avatar do cliente numa
--    oportunidade `open` (`WorkerJobDetailScreen`, "Pedidos disponíveis" →
--    detalhe). Autorização = a mesma condição da policy "Worker vê jobs
--    abertos" (status = 'open'); nunca telefone (esse só aparece depois de
--    confirmado, via `fetchClientBasicInfo` + a policy já existente).
--
-- 2) get_pending_proposals_for_job — cliente vê nome/avatar do worker nas
--    propostas AINDA pending ("Propostas recebidas",
--    `client_proposals_screen.dart`). Mesma condição da policy "Client vê
--    propostas dos seus jobs". Era o SELECT direto mais visível partido
--    pelo 0032 — exatamente onde o cliente mais precisa de ver quem
--    propôs, antes de decidir, e silenciosamente mostrava "—" desde então.
--
-- 3) get_candidates_for_help_request — worker principal vê nome/avatar de
--    cada candidato ajudante (`worker_help_requests_lobby_screen.dart`).
--    Mesma condição que a policy "Worker principal vê candidatos"
--    (`is_principal_worker_for_help_request`, reaproveitada diretamente).
--
-- 4) get_ratings_with_rater_identity — nome/avatar de quem avaliou um
--    worker (`showRatingsSheet`, usado em `client_proposals_screen.dart` e
--    nos ecrãs de candidatura de ajudante). `ratings` já é pública
--    (`USING(true)`) — só o nome do rater ficava bloqueado pela mesma
--    causa; esta função não adiciona NENHUMA restrição de autorização além
--    de "o ratee existe", porque a informação em si já era pública.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_open_job_client_identity(p_job_id uuid)
RETURNS TABLE(client_name text, client_avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.full_name, p.avatar_url
  FROM   job_requests jr
  JOIN   profiles     p ON p.id = jr.client_id
  WHERE  jr.id = p_job_id
    AND  jr.status = 'open';
$function$;

CREATE OR REPLACE FUNCTION public.get_pending_proposals_for_job(p_job_id uuid)
RETURNS TABLE(
  id                        uuid,
  job_id                    uuid,
  worker_id                 uuid,
  hourly_rate               numeric,
  estimated_hours_min       numeric,
  estimated_hours_max       numeric,
  people_needed             integer,
  helpers_equipment_required boolean,
  notes                     text,
  status                    text,
  scheduled_date            date,
  scheduled_time            time,
  scheduled_flexible        boolean,
  created_at                timestamptz,
  worker_name               text,
  worker_avatar_url         text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    jp.id, jp.job_id, jp.worker_id, jp.hourly_rate, jp.estimated_hours_min,
    jp.estimated_hours_max, jp.people_needed, jp.helpers_equipment_required,
    jp.notes, jp.status, jp.scheduled_date, jp.scheduled_time,
    jp.scheduled_flexible, jp.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url
  FROM   job_proposals jp
  JOIN   profiles      p ON p.id = jp.worker_id
  WHERE  jp.job_id = p_job_id
    AND  jp.status = 'pending'
    AND  EXISTS (
      SELECT 1 FROM job_requests jr
      WHERE jr.id = jp.job_id AND jr.client_id = auth.uid()
    )
  ORDER BY jp.created_at ASC;
$function$;

CREATE OR REPLACE FUNCTION public.get_candidates_for_help_request(p_help_request_id uuid)
RETURNS TABLE(
  id                uuid,
  help_request_id   uuid,
  worker_id         uuid,
  status            text,
  agreed_rate       numeric,
  brought_equipment boolean,
  created_at        timestamptz,
  worker_name       text,
  worker_avatar_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    ha.id, ha.help_request_id, ha.worker_id, ha.status, ha.agreed_rate,
    ha.brought_equipment, ha.created_at,
    p.full_name AS worker_name, p.avatar_url AS worker_avatar_url
  FROM   help_acceptances ha
  JOIN   profiles         p ON p.id = ha.worker_id
  WHERE  ha.help_request_id = p_help_request_id
    AND  is_principal_worker_for_help_request(p_help_request_id)
  ORDER BY ha.created_at ASC;
$function$;

CREATE OR REPLACE FUNCTION public.get_ratings_with_rater_identity(p_ratee_id uuid)
RETURNS TABLE(
  id               uuid,
  job_id           uuid,
  rater_id         uuid,
  ratee_id         uuid,
  stars            integer,
  comment          text,
  created_at       timestamptz,
  rater_name       text,
  rater_avatar_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    r.id, r.job_id, r.rater_id, r.ratee_id, r.stars, r.comment, r.created_at,
    p.full_name AS rater_name, p.avatar_url AS rater_avatar_url
  FROM   ratings  r
  JOIN   profiles p ON p.id = r.rater_id
  WHERE  r.ratee_id = p_ratee_id
  ORDER BY r.created_at DESC;
$function$;
