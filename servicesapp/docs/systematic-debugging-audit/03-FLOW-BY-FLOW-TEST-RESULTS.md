# 03. Resultados fluxo a fluxo

Como ler o estado de cada fluxo:

- **TESTADO AUTOMATICAMENTE — PASSOU**: o backend do fluxo (RPCs, RLS, triggers) foi executado numa BD Postgres 16 local montada com as migrations 0001 a 0073, a fazer de app (papel `authenticated`, `auth.uid()` de cada pessoa), e as asserções passaram. A lógica e as vistas Flutter do fluxo, quando existem testes, também passaram em `flutter test`. **Não** quer dizer que o ecrã foi aberto num telemóvel: a UI real não foi executada (sem emulador nem Supabase real neste ambiente).
- **TESTADO AUTOMATICAMENTE — FALHOU**: pelo menos uma asserção falhou e o problema está registado em 04-BUG-REPORT.md.
- **ANALISADO ESTATICAMENTE**: só leitura de código, ou coberto por cenários de revisões anteriores que não repeti nesta bateria.
- **BLOQUEADO**: depende de um serviço real que não existe aqui (email, OAuth, FCM, GPS, OCR, APIs externas, Netlify).
- **NÃO TESTADO**: não houve nenhuma verificação.

Nenhum fluxo foi testado manualmente nesta auditoria (sem dispositivo). Mocks: nenhum nos testes da BD; os stubs de `auth`, `storage`, `cron`, `vault` e `pg_net` substituem os serviços do Supabase e estão em `supabase/tests/audit/stubs.sql`. Os testes Flutter usam dados falsos nas vistas puras, sem rede.

## Resumo

| Estado | Fluxos |
|---|---|
| TESTADO AUTOMATICAMENTE — PASSOU | 43 |
| TESTADO AUTOMATICAMENTE — FALHOU | 12 |
| ANALISADO ESTATICAMENTE | 18 |
| BLOQUEADO | 7 |
| NÃO TESTADO | 0 |
| **Total** | **80** |

## Comandos e evidência

```bash
cd servicesapp
flutter analyze                       # No issues found (evidence/flutter-analyze.txt)
flutter test                          # 621 testes, todos passam (evidence/flutter-test.txt)
bash supabase/tests/audit/run.sh keep # 162 asserções: 156 passam, 6 falham (evidence/bd-10_flows.txt)
psql -d pj_audit -f supabase/tests/audit/30_findings.sql   # reprodução dos bugs (evidence/bd-30_findings.txt)
bash supabase/tests/audit/20_concurrency.sh                # corridas entre 2 sessões (evidence/bd-20_concurrency.txt)
```

As 41 migrations (0001, 0033 a 0049, 0051 a 0073) aplicam sem erro numa BD vazia, por ordem. A única linha retirada é `CREATE EXTENSION pg_net`, substituída por um stub.

## Fluxo a fluxo

### FLOW-001: Onboarding (3 slides, primeira vez)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** n/a
- **App (Flutter):** route_guard_test (redirect para /onboarding)
- **Testes automáticos:** route_guard_test.dart
- **Bugs:** BUG-011
- **Testes manuais pendentes:** TM-001

### FLOW-002: Registo com email e senha

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** T-PROF-04 (não cria perfil de outro id) passou
- **App (Flutter):** política de senha e mensagens de erro testadas
- **Testes automáticos:** T-PROF-04, labels_and_errors_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-002, TM-003

### FLOW-003: Confirmação de email por código

- **Estado:** BLOQUEADO
- **Backend (BD local):** n/a (Auth não existe na BD local)
- **App (Flutter):** AppOtpInput testado em app_toast_and_otp_test
- **Testes automáticos:** app_toast_and_otp_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-003
- **Nota:** Precisa de email real.

### FLOW-004: Login com email e senha

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** n/a
- **App (Flutter):** resolveRedirect testado (35 testes)
- **Testes automáticos:** route_guard_test.dart, labels_and_errors_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-004, TM-005

### FLOW-005: Login social Google/Facebook

- **Estado:** BLOQUEADO
- **Backend (BD local):** n/a
- **App (Flutter):** lógica de decisão testada em social_sign_in_test
- **Testes automáticos:** social_sign_in_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-006
- **Nota:** Precisa de contas e dispositivo reais.

### FLOW-006: Escolher papel (e telemóvel)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-PROF-01 (não muda o papel) passou
- **App (Flutter):** choose_role_phone_hint_test
- **Testes automáticos:** T-PROF-01, choose_role_phone_hint_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-007

