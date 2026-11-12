# 06. Dependências e testes de regressão

## Componentes partilhados com mais impacto

| Componente | Onde vive | Usado por | Uma falha aqui parte |
|---|---|---|---|
| `resolveRedirect` / `RouterNotifier` | `core/router/route_guard.dart` | todas as rotas | todos os fluxos (FLOW-001 a 101) |
| `SessionNotifier` / `sessionStatusProvider` | `features/auth/application/session_provider.dart` | router, ecrãs de topo | arranque, login, papel (FLOW-004, 006, 009, 014) |
| `friendlyError` / `isNetworkError` | `core/utils/error_utils.dart` | todos os ecrãs com ações | mensagens de erro (FLOW-079 e todos) |
| `AppToast` | `core/widgets/app_toast.dart` | todas as ações; avisos com a app aberta | feedback (FLOW-072 e todos) |
| `goBackOrToRoleHome` + `PopScope` dos builders | `core/router/app_back_navigation.dart`, `app_page_transitions.dart` | todas as rotas fora das shells | voltar (FLOW-075, 071) |
| `notificationSyncProvider` | `features/notifications/application/notification_providers.dart` | invalida providers por tipo de aviso | listas atualizadas em todos os fluxos de trabalho |
| `notification_handler.dart` | idem | toque em aviso, push | FLOW-071, 073 |
| `serviceTypesProvider` | `features/jobs` | criar pedido, setup, filtros, cartão | FLOW-007, 020, 040, 055 |
| `jobByIdProvider` / `get_job_by_id` | `features/jobs` + RPC | todos os detalhes de trabalho | FLOW-027, 041, 046..052 |
| `get_worker_job_board` | RPC 0035 | Início e Trabalhos do jardineiro | FLOW-045, 060 |
| `mask_job_location` / `can_see_exact_job_location` | SQL | descoberta, detalhe, RLS de `job_requests` e `job_photos` | privacidade da morada (FLOW-040, 041, 025) |
| `notifications_add_job_context` (trigger) | SQL 0062 | todos os textos de avisos | FLOW-070..073 |
| `notifications_send_push` (trigger) | SQL 0041 | todos os avisos | FLOW-073 |
| `today_pt()`, `job_expected_end_date` | SQL | regras de datas, crons, avisos | FLOW-031, 032, 046, 047, 059, 090, 091 |
| Triggers de pedido direto (0057, 0059, 0073) | SQL | INSERT de pedidos e propostas | FLOW-020, 025, 033, 034, 042, 093 |

## Estado global

- Sessão Supabase (token local) e `SessionStatus`.
- Cache por TTL (`cacheFor`) em providers de identidade e do trabalho (45 s a 5 min).
- Rascunho do pedido do cliente (persistido localmente).
- `hasSeenOnboarding` e o contexto do pedido direto pelo cartão (`directRequestAuthStore`) em `shared_preferences`.

## Operações com impacto na BD (efeitos secundários)

| Ação | Mexe em | Efeitos que disparam |
|---|---|---|
| Criar pedido | `job_requests`, `job_photos` | aviso aos jardineiros no raio (trigger), reserva do pedido direto, push |
| `accept_proposal` | pedido, todas as propostas, `help_requests` | avisos a todos os propostos, pedido de ajudantes, plano (`accepted_at`) |
| `cancel_job` | pedido, propostas, pedidos de ajuda, novo pedido reaberto | avisos a cliente, jardineiro e ajudantes; cópia de fotos |
| `start_job` / `mark_job_done` | pedido, `job_work_days` | avisos à cliente e ajudantes, fecho de pedidos de ajuda |
| `confirm_job_completion` / cron | pedido | avisos, ganhos, avaliações ficam disponíveis |
| `delete_my_account` | perfil, pedidos, propostas, tokens, agenda, planos, visitas | fecha pedidos e propostas, bloqueia o email 90 dias |
| `admin_set_worker_plan` | `worker_plans`, `admin_actions` | limite do Grátis, selo, painel de ganhos |

