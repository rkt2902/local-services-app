# supabase/migrations

## Estado a 2026-10-27

**Todas as migrations deste diretório estão aplicadas na BD viva** (projeto
`twpflvcoyeiysnychkom`), confirmado pelo Henrique a 2026-10-27. Isto inclui a
`0065_notifications_clear_and_profile_stats.sql`. A `0050` nunca foi usada (o
número ficou reservado para uma thread que não chegou a criar a migration).

**Próxima migration nova: `0066`.** Antes de numerar, confirmar com
`ls servicesapp/supabase/migrations` no `main`, porque threads paralelas também criam
migrations.

O Claude Code nunca aplica migrations: só cria o `.sql`. O Henrique aplica-as no SQL
Editor do Supabase e confirma.

## Ficheiros

| Ficheiro | O que faz | Estado |
|---|---|---|
| `0001_consolidated_baseline.sql` | Schema completo da BD viva a 2026-07-09 (substitui `archive/`) | aplicada |
| `0033`–`0037` | Cartão público do worker, descoberta de ajudantes com pagamento, RPC única de "Os meus trabalhos", cascade de `profiles`, cartão frota | aplicadas (2026-09-09) |
| `0038`–`0040` | "As minhas avaliações", foto do principal nos pedidos de ajuda, 4 RPCs de identidade da contraparte | aplicadas (confirmado por dump a 2026-10-16) |
| `0041_push_notifications.sql` | `device_tokens`, registo de tokens, trigger que chama a Edge Function `send-push` | aplicada (2026-10-16) |
| `0042_security_hardening.sql` | Review de segurança: autorização em `cancel_job`/`reject_proposal`, escritas só por RPC, REVOKE a anon, índices | aplicada (2026-10-16) |
| `0043_job_location_privacy.sql` | Morada exata escondida até a proposta ser aceite (`location_area`, `get_job_by_id`) | aplicada (2026-10-16) |
| `0044_rpc_identity_and_policy_perf.sql` | RPCs sem `p_worker_id`, policies com `(SELECT auth.uid())` | aplicada (2026-10-17) |
| `0045_service_catalog.sql` | Jardinagem, Agricultura e Floresta, 33 tipos com ícone e ordem | aplicada (2026-10-17) |
| `0046_job_day_rules.sql` | Concluir só a partir do dia, foto de conclusão, expiração, lembretes | aplicada (2026-10-17) |
| `0047_candidate_message.sql` | Mensagem do candidato a ajudante no lobby | aplicada |
| `0048_worker_helper_flow_fixes.sql` | `apply_to_help_request`, avisos novos, histórico no quadro, telefone dos ajudantes | aplicada |
| `0049_pending_decisions.sql` | Eliminar conta, editar pedido, gestão da equipa, avisos com contexto, fecho aos 14 dias | aplicada |
| `0051_worker_showcase.sql` | Destaques e redes sociais do jardineiro | aplicada |
| `0052_job_start_flow.sql` | Iniciar trabalho, fotos de antes e depois, confirmação automática em 48h | aplicada |
| `0053_worker_jobs_board_cards.sql` | Colunas novas em `get_worker_job_board` (design A2) | aplicada |
| `0054_help_requests_job_day_and_alerts.sql` | Pedidos de ajuda fecham no dia, avisos só a quem faz o serviço | aplicada |
| `0055_team_flow_improvements.sql` | Equipa visível ao cliente, desistir até à véspera, aprovação automática em 24h | aplicada |
| `0056_worker_job_board_team_estimate.sql` | Total estimado com a equipa no quadro | aplicada |
| `0057_direct_requests.sql` | "Pedir de novo" ao mesmo jardineiro (reserva de 24h) | aplicada (2026-10-22) |
| `0058_proposal_pricing_and_work_days.sql` | Proposta por hora ou valor total, validade, dias de trabalho | aplicada |
| `0059_card_direct_requests_and_tracking.sql` | Pedido direto pelo cartão `/w/:id`, `on_hold`, visitas e clientes trazidos | aplicada |
| `0060_admin_and_worker_plans.sql` | Painel `/admin`, planos Grátis/Pro/Pro+, limite de 5 no Grátis | aplicada |
| `0061_hotfix_reserved_for_other.sql` | Corrige `job_reserved_for_other` (NULL escondia pedidos normais) | aplicada |
| `0062_job_followups_and_better_notifications.sql` | Lembrete às 6h, pedido mais longe às 24h, dicas da época, textos das notificações | aplicada |
| `0063_direct_context_fixed_price.sql` | "Já trabalhaste com..." com valor fechado | aplicada |
| `0064_worker_agenda.sql` | Agenda do jardineiro (trabalhos fora da app, indisponibilidades, `get_worker_agenda`) | aplicada |
| `0065_notifications_clear_and_profile_stats.sql` | "Limpar tudo" com "Desfazer", números do Perfil | aplicada (2026-10-27) |

O detalhe de cada uma está no cabeçalho do próprio ficheiro e em `docs/ARCHITECTURE.md`
secção 7.

## Regras

- Identidade sempre por `auth.uid()` dentro da função; nenhuma RPC recebe
  `worker_id`/`client_id`/`user_id` vindo da app (classe corrigida na 0032).
- `DROP FUNCTION` explícito antes de recriar quando o `RETURNS TABLE` muda de forma, ou
  quando a lista de parâmetros muda (senão fica um overload).
- Desde a 0042, cada função nova faz `REVOKE EXECUTE ... FROM PUBLIC, anon` e
  `GRANT EXECUTE ... TO authenticated` (o Postgres dá EXECUTE a PUBLIC por omissão).
- Escritas de negócio só por RPC.
- `RETURNING` com RLS precisa de policy de INSERT e de SELECT.
- Sublinks `(SELECT auth.uid())` nas policies de SELECT de `job_requests` dão recursão
  infinita no INSERT (ciclo `job_requests` → `profiles` → `job_requests`); não os pôr lá.
- As migrations recentes podem correr-se mais do que uma vez sem erro. Dá para as
  validar num Postgres 16 local com stubs de `auth`, `storage` e `cron`; a 0041 falha aí
  por falta de `pg_net`, o resto aplica.

## Projeto novo

1. Criar o projeto Supabase e ativar `pg_cron` (e `pg_net` + Vault para a 0041, ver
   `docs/push_notifications.md`).
2. Criar os buckets públicos `avatars` e `job-photos`.
3. Correr `0001_consolidated_baseline.sql` no SQL Editor. Não corre de uma vez num
   projeto vazio: 4 policies (linhas 384, 444, 572 e 587) usam funções helper criadas
   mais abaixo, na secção 7. Correr o ficheiro e depois de novo só essas 4 policies.
4. Correr `0033` a `0065` por ordem numérica.
5. `NOTIFY pgrst, 'reload schema';`

## Drift conhecido

O trigger em `job_requests` chama-se `on_job_created` na BD viva, mas a baseline
define-o como `trigger_notify_workers_new_job` (mesma função `notify_workers_new_job()`,
mesmo evento). Renomeado à mão no Studio em algum momento; só cosmético.

## Arquivo

`archive/` tem as 31 migrations incrementais originais (0001_baseline … 0032_audit_fixes),
só para histórico e git blame. **Não aplicar**: `0001_consolidated_baseline.sql`
substitui-as. A baseline foi consolidada a partir de `supabase/snapshot_tables.csv`
(2026-07-09), de `archive/0001_baseline.sql` (funções fora do snapshot, buckets, seed) e
de `archive/0032_audit_fixes.sql` (FKs, RPCs com verificação de identidade, trigger de
papel, índices, policies de `profiles`).