### FLOW-007: Setup do jardineiro (raio, base, serviços)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** F-006: raio 5000 km aceite pela API e usado nos avisos
- **App (Flutter):** service_catalog_test, service_category_section_test
- **Testes automáticos:** F-006a, F-006c, service_catalog_test.dart
- **Bugs:** BUG-006
- **Testes manuais pendentes:** TM-008

### FLOW-008: Recuperar senha (OTP em 4 passos)

- **Estado:** BLOQUEADO
- **Backend (BD local):** n/a
- **App (Flutter):** estados de erro testados em labels_and_errors_test
- **Testes automáticos:** labels_and_errors_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-009
- **Nota:** Bypass em debug confirmado só com kDebugMode (auth_repository.dart:286).

### FLOW-009: Arranque e sessão (loading, restauro, erro de perfil)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** n/a
- **App (Flutter):** resolveRedirect testado (incl. profileLoadFailed)
- **Testes automáticos:** route_guard_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-010

### FLOW-010: Terminar sessão

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** n/a
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-011

### FLOW-011: Eliminar conta

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-DEL-01..05 passaram
- **App (Flutter):** account_actions_test
- **Testes automáticos:** T-DEL-02, T-DEL-03, T-DEL-04, T-DEL-05, account_actions_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-012
- **Nota:** Fotos no Storage ficam (decisão registada a 18/10).

### FLOW-012: Editar perfil do cliente (nome, telefone, foto)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** F-008: nome com 100 000 caracteres aceite
- **App (Flutter):** phone_utils_test
- **Testes automáticos:** F-008a, T-PROF-05, T-STOR-03, phone_utils_test.dart
- **Bugs:** BUG-008
- **Testes manuais pendentes:** TM-013

### FLOW-013: Editar perfil do jardineiro (3 secções, destaques, links)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** CHECK de destaques/links existe; bio e raio sem limite (BUG-006, BUG-008)
- **App (Flutter):** worker_showcase_* (15 testes)
- **Testes automáticos:** worker_showcase_test.dart, worker_showcase_editor_test.dart
- **Bugs:** BUG-006, BUG-008
- **Testes manuais pendentes:** TM-014

### FLOW-014: Guarda de rotas por papel

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** RLS testada nos fluxos
- **App (Flutter):** 35 testes de redirect
- **Testes automáticos:** route_guard_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-015

### FLOW-020: Criar pedido (4 passos, rascunho, fotos)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-JOB-01..16 (14 passam; T-JOB-06 e T-JOB-08 falham), RACE-03 falha
- **App (Flutter):** job_request_form_test, job_schedule_fields_test
- **Testes automáticos:** T-JOB-01, T-JOB-06, T-JOB-08, T-JOB-09, T-JOB-11, T-JOB-12, RACE-03, job_request_form_test.dart
- **Bugs:** BUG-002, BUG-003, BUG-005
- **Testes manuais pendentes:** TM-016, TM-017

### FLOW-021: Limite de 5 pedidos por hora

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-JOB-14/15 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-JOB-15
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-017

### FLOW-022: Editar pedido aberto

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-EDIT-01..03 e T-CANC-07 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-EDIT-01, T-EDIT-02, T-EDIT-03, T-CANC-07
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-018

### FLOW-023: Pedido sem propostas: alargar pesquisa e avisos

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-EDIT-04/05 e T-JOB-07 passaram; cron correu sem erro
- **App (Flutter):** job_followups_test
- **Testes automáticos:** T-EDIT-04, T-EDIT-05, T-CRON-05, job_followups_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-019

### FLOW-024: Ver propostas recebidas (e recomendada)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-PROP-12/14 passaram
- **App (Flutter):** client_proposals_view_test
- **Testes automáticos:** T-PROP-12, T-PROP-14, client_proposals_view_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-020

### FLOW-025: Aceitar proposta

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-PROP-13..28 passaram; RACE-01 passou; RACE-02 falhou
- **App (Flutter):** proposal_pricing_test, proposal_client_date_test
- **Testes automáticos:** T-PROP-17, T-PROP-22, RACE-01, RACE-02
- **Bugs:** BUG-001, BUG-013
- **Testes manuais pendentes:** TM-021

### FLOW-026: Recusar proposta

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** não incluída nesta bateria; coberta na revisão parte 5 (cenários p9)
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-021

### FLOW-027: Detalhe do pedido do cliente (por estado)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** leituras testadas indiretamente
- **App (Flutter):** client_job_flow_test (16), client_job_rules_test (12), client_job_next_step_test
- **Testes automáticos:** client_job_flow_test.dart, client_job_rules_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-022