## Jobs do pg_cron (11)

| Job | Horário | Função |
|---|---|---|
| auto-confirm-completed-jobs | `15 * * * *` | `auto_confirm_completed_jobs` |
| auto-expire-jobs | `0 */3 * * *` | `auto_expire_jobs` |
| cleanup-deleted-account-emails | `45 3 * * *` | `cleanup_deleted_account_emails` |
| cleanup-old-notifications | `30 3 * * *` | `cleanup_old_notifications` |
| close-help-requests-on-job-day | `5 * * * *` | `close_help_requests_on_job_day` |
| expire-direct-job-requests | `*/5 * * * *` | `expire_direct_job_requests` |
| job-reminders | `30 7 * * *` | `send_job_reminders` |
| job-start-reminders | `*/5 * * * *` | `send_start_reminders` (0072, por aplicar) |
| open-job-followups | `15 * * * *` | `process_open_job_followups` |
| process-help-request-deadlines | `10 * * * *` | `process_help_request_deadlines` |
| seasonal-campaigns | `0 10 * * *` | `send_seasonal_campaigns` |

## Matriz: correção → regressão obrigatória

Depois de cada correção de 08, correr sempre `flutter analyze`, `flutter test` e `bash supabase/tests/audit/run.sh` (tem de continuar a 156 PASS mais as que a correção fizer passar). Além disso:

| Correção | Cenários automáticos | Fluxos a rever | Testes manuais |
|---|---|---|---|
| BUG-001 (`withdraw_proposal`) | RACE-02, T-PROP-17..23, cenários `p9_direct*` da parte 5 | 025, 033, 043, 045 | TM-021, TM-028 |
| BUG-002 (campos de execução no INSERT) | T-JOB-01..16, F-002, T-EXEC-*, `flow.sql` | 020, 031, 046, 048 | TM-016, TM-036 |
| BUG-003 (data fixa no passado) | T-JOB-08, F-003, T-EDIT-03 | 020, 022, 090 | TM-016, TM-017 |
| BUG-004 (descoberta) | T-DISC-01..08, T-PROP-24..26 | 040, 041, 060, 094 | TM-033 |
| BUG-005 (fotos em paralelo) | RACE-03, T-JOB-09..12 | 020, 031 (cópia das fotos ao reabrir) | TM-016 |
| BUG-006 (raio) | F-006, T-PROP-20 | 007, 013, 040, 099 | TM-008 |
| BUG-007 (horas) | T-PROP-01..11, F-007 | 042, 056 | TM-034 |
| BUG-008 (limites de texto) | F-008, T-PROF-*, perfil e relatos | 012, 013, 029 | TM-013, TM-024 |
| BUG-009 (ratings anónimos) | T-RATE-11, T-CARD-01 | 034, 074 | TM-029, TM-025 |
| BUG-010 / BUG-011 (app) | `legal_links_test`, `flutter analyze` | 076, 001 | TM-049, TM-001 |
| BUG-012 (avaliar 2 vezes) | T-RATE-03..06 | 030, 049 | TM-025 |
| BUG-013 (texto do erro) | teste novo de mapeamento | 025 | TM-021 |
| BUG-014 (aplicar 0067 a 0073) | `run.sh` (migrations numa BD vazia) | todos | todos os P0, TM-054 |

## Propagação entre fluxos (o que um problema arrasta)

- Um erro em `accept_proposal` ou `withdraw_proposal` propaga-se para Agenda, lembretes, ganhos, avaliações e pedidos de ajuda (BUG-001).
- Um erro nas datas (`today_pt`, `job_expected_end_date`) muda o que os crons fazem a trabalhos reais: expirar, confirmar, avisar.
- Qualquer mudança de forma de uma RPC sem `DROP FUNCTION` deixa overloads; o `rpccheck.py` dos relatórios de 02/11 e o `run.sh` apanham-no.
- Uma mudança nos triggers de notificação muda textos e pushes de todos os fluxos.
