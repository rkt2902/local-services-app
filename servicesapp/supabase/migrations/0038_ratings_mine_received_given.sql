-- ============================================================
-- 0038_ratings_mine_received_given.sql
-- NOVA — NÃO APLICADA. Aplicar manualmente via SQL Editor.
--
-- Contexto: novo ecrã "As minhas avaliações" (2 tabs — Recebidas/Dadas),
-- partilhado entre cliente e worker. Precisa de duas coisas que ainda não
-- existiam:
--   1) A lista de "avaliações dadas" (rater_id = utilizador atual) — não
--      existia nenhum método/RPC para isto, só o inverso (ratee_id).
--   2) Nome/foto de quem avaliou (ou de quem foi avaliado) + o serviço do
--      job, para os cards mostrarem contexto — não só estrelas e comentário
--      como o `ratings_sheet.dart` atual.
--
-- Porque RPC (SECURITY DEFINER) e não um SELECT direto do lado Dart:
-- `job_requests` só tem policy de SELECT para o cliente dono, para o
-- worker com proposta (`worker_has_proposal_for_job`) e para jobs `open`.
-- Um AJUDANTE aceite (help_acceptances) não tem NENHUMA policy de SELECT
-- em `job_requests` — o acesso dele a dados do job hoje é sempre via RPCs
-- SECURITY DEFINER (get_my_help_acceptances, get_accepted_helpers_for_job),
-- nunca um SELECT direto. Um ajudante também avalia e é avaliado (RC/
-- submit_helper_rating, submit_principal_rating) — se esta função fosse um
-- SELECT direto com embedded resource do PostgREST, o join a `job_requests`
-- devolvia sempre null para um ajudante a ver as suas próprias avaliações,
-- por causa desse gap de RLS pré-existente (não introduzido aqui, só
-- exposto por esta ser a primeira feature a precisar do join
-- ratings → job_requests do lado do utilizador comum). Uma RPC SECURITY
-- DEFINER evita o problema sem alargar a RLS de job_requests.
--
-- Segurança: nenhum parâmetro de identidade — filtra sempre por
-- auth.uid(), mesmo padrão já usado em get_worker_job_board (0035) e
-- get_my_help_acceptances. Não é possível pedir as avaliações de outra
-- pessoa através destas funções.
--
-- Sem agregação nova (avg/count): `worker_rating_summary` (migration 0024,
-- security_invoker) já agrega por `ratee_id` sem nenhum filtro de papel —
-- funciona identicamente para um client_id. Reutilizada tal como está
-- (ratingSummaryProvider(myOwnId) do lado Dart) — criar uma view paralela
-- só para o nome seria duplicação sem ganho funcional.
-- ============================================================

-- ── get_my_ratings_received ──────────────────────────────────
-- Avaliações onde o utilizador atual é o AVALIADO (ratee_id). Serve tanto
-- o cliente (avaliado pelo worker/ajudantes) como o worker/ajudante
-- (avaliado pelo cliente ou pelo principal).

CREATE OR REPLACE FUNCTION public.get_my_ratings_received()
RETURNS TABLE(
  id                 uuid,
  job_id             uuid,
  stars              integer,
  comment            text,
  created_at         timestamptz,
  party_id           uuid,
  party_name         text,
  party_avatar_url   text,
  service_type_name  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    r.id, r.job_id, r.stars, r.comment, r.created_at,
    r.rater_id      AS party_id,
    p.full_name     AS party_name,
    p.avatar_url    AS party_avatar_url,
    st.name         AS service_type_name
  FROM   ratings r
  JOIN   profiles p ON p.id = r.rater_id
  LEFT JOIN job_requests  jr ON jr.id = r.job_id
  LEFT JOIN service_types st ON st.id = jr.service_type_id
  WHERE  r.ratee_id = auth.uid()
  ORDER BY r.created_at DESC;
$function$;

-- ── get_my_ratings_given ─────────────────────────────────────
-- Avaliações onde o utilizador atual é quem AVALIA (rater_id). Serve o
-- cliente (avalia o worker) e o worker/ajudante (avalia o cliente ou os
-- ajudantes/o principal).

CREATE OR REPLACE FUNCTION public.get_my_ratings_given()
RETURNS TABLE(
  id                 uuid,
  job_id             uuid,
  stars              integer,
  comment            text,
  created_at         timestamptz,
  party_id           uuid,
  party_name         text,
  party_avatar_url   text,
  service_type_name  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    r.id, r.job_id, r.stars, r.comment, r.created_at,
    r.ratee_id      AS party_id,
    p.full_name     AS party_name,
    p.avatar_url    AS party_avatar_url,
    st.name         AS service_type_name
  FROM   ratings r
  JOIN   profiles p ON p.id = r.ratee_id
  LEFT JOIN job_requests  jr ON jr.id = r.job_id
  LEFT JOIN service_types st ON st.id = jr.service_type_id
  WHERE  r.rater_id = auth.uid()
  ORDER BY r.created_at DESC;
$function$;