### FLOW-028: Confirmar conclusão

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-EXEC-09, 13..17 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-EXEC-15, T-EXEC-16
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-023

### FLOW-029: Reportar problema depois de concluído

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** RLS de INSERT confirmada no schema; limite de texto não existe (BUG-008)
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** BUG-008
- **Testes manuais pendentes:** TM-024

### FLOW-030: Avaliar o jardineiro

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-RATE-01..06 passaram (T-RATE-04b mostra que a 2.ª é ignorada)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-RATE-03, T-RATE-04a, T-RATE-04b
- **Bugs:** BUG-012
- **Testes manuais pendentes:** TM-025

### FLOW-031: Cancelar pedido ou trabalho (e reabrir)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CANC-02..07, T-EXEC-08 passaram
- **App (Flutter):** job_dialogs_test
- **Testes automáticos:** T-CANC-04, T-CANC-05, T-EXEC-08, job_dialogs_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-026

### FLOW-032: Remarcar (propor, aceitar, recusar)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-RESCH-01..06 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-RESCH-03, T-RESCH-05, T-RESCH-06
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-027

### FLOW-033: Pedir de novo (pedido direto, 24h)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** não repetido aqui; cenários p9_direct/p9_direct2 da parte 5 passam (PR #47)
- **App (Flutter):** direct_request_test (19)
- **Testes automáticos:** direct_request_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-028

### FLOW-034: Pedido pelo cartão público /w/:id

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CARD-01..04 passaram
- **App (Flutter):** card_direct_request_test (34)
- **Testes automáticos:** T-CARD-01, T-CARD-03, card_direct_request_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-029

### FLOW-035: Os teus jardineiros (anteriores)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** não incluída nesta bateria
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-028

### FLOW-036: Contacto por WhatsApp

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-PROP-25/27/28 e T-HELP-09 confirmam quem vê o telefone
- **App (Flutter):** phone_utils_test (12), whatsapp_button_and_sheets_test
- **Testes automáticos:** T-PROP-25, T-PROP-27, phone_utils_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-030

### FLOW-037: Aprovar pedido de ajudantes (cliente)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** nesta bateria o pedido nasceu open; fluxo coberto no cenário flow.sql de 02/11
- **App (Flutter):** team_flow_improvements_test
- **Testes automáticos:** team_flow_improvements_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-031

### FLOW-038: Início e lista de pedidos do cliente

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-JOB-13 (outro cliente não vê)
- **App (Flutter):** client_job_next_step_test
- **Testes automáticos:** client_job_next_step_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-022

### FLOW-039: Dicas da época (preferência)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** cron correu sem erro (T-CRON-05)
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-032

### FLOW-040: Descobrir pedidos no raio

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-DISC-01..06 passaram; T-DISC-07 e T-DISC-08 falharam
- **App (Flutter):** nenhum
- **Testes automáticos:** T-DISC-01, T-DISC-06, T-DISC-07, T-DISC-08
- **Bugs:** BUG-004
- **Testes manuais pendentes:** TM-033

### FLOW-041: Detalhe da oportunidade (zona aproximada)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-DISC-02/03, T-PROP-24/26 passaram
- **App (Flutter):** worker_job_rules_test (21)
- **Testes automáticos:** T-DISC-02, T-DISC-03, T-PROP-26, worker_job_rules_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-033

### FLOW-042: Enviar proposta (hora ou valor total)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-PROP-01..11 passaram menos T-PROP-07; RACE-04 passou
- **App (Flutter):** proposal_pricing_test (12), create_proposal_error_test
- **Testes automáticos:** T-PROP-01, T-PROP-02, T-PROP-03, T-PROP-05, T-PROP-07, RACE-04, proposal_pricing_test.dart
- **Bugs:** BUG-007
- **Testes manuais pendentes:** TM-034

### FLOW-043: Retirar proposta

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-PROP-23 passou; RACE-02 falhou
- **App (Flutter):** nenhum
- **Testes automáticos:** T-PROP-23, RACE-02
- **Bugs:** BUG-001
- **Testes manuais pendentes:** TM-021

### FLOW-044: Recusar pedido direto ('Não posso desta vez')

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** coberto pelos cenários da parte 5
- **App (Flutter):** direct_request_test
- **Testes automáticos:** direct_request_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-028

### FLOW-045: Os meus trabalhos (Agenda · Propostas · Histórico)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** consequência do RACE-02 confirmada (aparece em 'completed')
- **App (Flutter):** worker_jobs_view_test, worker_board_status_test, worker_proposal_outcome_test
- **Testes automáticos:** worker_jobs_view_test.dart, worker_board_status_test.dart
- **Bugs:** BUG-001
- **Testes manuais pendentes:** TM-035

