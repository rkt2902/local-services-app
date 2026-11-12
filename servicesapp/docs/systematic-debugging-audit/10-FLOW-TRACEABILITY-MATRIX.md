# 10. Matriz de rastreabilidade

Cada um dos 80 fluxos aparece aqui uma vez, com o código principal, os testes automáticos, os bugs e os testes manuais. Um fluxo sem testes automáticos tem "nenhum" de forma explícita. A matriz é gerada da mesma lista que o 02, o 03 e o 05, por isso não há fluxos perdidos entre documentos.

| Fluxo | Estado | Código principal | Backend | Testes automáticos | Bugs | Testes manuais |
|---|---|---|---|---|---|---|
| FLOW-001 Onboarding (3 slides, primeira vez) | Estático | ProJardimOnboardingScreen, OnboardingPageIndicator, hasSeenOnboardingProvider | Nenhum (shared_preferences) | route_guard_test.dart | BUG-011 | TM-001 |
| FLOW-002 Registo com email e senha | Estático | SignupScreen, AppPasswordStrengthMeter, AuthRepository.signUp/createProfile | Supabase Auth signUp; profiles.upsert (RLS: só o próprio id) | T-PROF-04, labels_and_errors_test.dart | nenhum | TM-002, TM-003 |
| FLOW-003 Confirmação de email por código | Bloqueado | VerifyEmailScreen, AppOtpInput | Supabase Auth verifyOTP | app_toast_and_otp_test.dart | nenhum | TM-003 |
| FLOW-004 Login com email e senha | Estático | LoginScreen, AuthController, SessionNotifier, resolveRedirect | Supabase Auth signInWithPassword; profiles (SELECT próprio) | route_guard_test.dart, labels_and_errors_test.dart | nenhum | TM-004, TM-005 |
| FLOW-005 Login social Google/Facebook | Bloqueado | AuthRepository.signInWithSocial, importSocialAvatar | Supabase Auth OAuth; Storage avatars | social_sign_in_test.dart | nenhum | TM-006 |
| FLOW-006 Escolher papel (e telemóvel) | Auto: passou | ChooseRoleScreen, RegistrationIdentity | profiles (UPDATE próprio); trigger tg_prevent_profile_role_change | T-PROF-01, choose_role_phone_hint_test.dart | nenhum | TM-007 |
| FLOW-007 Setup do jardineiro (raio, base, serviços) | Auto: falhou | WorkerSetupScreen, GeocodingService, ServiceCategorySection | worker_profiles (UPSERT próprio), sync_worker_service_types | F-006a, F-006c, service_catalog_test.dart | BUG-006 | TM-008 |
| FLOW-008 Recuperar senha (OTP em 4 passos) | Bloqueado | RequestPasswordResetScreen, PasswordResetScreen, PasswordResetController | Supabase Auth | labels_and_errors_test.dart | nenhum | TM-009 |
| FLOW-009 Arranque e sessão (loading, restauro, erro de perfil) | Auto: passou | main.dart, SessionNotifier, RouterNotifier, SessionErrorScreen | profiles (SELECT próprio) | route_guard_test.dart | nenhum | TM-010 |
| FLOW-010 Terminar sessão | Estático | sign_out_flow.dart, AuthController.signOut, PushNotificationService.unregister | unregister_device_token; Supabase Auth | nenhum | nenhum | TM-011 |
| FLOW-011 Eliminar conta | Auto: passou | delete_account_flow.dart | check_can_delete_my_account, delete_my_account, trigger de bloqueio do email | T-DEL-02, T-DEL-03, T-DEL-04, T-DEL-05, account_actions_test.dart | nenhum | TM-012 |
| FLOW-012 Editar perfil do cliente (nome, telefone, foto) | Auto: falhou | ClientEditProfileScreen/View | profiles (UPDATE próprio), Storage avatars | F-008a, T-PROF-05, T-STOR-03, phone_utils_test.dart | BUG-008 | TM-013 |
| FLOW-013 Editar perfil do jardineiro (3 secções, destaques, links) | Auto: falhou | WorkerEditProfileScreen, worker_showcase_* | worker_profiles, sync_worker_service_types | worker_showcase_test.dart, worker_showcase_editor_test.dart | BUG-006, BUG-008 | TM-014 |
| FLOW-014 Guarda de rotas por papel | Auto: passou | route_guard.dart, app_router.dart | nenhum (a segurança real é a RLS) | route_guard_test.dart | nenhum | TM-015 |
| FLOW-020 Criar pedido (4 passos, rascunho, fotos) | Auto: falhou | ClientCreateJob*Screen, JobLocationPicker, JobRepository.createJob | INSERT job_requests (RLS), job_photos, Storage job-photos, trigger notify_workers_new_job | T-JOB-01, T-JOB-06, T-JOB-08, T-JOB-09, T-JOB-11, T-JOB-12, RACE-03, job_request_form_test.dart | BUG-002, BUG-003, BUG-005 | TM-016, TM-017 |
| FLOW-021 Limite de 5 pedidos por hora | Auto: passou | RLS de INSERT (client_recent_job_count) | job_requests | T-JOB-15 | nenhum | TM-017 |
| FLOW-022 Editar pedido aberto | Auto: passou | ClientEditJobScreen | update_job_request | T-EDIT-01, T-EDIT-02, T-EDIT-03, T-CANC-07 | nenhum | TM-018 |
| FLOW-023 Pedido sem propostas: alargar pesquisa e avisos | Auto: passou | client_job_detail_screen | widen_job_search, process_open_job_followups | T-EDIT-04, T-EDIT-05, T-CRON-05, job_followups_test.dart | nenhum | TM-019 |
| FLOW-024 Ver propostas recebidas (e recomendada) | Auto: passou | ClientProposalsScreen | get_pending_proposals_for_job | T-PROP-12, T-PROP-14, client_proposals_view_test.dart | nenhum | TM-020 |
| FLOW-025 Aceitar proposta | Auto: falhou | ClientProposalDetailScreen, ClientJobConfirmedScreen | accept_proposal (FOR UPDATE), triggers de plano, validade e pedido direto | T-PROP-17, T-PROP-22, RACE-01, RACE-02 | BUG-001, BUG-013 | TM-021 |
| FLOW-026 Recusar proposta | Estático | ClientProposalDetailScreen | reject_proposal (FOR UPDATE) | nenhum | nenhum | TM-021 |
| FLOW-027 Detalhe do pedido do cliente (por estado) | Auto: passou | ClientJobDetailScreen, JobFlowStepper, client_job_flow.dart | get_job_by_id, get_job_work_days, get_accepted_helpers_for_job | client_job_flow_test.dart, client_job_rules_test.dart | nenhum | TM-022 |
| FLOW-028 Confirmar conclusão | Auto: passou | ClientJobDetailScreen | confirm_job_completion (FOR UPDATE) | T-EXEC-15, T-EXEC-16 | nenhum | TM-023 |
| FLOW-029 Reportar problema depois de concluído | Estático | client_job_detail_screen (AppSheet) | INSERT job_reports (RLS), trigger notify_job_report | nenhum | BUG-008 | TM-024 |
| FLOW-030 Avaliar o jardineiro | Auto: passou | ClientRateWorkerScreen, RatingStarsInput | submit_client_rating | T-RATE-03, T-RATE-04a, T-RATE-04b | BUG-012 | TM-025 |
| FLOW-031 Cancelar pedido ou trabalho (e reabrir) | Auto: passou | Diálogo de cancelar | cancel_job (FOR UPDATE) | T-CANC-04, T-CANC-05, T-EXEC-08, job_dialogs_test.dart | nenhum | TM-026 |
| FLOW-032 Remarcar (propor, aceitar, recusar) | Auto: passou | Diálogo de remarcar | propose_reschedule, accept_reschedule, reject_reschedule | T-RESCH-03, T-RESCH-05, T-RESCH-06 | nenhum | TM-027 |
| FLOW-033 Pedir de novo (pedido direto, 24h) | Estático | client_create_job_*, direct_request presenters | trigger job_request_direct_before_insert, decline/release, expire_direct_job_requests | direct_request_test.dart | nenhum | TM-028 |
| FLOW-034 Pedido pelo cartão público /w/:id | Auto: passou | WorkerPublicProfileScreen, directRequestAuthStore | worker_public_card (anon), log_worker_card_visit, claim_worker_card_visit | T-CARD-01, T-CARD-03, card_direct_request_test.dart | nenhum | TM-029 |
| FLOW-035 Os teus jardineiros (anteriores) | Estático | client home widgets | get_my_previous_workers, get_repeat_hire_for_job | nenhum | nenhum | TM-028 |
| FLOW-036 Contacto por WhatsApp | Auto: passou | AppWhatsAppButton, phone_utils.dart | profiles.phone (RLS só com trabalho confirmado) | T-PROP-25, T-PROP-27, phone_utils_test.dart | nenhum | TM-030 |
| FLOW-037 Aprovar pedido de ajudantes (cliente) | Estático | client_job_detail_screen | approve_help_request, process_help_request_deadlines | team_flow_improvements_test.dart | nenhum | TM-031 |
| FLOW-038 Início e lista de pedidos do cliente | Auto: passou | ClientHomeScreen, ClientJobsScreen, NextStepRow | SELECT job_requests (próprios) | client_job_next_step_test.dart | nenhum | TM-022 |
| FLOW-039 Dicas da época (preferência) | Estático | Definições do cliente | get_my_notification_preferences, set_seasonal_tips, send_seasonal_campaigns | nenhum | nenhum | TM-032 |
| FLOW-040 Descobrir pedidos no raio | Auto: falhou | WorkerAvailableJobsScreen | get_jobs_in_radius (coordenadas vindas da app, raio limitado a 50) | T-DISC-01, T-DISC-06, T-DISC-07, T-DISC-08 | BUG-004 | TM-033 |
| FLOW-041 Detalhe da oportunidade (zona aproximada) | Auto: passou | WorkerJobDetailScreen/View | get_job_by_id, get_open_job_client_identity | T-DISC-02, T-DISC-03, T-PROP-26, worker_job_rules_test.dart | nenhum | TM-033 |
| FLOW-042 Enviar proposta (hora ou valor total) | Auto: falhou | WorkerSubmitProposalScreen, ProposalRepository.createProposal | create_proposal, triggers de plano, data passada e pedido direto | T-PROP-01, T-PROP-02, T-PROP-03, T-PROP-05, T-PROP-07, RACE-04, proposal_pricing_test.dart | BUG-007 | TM-034 |
| FLOW-043 Retirar proposta | Auto: falhou | worker_my_job_detail_screen | withdraw_proposal (sem FOR UPDATE) | T-PROP-23, RACE-02 | BUG-001 | TM-021 |
| FLOW-044 Recusar pedido direto ('Não posso desta vez') | Estático | worker_job_detail_screen | decline_direct_job_request | direct_request_test.dart | nenhum | TM-028 |
| FLOW-045 Os meus trabalhos (Agenda · Propostas · Histórico) | Auto: falhou | WorkerJobsScreen, worker_jobs_view | get_worker_job_board (0035) | worker_jobs_view_test.dart, worker_board_status_test.dart | BUG-001 | TM-035 |
| FLOW-046 Iniciar trabalho (fotos de antes) | Auto: passou | worker_my_job_detail_screen, job_start_flow | start_job (FOR UPDATE) | T-EXEC-01, T-EXEC-04, T-EXEC-06, T-EXEC-07, job_start_flow_test.dart | nenhum | TM-036 |
| FLOW-047 Trabalho por dias / vários dias | Estático | worker_my_job_detail_view, worker_todo | job_expected_end_date, get_job_work_days | worker_my_job_detail_view_test.dart, worker_todo_test.dart | nenhum | TM-037 |
| FLOW-048 Marcar como concluído (fotos de depois) | Auto: passou | worker_my_job_detail_screen | mark_job_done | T-EXEC-11, T-EXEC-12 | nenhum | TM-036 |
| FLOW-049 Avaliar cliente e ajudantes | Auto: passou | rating_sheet, helper_actions | submit_principal_rating, submit_helper_rating | T-RATE-07, T-RATE-08, T-RATE-09, T-RATE-10 | nenhum | TM-025 |
| FLOW-050 Pedir ajudantes e gerir a equipa | Auto: passou | WorkerHelpRequestsLobbyScreen | accept/reject_help_candidate, update_help_request_slots, cancel_help_request, remove_help_helper | T-HELP-06, T-HELP-07, T-HELP-08, help_lobby_team_test.dart | nenhum | TM-031 |
| FLOW-051 Candidatar-se como ajudante / desistir | Auto: passou | WorkerHelpRequestsScreen, ApplyAsHelperScreen | apply_to_help_request, withdraw_help_acceptance, get_help_requests_in_radius | T-HELP-01, T-HELP-03, T-HELP-04 | nenhum | TM-031 |
| FLOW-052 Trabalho visto pelo ajudante | Auto: passou | WorkerHelperJobScreen, helper_job_state | get_my_help_acceptances | T-HELP-09, helper_job_state_test.dart | nenhum | TM-031 |
| FLOW-053 Agenda (Hoje, Semana, Mês) | Auto: passou | WorkerAgendaTab, agenda_* | get_worker_agenda (máx. 62 dias) | T-AG-02, T-AG-03, agenda_day_view_test.dart | nenhum | TM-038 |
| FLOW-054 Agenda: adicionar, editar, apagar e séries | Auto: passou | AgendaEntryEditorScreen, AgendaEntryDetailScreen | worker_calendar_entries/exceptions (RLS do dono), split_calendar_series, free_calendar_day | T-AG-01, T-AG-04, T-AG-05, T-AG-06 | nenhum | TM-038 |
| FLOW-055 Cartão partilhável (QR, imagem, PDF, link) | Estático | WorkerShareCardScreen | worker_public_card | nenhum | nenhum | TM-039 |
| FLOW-056 Painel de ganhos (Pro) | Auto: passou | WorkerEarningsScreen, worker_earnings.dart | get_my_earnings (0067, por aplicar) | T-PLAN-03 | BUG-014 | TM-040 |
| FLOW-057 Plano e limite do Grátis | Auto: passou | WorkerProfileScreen | trg_enforce_free_plan_limit, get_my_plan | T-PLAN-01, T-PLAN-02, T-PLAN-04 | nenhum | TM-040 |
| FLOW-058 Cartão frota (demo, OCR) | Bloqueado | FleetCard*Screen, fleet_card_text_extractor | worker_fleet_cards (INSERT pending) | T-FLEET-01 | nenhum | TM-041 |
| FLOW-059 Lembretes de início e atraso (0072) | Estático | notification_handler | send_start_reminders (cron */5) | nenhum | nenhum | TM-042 |
| FLOW-060 Início do jardineiro (dashboard) | Auto: passou | WorkerDashboardScreen, TodoRow | get_worker_job_board, get_jobs_in_radius | worker_todo_test.dart | nenhum | TM-035 |
| FLOW-070 Lista de notificações (ler, filtros, limpar e desfazer) | Auto: passou | NotificationsScreen, AppNotificationsView | SELECT/UPDATE notifications, clear/restore_my_notifications | T-NOTIF-01, T-NOTIF-02, T-NOTIF-03, T-NOTIF-04, notifications_view_test.dart | nenhum | TM-043 |
| FLOW-071 Abrir o destino ao tocar numa notificação | Estático | notification_handler.dart | get_job_by_id, job_proposals | nenhum | nenhum | TM-044 |
| FLOW-072 Aviso no topo com a app aberta | Estático | app.dart, AppToast | Realtime notifications | nenhum | nenhum | TM-045 |
| FLOW-073 Push FCM | Bloqueado | PushNotificationService | register_device_token, send-push (Edge Function), pg_net, Vault | T-PUSH-01, T-PUSH-02, T-PUSH-03 | nenhum | TM-046, TM-047 |
| FLOW-074 As minhas avaliações (recebidas e dadas) | Estático | MyRatingsRoute | get_my_ratings_received/given | T-RATE-11 | BUG-009 | TM-025 |
| FLOW-075 Voltar, deep links e PopScope | Estático | app_back_navigation.dart, app_page_transitions.dart | nenhum | nenhum | nenhum | TM-044, TM-048 |
| FLOW-076 Contacto e suporte, Sobre, links legais | Auto: passou | AppSupportSheet, AppAboutDialog, app_legal_links.dart | nenhum | legal_links_test.dart | BUG-010 | TM-049 |
| FLOW-077 Uploads para o Storage (avatar e fotos) | Auto: passou | JobRepository, StorageUrls | storage.objects (RLS por pasta), buckets públicos | T-STOR-01, T-STOR-02, T-STOR-03, T-STOR-04 | nenhum | TM-050 |
| FLOW-078 Morada e GPS (Photon, Nominatim, geocoder nativo) | Bloqueado | GeocodingService, AddressSuggestionsList | APIs externas | nenhum | nenhum | TM-051 |
| FLOW-079 Erros, sem rede e timeouts | Auto: passou | error_utils.dart | nenhum | labels_and_errors_test.dart | nenhum | TM-052 |
| FLOW-080 Entrar no painel /admin (login + 2.º fator) | Auto: passou | AdminGateScreen | admin_whoami, assert_verified_admin | T-ADM-02, T-ADM-04, T-ADM-05 | nenhum | TM-053 |
| FLOW-081 Visão geral, lista e ficha de jardineiros | Auto: passou | AdminHomeScreen, AdminWorkerDetailScreen | admin_overview, admin_list_workers, admin_get_worker | T-ADM-05 | nenhum | TM-053 |
| FLOW-082 Atribuir plano a um jardineiro | Auto: passou | AdminWorkerDetailScreen | admin_set_worker_plan, admin_actions | T-ADM-06, T-ADM-07, T-ADM-08, T-PLAN-04 | nenhum | TM-053 |
| FLOW-090 Expirar pedidos e trabalhos (auto_expire_jobs) | Auto: falhou | nenhum | auto_expire_jobs (0 */3 * * *) | T-CRON-01, T-CRON-05, F-003c | BUG-003 | TM-054 |
| FLOW-091 Confirmação automática (48h; 7 dias com relato) | Auto: passou | nenhum | auto_confirm_completed_jobs (15 * * * *) | T-CRON-01, T-CRON-05 | nenhum | TM-054 |
| FLOW-092 Lembretes diários (send_job_reminders) | Auto: passou | nenhum | send_job_reminders (30 7 * * *) | T-CRON-01, T-CRON-05 | nenhum | TM-042 |
| FLOW-093 Fim da reserva do pedido direto | Auto: passou | nenhum | expire_direct_job_requests (*/5) | T-CRON-01, T-CRON-05 | nenhum | TM-028 |
| FLOW-094 Pedidos sem propostas (6h e 24h) | Auto: passou | nenhum | process_open_job_followups (15 * * * *) | T-CRON-01, T-CRON-05 | nenhum | TM-019 |
| FLOW-095 Prazos dos pedidos de ajuda | Auto: passou | nenhum | close_help_requests_on_job_day, process_help_request_deadlines | T-CRON-01, T-CRON-05 | nenhum | TM-031 |
| FLOW-096 Limpeza (notificações, emails bloqueados) | Auto: passou | nenhum | cleanup_old_notifications, cleanup_deleted_account_emails | T-CRON-01, T-CRON-05 | nenhum | TM-054 |
| FLOW-097 Dicas da época | Auto: passou | nenhum | send_seasonal_campaigns (0 10 * * *) | T-CRON-01, T-CRON-05 | nenhum | TM-032 |
| FLOW-098 Lembretes de início (0072) | Auto: passou | nenhum | send_start_reminders (*/5) | T-CRON-01, T-CRON-05 | nenhum | TM-042 |
| FLOW-099 Avisar jardineiros de pedidos e ajudas novos (triggers) | Auto: falhou | nenhum | notify_workers_new_job, job_candidate_workers, notify_workers_new_help_request | T-PROP-20, F-006c | BUG-006 | TM-046 |
| FLOW-100 Versão web (Netlify) | Bloqueado | deploy-web.yml, web/ | Mesmo Supabase | nenhum | BUG-014 | TM-055 |
| FLOW-101 Ações repetidas e concorrentes (transversal) | Auto: falhou | Botões com isLoading | FOR UPDATE nas RPCs | RACE-01, RACE-02, RACE-03, RACE-04 | BUG-001, BUG-005 | TM-056 |

