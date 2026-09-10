-- ============================================================
-- 0036_profiles_cascade_and_confirm_backfill.sql
-- APLICADA — confirmado pelo utilizador via SQL Editor (2026-09-09).
--
-- Contexto: preparação para reativar "Confirm email" no Supabase no
-- futuro (hoje desativado — ver decisions_log.md 2026-06-05: "Confirmação
-- de email Supabase desativada para MVP — reativar antes do launch.").
-- Esta migration NÃO ativa a confirmação — só resolve dois problemas
-- estruturais que ficariam por resolver quando ela for ligada:
--
-- 1) profiles.id → auth.users(id): reforça ON DELETE CASCADE via DROP +
--    ADD CONSTRAINT (idempotente), em vez de confiar em que o corpo do
--    CREATE TABLE IF NOT EXISTS do baseline consolidado tenha sido
--    aplicado tal e qual à BD viva. Este projeto já teve mais que um
--    caso (migrations 0029, 0031, 0032) em que um FK declarado inline
--    num CREATE TABLE IF NOT EXISTS nunca chegou a existir em
--    pg_constraint porque a tabela já existia e o corpo foi saltado —
--    aplicar explicitamente aqui garante o estado certo independentemente
--    do que já lá está, sem ser preciso confirmar isso ao vivo primeiro.
--
-- 2) auth.users.email_confirmed_at — backfill para todos os utilizadores
--    já registados. Sem isto, no dia em que "Confirm email" for ligado no
--    dashboard, qualquer conta já criada (todas — foram todas criadas com
--    a definição desligada) ficaria bloqueada no login com
--    "email_not_confirmed" sem nunca ter recebido nenhum email de
--    confirmação. Isto não ativa a confirmação; só evita que a ativação
--    futura tranque retroativamente contas já existentes.
--
-- 3) Auditoria de outras FKs para auth.users — ver nota no fim do
--    ficheiro. Só profiles.id referencia auth.users diretamente; as
--    restantes tabelas de domínio já cascateiam via profiles(id), exceto
--    6 colunas de atribuição ("quem fez isto") deixadas deliberadamente
--    de fora — ver justificação abaixo.
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- 1. profiles.id → auth.users(id) ON DELETE CASCADE
-- ══════════════════════════════════════════════════════════════
--
-- Nome de constraint assumido pela convenção por omissão do Postgres para
-- uma FK de coluna única declarada inline (<tabela>_<coluna>_fkey) — o
-- mesmo padrão já usado nos FKs corrigidos em 0029/0032
-- (worker_profiles_profile_id_fkey, job_proposals_worker_id_fkey,
-- help_acceptances_worker_id_fkey). DROP CONSTRAINT IF EXISTS é seguro
-- mesmo que o nome já não bata certo ou a constraint não exista.

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

ALTER TABLE profiles
  ADD CONSTRAINT profiles_id_fkey
  FOREIGN KEY (id)
  REFERENCES auth.users(id)
  ON DELETE CASCADE;


-- ══════════════════════════════════════════════════════════════
-- 2. Backfill — utilizadores existentes marcados como confirmados
-- ══════════════════════════════════════════════════════════════

UPDATE auth.users
SET email_confirmed_at = now()
WHERE email_confirmed_at IS NULL;


-- ══════════════════════════════════════════════════════════════
-- 3. Outras FKs para auth.users — auditoria (Part 1.3)
-- ══════════════════════════════════════════════════════════════
--
-- profiles.id é o ÚNICO FK direto para auth.users em todo o schema —
-- confirmado por grep em 0001_consolidated_baseline.sql e no
-- archive/0001_baseline.sql original (mesma linha nos dois, nenhuma outra
-- ocorrência de "auth.users" em nenhuma migration). Todas as outras
-- tabelas (worker_profiles, job_requests, job_proposals, help_requests,
-- help_acceptances, notifications, job_photos, ratings, job_reports)
-- referenciam profiles(id), nunca auth.users(id) diretamente — profiles é
-- deliberadamente a única ponte entre o schema do Supabase Auth e o resto
-- do domínio (ver database_schema.md: "profiles: 1:1 com auth.users").
--
-- Como profiles.id agora cascata garantidamente para auth.users (passo 1
-- acima), qualquer FK "de posse" que já cascate para profiles(id) fica
-- coberto transitivamente sem precisar de alteração:
--   worker_profiles.profile_id, job_requests.client_id,
--   job_proposals.worker_id, help_requests.job_id/proposal_id,
--   help_acceptances.help_request_id/worker_id, notifications.user_id,
--   job_photos.job_id — todos já ON DELETE CASCADE na baseline.
--
-- NÃO alteradas — 6 colunas que apontam a profiles(id) SEM cascade
-- (comportamento por omissão NO ACTION, inalterado por esta migration):
--   job_requests.cancelled_by
--   job_requests.cancelled_worker_id
--   job_requests.reschedule_proposed_by
--   ratings.rater_id          (NOT NULL)
--   ratings.ratee_id          (NOT NULL)
--   job_reports.reporter_id   (NOT NULL)
--
-- Decisão: estas são colunas de ATRIBUIÇÃO ("quem fez isto"), não de
-- posse — ao contrário de client_id/worker_id/profile_id, apagar o
-- utilizador referenciado não deveria apagar em cascata um job_request ou
-- rating que pertence a OUTRA pessoa. CASCADE aqui destruiria dados de
-- terceiros por engano — ex.: apagar o worker que uma vez cancelou o job
-- de OUTRO cliente apagaria o job_request inteiro desse cliente, que nada
-- tem a ver com a conta apagada. SET NULL seria mais correto a prazo, mas
-- rater_id/ratee_id/reporter_id são NOT NULL — mudar isso é uma decisão
-- de schema à parte (dados a preservar como "utilizador apagado" vs.
-- anonimizar vs. impedir a operação), fora do âmbito desta migration.
--
-- Ficam como NO ACTION: apagar um utilizador referenciado numa destas 6
-- colunas falha explicitamente com um erro de FK em vez de apagar ou
-- corromper dados de outra pessoa silenciosamente — falha ruidosa é mais
-- segura que uma correção adivinhada às cegas. Não existe hoje nenhuma
-- funcionalidade de apagar conta na app (nada chama auth.admin.deleteUser
-- nem equivalente) — isto só passa a importar quando essa funcionalidade
-- for construída, e nessa altura é uma decisão de produto (cascade vs.
-- set null vs. anonimizar) a registar em decisions_log.md, não algo para
-- decidir silenciosamente aqui.