### FLOW-046: Iniciar trabalho (fotos de antes)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-EXEC-01..07 passaram
- **App (Flutter):** job_start_flow_test
- **Testes automáticos:** T-EXEC-01, T-EXEC-04, T-EXEC-06, T-EXEC-07, job_start_flow_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-036

### FLOW-047: Trabalho por dias / vários dias

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** não repetido; cenários md/md2/p6 de 02/11 passam (ver evidência)
- **App (Flutter):** worker_my_job_detail_view_test (14), worker_todo_test (11)
- **Testes automáticos:** worker_my_job_detail_view_test.dart, worker_todo_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-037

### FLOW-048: Marcar como concluído (fotos de depois)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-EXEC-05, 10..12 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-EXEC-11, T-EXEC-12
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-036

### FLOW-049: Avaliar cliente e ajudantes

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-RATE-07..10 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-RATE-07, T-RATE-08, T-RATE-09, T-RATE-10
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-025

### FLOW-050: Pedir ajudantes e gerir a equipa

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-HELP-05..08 passaram
- **App (Flutter):** help_lobby_*, team_*
- **Testes automáticos:** T-HELP-06, T-HELP-07, T-HELP-08, help_lobby_team_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-031

### FLOW-051: Candidatar-se como ajudante / desistir

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-HELP-01..04 passaram
- **App (Flutter):** help_acceptance_test
- **Testes automáticos:** T-HELP-01, T-HELP-03, T-HELP-04
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-031

### FLOW-052: Trabalho visto pelo ajudante

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-HELP-09 passou
- **App (Flutter):** helper_job_state_test (18)
- **Testes automáticos:** T-HELP-09, helper_job_state_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-031

### FLOW-053: Agenda (Hoje, Semana, Mês)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-AG-02/03 passaram
- **App (Flutter):** agenda_* (≈150 testes)
- **Testes automáticos:** T-AG-02, T-AG-03, agenda_day_view_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-038

### FLOW-054: Agenda: adicionar, editar, apagar e séries

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-AG-01, 04..06 passaram
- **App (Flutter):** agenda_entry_* testes
- **Testes automáticos:** T-AG-01, T-AG-04, T-AG-05, T-AG-06
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-038

### FLOW-055: Cartão partilhável (QR, imagem, PDF, link)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** T-CARD-01/02 (vista pública)
- **App (Flutter):** plan_features_and_earnings_test
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-039

### FLOW-056: Painel de ganhos (Pro)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-PLAN-03 passou
- **App (Flutter):** plan_features_and_earnings_test (15)
- **Testes automáticos:** T-PLAN-03
- **Bugs:** BUG-014
- **Testes manuais pendentes:** TM-040

### FLOW-057: Plano e limite do Grátis

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-PLAN-01/02/04 passaram
- **App (Flutter):** admin_and_worker_plan_test
- **Testes automáticos:** T-PLAN-01, T-PLAN-02, T-PLAN-04
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-040

### FLOW-058: Cartão frota (demo, OCR)

- **Estado:** BLOQUEADO
- **Backend (BD local):** T-FLEET-01 passou
- **App (Flutter):** nenhum
- **Testes automáticos:** T-FLEET-01
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-041
- **Nota:** OCR só em dispositivo.

### FLOW-059: Lembretes de início e atraso (0072)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** cron correu sem erro (T-CRON-05); cenário p8_start da parte 5
- **App (Flutter):** worker_todo_test
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-042

### FLOW-060: Início do jardineiro (dashboard)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** leituras testadas indiretamente
- **App (Flutter):** worker_todo_test, worker_job_flow_test
- **Testes automáticos:** worker_todo_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-035

### FLOW-070: Lista de notificações (ler, filtros, limpar e desfazer)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-NOTIF-01..04 passaram
- **App (Flutter):** notifications_view_test
- **Testes automáticos:** T-NOTIF-01, T-NOTIF-02, T-NOTIF-03, T-NOTIF-04, notifications_view_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-043

### FLOW-071: Abrir o destino ao tocar numa notificação

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** contrato dos tipos SQL e Dart verificado por script: batem
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-044

### FLOW-072: Aviso no topo com a app aberta

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** n/a
- **App (Flutter):** app_toast_and_otp_test
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-045

### FLOW-073: Push FCM

- **Estado:** BLOQUEADO
- **Backend (BD local):** T-PUSH-01..03 passaram (só a tabela)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-PUSH-01, T-PUSH-02, T-PUSH-03
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-046, TM-047
- **Nota:** pg_net/FCM não existem localmente.