## Bug → fluxos afetados

| Bug | Fluxos |
|---|---|
| BUG-001 | FLOW-025, FLOW-043, FLOW-045, FLOW-101 |
| BUG-002 | FLOW-020 |
| BUG-003 | FLOW-020, FLOW-090 |
| BUG-004 | FLOW-040 |
| BUG-005 | FLOW-020, FLOW-101 |
| BUG-006 | FLOW-007, FLOW-013, FLOW-099 |
| BUG-007 | FLOW-042 |
| BUG-008 | FLOW-012, FLOW-013, FLOW-029 |
| BUG-009 | FLOW-074 |
| BUG-010 | FLOW-076 |
| BUG-011 | FLOW-001 |
| BUG-012 | FLOW-030 |
| BUG-013 | FLOW-025 |
| BUG-014 | FLOW-056, FLOW-100 |

## Teste manual → fluxos

| Teste | Fluxos |
|---|---|
| TM-001 | FLOW-001 |
| TM-002 | FLOW-002 |
| TM-003 | FLOW-002, FLOW-003 |
| TM-004 | FLOW-004 |
| TM-005 | FLOW-004 |
| TM-006 | FLOW-005 |
| TM-007 | FLOW-006 |
| TM-008 | FLOW-007 |
| TM-009 | FLOW-008 |
| TM-010 | FLOW-009 |
| TM-011 | FLOW-010 |
| TM-012 | FLOW-011 |
| TM-013 | FLOW-012 |
| TM-014 | FLOW-013 |
| TM-015 | FLOW-014 |
| TM-016 | FLOW-020 |
| TM-017 | FLOW-020, FLOW-021 |
| TM-018 | FLOW-022 |
| TM-019 | FLOW-023, FLOW-094 |
| TM-020 | FLOW-024 |
| TM-021 | FLOW-025, FLOW-026, FLOW-043 |
| TM-022 | FLOW-027, FLOW-038 |
| TM-023 | FLOW-028 |
| TM-024 | FLOW-029 |
| TM-025 | FLOW-030, FLOW-049, FLOW-074 |
| TM-026 | FLOW-031 |
| TM-027 | FLOW-032 |
| TM-028 | FLOW-033, FLOW-035, FLOW-044, FLOW-093 |
| TM-029 | FLOW-034 |
| TM-030 | FLOW-036 |
| TM-031 | FLOW-037, FLOW-050, FLOW-051, FLOW-052, FLOW-095 |
| TM-032 | FLOW-039, FLOW-097 |
| TM-033 | FLOW-040, FLOW-041 |
| TM-034 | FLOW-042 |
| TM-035 | FLOW-045, FLOW-060 |
| TM-036 | FLOW-046, FLOW-048 |
| TM-037 | FLOW-047 |
| TM-038 | FLOW-053, FLOW-054 |
| TM-039 | FLOW-055 |
| TM-040 | FLOW-056, FLOW-057 |
| TM-041 | FLOW-058 |
| TM-042 | FLOW-059, FLOW-092, FLOW-098 |
| TM-043 | FLOW-070 |
| TM-044 | FLOW-071, FLOW-075 |
| TM-045 | FLOW-072 |
| TM-046 | FLOW-073, FLOW-099 |
| TM-047 | FLOW-073 |
| TM-048 | FLOW-075 |
| TM-049 | FLOW-076 |
| TM-050 | FLOW-077 |
| TM-051 | FLOW-078 |
| TM-052 | FLOW-079 |
| TM-053 | FLOW-080, FLOW-081, FLOW-082 |
| TM-054 | FLOW-090, FLOW-091, FLOW-096 |
| TM-055 | FLOW-100 |
| TM-056 | FLOW-101 |