### FLOW-074: As minhas avaliações (recebidas e dadas)

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** T-RATE-11 mostra leitura anónima de ratings
- **App (Flutter):** nenhum
- **Testes automáticos:** T-RATE-11
- **Bugs:** BUG-009
- **Testes manuais pendentes:** TM-025

### FLOW-075: Voltar, deep links e PopScope

- **Estado:** ANALISADO ESTATICAMENTE
- **Backend (BD local):** n/a
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-044, TM-048

### FLOW-076: Contacto e suporte, Sobre, links legais

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** n/a
- **App (Flutter):** legal_links_test
- **Testes automáticos:** legal_links_test.dart
- **Bugs:** BUG-010
- **Testes manuais pendentes:** TM-049

### FLOW-077: Uploads para o Storage (avatar e fotos)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-STOR-01..04 passaram
- **App (Flutter):** storage_urls_test
- **Testes automáticos:** T-STOR-01, T-STOR-02, T-STOR-03, T-STOR-04
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-050
- **Nota:** Leitura pública dos buckets é decisão conhecida.

### FLOW-078: Morada e GPS (Photon, Nominatim, geocoder nativo)

- **Estado:** BLOQUEADO
- **Backend (BD local):** n/a
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-051
- **Nota:** Rede externa e GPS reais.

### FLOW-079: Erros, sem rede e timeouts

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** mensagens P0001 da BD testadas (vêm em PT)
- **App (Flutter):** labels_and_errors_test (22)
- **Testes automáticos:** labels_and_errors_test.dart
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-052

### FLOW-080: Entrar no painel /admin (login + 2.º fator)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-ADM-01..05 passaram (aal simulado)
- **App (Flutter):** admin_and_worker_plan_test
- **Testes automáticos:** T-ADM-02, T-ADM-04, T-ADM-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-053

### FLOW-081: Visão geral, lista e ficha de jardineiros

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-ADM-05 passou (overview); lista e ficha não testadas aqui
- **App (Flutter):** nenhum
- **Testes automáticos:** T-ADM-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-053

### FLOW-082: Atribuir plano a um jardineiro

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-ADM-03, 06..08 e T-PLAN-04 passaram
- **App (Flutter):** nenhum
- **Testes automáticos:** T-ADM-06, T-ADM-07, T-ADM-08, T-PLAN-04
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-053

### FLOW-090: Expirar pedidos e trabalhos (auto_expire_jobs)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres); F-003c mostra que fecha um pedido criado já no passado
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05, F-003c
- **Bugs:** BUG-003
- **Testes manuais pendentes:** TM-054
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-091: Confirmação automática (48h; 7 dias com relato)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-054
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-092: Lembretes diários (send_job_reminders)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-042
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-093: Fim da reserva do pedido direto

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-028
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-094: Pedidos sem propostas (6h e 24h)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-019
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-095: Prazos dos pedidos de ajuda

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-031
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-096: Limpeza (notificações, emails bloqueados)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-054
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-097: Dicas da época

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-032
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-098: Lembretes de início (0072)

- **Estado:** TESTADO AUTOMATICAMENTE — PASSOU
- **Backend (BD local):** T-CRON-01..05 passaram (todos os 11 jobs correm sem erro como postgres)
- **App (Flutter):** nenhum
- **Testes automáticos:** T-CRON-01, T-CRON-05
- **Bugs:** nenhum encontrado
- **Testes manuais pendentes:** TM-042
- **Nota:** Confirmar na BD viva que o job existe em cron.job (ver TM-054).

### FLOW-099: Avisar jardineiros de pedidos e ajudas novos (triggers)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** T-PROP-20 passou; F-006c mostra o efeito do raio sem limite
- **App (Flutter):** nenhum
- **Testes automáticos:** T-PROP-20, F-006c
- **Bugs:** BUG-006
- **Testes manuais pendentes:** TM-046

### FLOW-100: Versão web (Netlify)

- **Estado:** BLOQUEADO
- **Backend (BD local):** n/a
- **App (Flutter):** nenhum
- **Testes automáticos:** nenhum
- **Bugs:** BUG-014
- **Testes manuais pendentes:** TM-055

### FLOW-101: Ações repetidas e concorrentes (transversal)

- **Estado:** TESTADO AUTOMATICAMENTE — FALHOU
- **Backend (BD local):** RACE-01 e RACE-04 passaram; RACE-02 e RACE-03 falharam
- **App (Flutter):** nenhum
- **Testes automáticos:** RACE-01, RACE-02, RACE-03, RACE-04
- **Bugs:** BUG-001, BUG-005
- **Testes manuais pendentes:** TM-056

