# LocalServices — Máquina de Estados do Ciclo de Vida

> Referência única de todas as transições de estado, notificações e providers invalidados.
> Cada transição: (1) muda estado na BD via RPC, (2) insere notificação, (3) invalida providers.
> Revisto contra o código e as migrations a 2026-10-27 (todas aplicadas na BD viva, até à
> 0065). Os estados vivem em `job_requests.status` e afins; os enums Dart estão em
> `core/constants/enums.dart`.

## Estados do job (`job_status`)

| Estado | Significado |
|---|---|
| `open` | Pedido criado, a receber propostas |
| `confirmed` | Proposta aceite, data agendada. "Em curso" não é um estado: é `confirmed` com `started_at` preenchido (0052) |
| `awaiting_confirmation` | Worker marcou como concluído, à espera do cliente |
| `completed` | Cliente confirmou conclusão |
| `no_response` | 48h sem propostas |
| `cancelled` | Cancelado por um dos lados |

## Estados da proposta (`proposal_status`)

| Estado | Significado |
|---|---|
| `pending` | Enviada, à espera de decisão |
| `accepted` | Cliente aceitou |
| `rejected` | Cliente recusou ou auto-rejeitada quando outra foi aceite |
| `superseded` | Worker retirou a proposta |

## Estado de remarcação (`reschedule_status`)

| Estado | Significado |
|---|---|
| `pending` | Remarcação proposta, à espera de resposta |
| `accepted` | Nova data aceite, `confirmed_*` atualizado |
| `rejected` | Recusada, mantém data original |

## Estado do pedido de ajuda (`help_request_status`)

| Estado | Significado |
|---|---|
| `pending_approval` | Criado pelo worker principal após o job estar confirmado; aguarda aprovação do cliente |
| `open` | Disponível para candidaturas de ajudantes |
| `filled` | Todos os slots preenchidos (`accepted` count = `slots_needed`) |
| `cancelled` | Cancelado em cascade quando o job é cancelado |

## Estado da candidatura de ajuda (`help_acceptance_status`)

| Estado | Significado |
|---|---|
| `pending` | Candidatura enviada, à espera de decisão do principal |
| `accepted` | Principal aceitou o ajudante; `agreed_rate` definido |
| `rejected` | Principal recusou; candidato pode re-candidatar-se se o slot reabrir |
| `cancelled` | Ajudante retirou a própria candidatura aceite (`withdraw_help_acceptance`) |

## Preferência de data do cliente (`date_mode`)

| Modo | Significado |
|---|---|
| `fixed` | Data específica escolhida pelo cliente |
| `flexible` | Qualquer data |
| `availability` | Disponibilidade descrita em texto (`availability_text`) |

## Tabela de transições

| # | Transição | Quem | RPC | Notifica | job_status | proposal_status |
|---|---|---|---|---|---|---|
| 1 | Criar pedido | Cliente | — (INSERT direto) | Workers no raio → `new_job_in_radius` | `open` | — |
| 2 | Enviar proposta | Worker | `create_proposal` | Cliente → `proposal_received` | `open` (inalterado) | `pending` |
| 3 | Retirar proposta | Worker | `withdraw_proposal` | Cliente → `proposal_withdrawn` | `open` (inalterado) | `superseded` |
| 4 | Aceitar proposta | Cliente | `accept_proposal` | Worker aceite → `proposal_accepted`; workers rejeitados → `proposal_rejected` | `confirmed` | `accepted` / `rejected` |
| 5 | Recusar proposta | Cliente | `reject_proposal` | Worker → `proposal_rejected` | `open` | `rejected` |
| 6 | Cancelar (open) | Cliente | `cancel_job` | — | `cancelled` | `rejected` |
| 7 | Cancelar (confirmed) — com reabertura | Cliente ou Worker | `cancel_job` | outro lado → `job_cancelled`; worker original → `job_reopened`; workers no raio → `new_job_in_radius` | `cancelled` + novo `open` | `rejected` |
| 8 | Cancelar (confirmed) — sem reabertura | Cliente ou Worker | `cancel_job` | outro lado → `job_cancelled` | `cancelled` | `rejected` |
| 9 | Propor remarcação | Cliente ou Worker | `propose_reschedule` | outro lado → `reschedule_proposed` | `confirmed` (inalterado) | `accepted` (inalterado) |
| 10 | Aceitar remarcação | outro lado | `accept_reschedule` | quem propôs → `reschedule_accepted` | `confirmed` (nova data) | `accepted` (inalterado) |
| 11 | Recusar remarcação | outro lado | `reject_reschedule` | quem propôs → `reschedule_rejected` | `confirmed` (data original) | `accepted` (inalterado) |
| 11b | Editar pedido aberto (0049) | Cliente | `update_job_request` | Quem já propôs → `job_updated` | `open` (inalterado) | inalterado |
| 11c | Iniciar trabalho (0052, a partir de 1h antes da hora, fotos de antes opcionais) | Worker | `start_job` | Cliente → `job_started`; ajudantes → `help_job_started` | `confirmed` (`started_at` preenchido) | `accepted` |
| 12 | Marcar concluído (desde 0052 exige ter iniciado; até 3 fotos de depois) | Worker | `mark_job_done` | Cliente → `job_marked_done`; ajudantes → `help_job_done` | `awaiting_confirmation` | `accepted` |
| 13 | Confirmar conclusão | Cliente | `confirm_job_completion` | Worker → `job_completed` | `completed` | `accepted` |
| 14 | Sem resposta 48h, ou data fixa passada (0046) | Sistema | `auto_expire_jobs` (cron) | Cliente → `job_no_response` | `no_response` | `pending` → `rejected` |
| 15 | Confirmado, 3 dias depois da data sem conclusão (0046) | Sistema | `auto_expire_jobs` (cron) | Cliente e worker → `job_cancelled`; ajudantes → `help_job_cancelled` | `cancelled` (`cancel_reason = expired`) | `accepted` |
| 16 | Marcado concluído, 48h sem confirmação nem problema reportado (0052; lembrete às 24h) | Sistema | `auto_confirm_completed_jobs` (cron de hora a hora) | Os dois → `job_completed`; ajudantes → `help_job_completed` | `completed` | `accepted` |
| — | Lembretes (0046): manhã do dia, data passada, conclusão por confirmar | Sistema | `send_job_reminders` (cron) | `job_reminder` | inalterado | inalterado |
| — | Pedido aberto sem propostas (0062): às 6h lembrete aos jardineiros; às 24h mostrado 10 km mais longe e prazo +24h | Sistema | `process_open_job_followups` (cron, 8h a 21h) | `job_opportunity_reminder`; anel novo → `new_job_in_radius`; cliente → `job_no_proposals_yet` | `open` (inalterado) | — |
| — | "Mostrar a jardineiros mais longe" (0062, +10 km até 30) | Cliente | `widen_job_search` | anel novo → `new_job_in_radius` | `open` (inalterado) | — |

## Proposta: validade e formato do preço (0058)

`pricing_mode` (`hourly`/`fixed_total`) não é um estado. `valid_until` também não: a
proposta continua `pending` depois de expirar, mas `get_pending_proposals_for_job`
devolve `is_expired = true` e o trigger `trg_job_proposal_block_expired_accept` recusa
passar a `accepted`.

## Dias de trabalho (0058, `job_work_days`)

O trabalho continua `confirmed` com `started_at` preenchido ("Em curso"). Os dias vivem à
parte e no máximo um está aberto.

| # | Transição | Quem | RPC | Dia |
|---|---|---|---|---|
| W1 | Iniciar trabalho | Jardineiro | `start_job` | trigger cria o dia 1 (aberto) |
| W2 | "Terminar o dia N" | Jardineiro | `finish_work_day` | dia N fechado |
| W3 | "Começar o dia N+1" | Jardineiro | `start_work_day` | dia N+1 aberto (falha se houver um aberto) |
| W4 | Concluir, ou cancelar | Jardineiro / sistema | `mark_job_done` / `cancel_job` | trigger fecha o dia aberto |

## Pedido direto (0057, `direct_status`)

O pedido continua `open` em `job_status`; a reserva vive em `direct_status`. Enquanto
`waiting` e antes de `direct_until`, só o jardineiro escolhido vê o pedido e pode propor.

| # | Transição | Quem | RPC | Notifica | direct_status |
|---|---|---|---|---|---|
| D1 | "Pedir de novo" (INSERT com `direct_source_job_id`) | Cliente | — (trigger valida e reserva 24h) | Escolhido → `direct_job_request` | `waiting` |
| D2 | "Não posso desta vez" (ou retirar a proposta) | Jardineiro escolhido | `decline_direct_job_request` | Workers no raio → `new_job_in_radius`; cliente → `direct_request_released` | `declined` (fica em `excluded_worker_ids`) |
| D3 | 24h sem proposta | Sistema | `expire_direct_job_requests` (cron 5 min) | Workers no raio; cliente → `direct_request_released` | `expired` |
| D4 | "Mostrar já a todos" ou recusar a proposta do escolhido | Cliente | `release_direct_job_request` / `reject_proposal` | Workers no raio | `released` |
| D5 | Pedido pelo cartão `/w/:id` (INSERT com `direct_card_worker_id`, 0059) | Cliente | — (trigger valida e reserva 24h, origem `public_card`) | Escolhido → `direct_job_request` ("Novo pedido pelo teu cartão") | `waiting` |
| D6 | D2 ou D3 com o interruptor desligado (`direct_auto_release = false`, 0059) | Jardineiro escolhido / sistema | `decline_direct_job_request` / cron | Cliente → `direct_request_released` ("O pedido está parado...") | `on_hold` (`direct_hold_reason` `declined` ou `expired`) |
| D7 | "Mostrar a todos" no pedido parado | Cliente | `release_direct_job_request` | Workers no raio | `released` |

Ao abrir a todos, `expires_at` passa a pelo menos agora + 48h. Em `on_hold` ninguém mais
vê o pedido; depois do prazo (`expired`) o escolhido ainda o vê e pode propor, depois de
recusar (`declined`) não. Cancelar continua a ser `cancel_job`.

## Transições de equipa de ajudantes (Fase 9)

| # | Transição | Quem | RPC | Notifica | help_request_status | help_acceptance_status |
|---|---|---|---|---|---|---|
| T1 | Criar pedido de ajuda | Worker principal | — (INSERT direto, `WITH CHECK` apertado na 0042) | Cliente → `help_request_pending_approval` se precisa de aprovação; jardineiros no raio que fazem o serviço → `new_help_request_in_radius` quando abre (0054) | `open` ou `pending_approval` | — |
| T2 | Aprovar pedido de ajuda | Cliente | `approve_help_request` | Worker principal → `help_request_approved` | `open` | — |
| T3 | Candidatar-se (com mensagem opcional) | Worker ajudante | `apply_to_help_request` (0048) | Principal → `help_candidate_applied` | inalterado | `pending` |
| T4 | Rejeitar candidatura | Worker principal | `reject_help_candidate` | Ajudante → `help_rejected` | inalterado | `rejected` |
| T5 | Aceitar candidatura | Worker principal | `accept_help_candidate` | Ajudante → `help_accepted`; se slots preenchidos → `filled` | `open` ou `filled` | `accepted` |
| T6 | Ajudante retira-se | Worker ajudante | `withdraw_help_acceptance` | Principal → `help_withdrew`; candidatos rejeitados → `help_request_reopened` (se era filled) | `filled → open` ou inalterado | `cancelled` |
| T7 | Job cancelado (cascade) | Sistema via cancel_job | — | Ajudantes `accepted` → `help_job_cancelled` | `cancelled` | `rejected` (pending) / `accepted` (inalterado) |
| T8 | Cancelar o pedido de ajuda / mudar vagas (0049) | Worker principal | `cancel_help_request` / `update_help_request_slots` | candidatos e ajudantes afetados | `cancelled` / `open` ou `filled` | `rejected` ou inalterado |
| T9 | Retirar um ajudante (0049, revisto na 0055) | Worker principal | `remove_help_helper` | Ajudante → `help_removed`; no dia do trabalho a vaga não reabre | `filled → open` (antes do dia) | `cancelled` |
| T10 | Fecho no dia do trabalho (0054) | Sistema | `close_help_requests_on_job_day` (cron) | Pendentes recusados; principal → `help_request_closed` | `filled` (com aceites) ou `cancelled` | `pending → rejected` |
| T11 | Aprovação automática ao fim de 24h (0055) | Sistema | `process_help_request_deadlines` (cron) | Principal → `help_request_approved`; cliente → `help_request_auto_approved` | `pending_approval → open` | — |
| T12 | Aviso da véspera, a partir das 18h (0055) | Sistema | `process_help_request_deadlines` (cron) | Principal → `help_request_closing_soon`; cliente que não aprovou → `help_request_pending_approval` | inalterado | — |

Regras da equipa desde a 0054/0055: a descoberta e as candidaturas fecham à meia-noite
do dia do trabalho; o ajudante aceite só pode desistir até à véspera; o cliente vê a
equipa (`get_accepted_helpers_for_job`). Remarcar o trabalho avisa os ajudantes
(`help_job_rescheduled`).

## Agenda do jardineiro (0064)

Não mexe nos estados acima. Os trabalhos da app aparecem na Agenda pelo estado que já
têm (`get_worker_agenda` devolve `app_job`, `helper_job`, `proposal` a tracejado e
`reschedule` por aceitar). O que vive só na Agenda são os trabalhos de fora da app e as
indisponibilidades (`worker_calendar_entries`):

| Transição | Ação na app | Estado |
|---|---|---|
| Criar | "Adicionar à agenda" / "Marcar indisponível" | `scheduled` |
| Marcar como feito (com "Desfazer") | detalhe | `done` (`status_at` por trigger) |
| Cancelar / repor | detalhe | `cancelled` (fica na agenda, riscado) / `scheduled` |
| Só este dia numa série | detalhe ou formulário | exceção em `worker_calendar_exceptions` (`skipped`, `moved`, `changed` ou `status`) |
| Este e os seguintes | formulário | `split_calendar_series` corta a série e cria uma nova |
| "Já estou livre" num dia de indisponibilidade | detalhe | `free_calendar_day` (exceção `skipped`) |
| Apagar | detalhe | linha apagada |

Sobreposições só avisam, nunca bloqueiam (`agenda_conflicts.dart`, `agenda_slot_check.dart`).

## Regras de cancelamento

- Só jobs `open` ou `confirmed` podem ser cancelados
- Jobs `confirmed` com `confirmed_date` definida: regra das 24h simétrica — cliente
  e worker não podem cancelar se `confirmed_date - CURRENT_DATE < 1` dia; enforcement
  na BD via `cancel_job` (migration 0013) e UI client-side (botão desativado +
  mensagem explicativa). Jobs com `confirmed_date IS NULL` (data flexível) estão
  isentos desta restrição
- Cliente: máx 1 reabertura por job
- Worker: máx 2 reaberturas por job
- Cancelamento cria novo job (novo id, `reopened_from` aponta para o original)
- Contagens separadas: `reopen_count_client` e `reopen_count_worker`
- `cancel_job` faz cascade à equipa de ajudantes: cancela todos os `help_requests`
  não cancelados do job (→ `cancelled`), rejeita todas as `help_acceptances` com
  `status = 'pending'` (→ `rejected`), e notifica todos os ajudantes com
  `status = 'accepted'` via `help_job_cancelled` — ver transição **T7** na tabela
  de equipa (migrations 0007 + 0009)

## Regras de remarcação

- Só jobs `confirmed` podem ser remarcados
- Regra das 24h (idêntica à do cancelamento — ver acima; enforcement em `propose_reschedule`)
- Só uma remarcação pendente por job de cada vez
- Quem propõe não pode aceitar a própria remarcação (validado na BD)
- Recusa mantém a data original

## Múltiplas propostas

- Job mantém-se `open` com N propostas `pending`
- Um worker só pode ter uma proposta `pending` por job (índice único)
- Cliente vê lista de propostas, aceita a mais conveniente
- Aceitar uma → auto-rejeita todas as outras
- `proposal_count` no job mantém contagem para display

## Providers invalidados por notificação

Fonte: `notificationSyncProvider` em `notification_providers.dart` (2026-10-27). "Board" =
`_invalidateWorkerJobBoard`: página 0 das 3 tabs de `workerJobBoardPageProvider` e
`agendaRangeProvider`. Todas as notificações invalidam também `allNotificationsProvider`.

| Tipo de notificação | Providers invalidados |
|---|---|
| `new_job_in_radius`, `direct_job_request`, `job_opportunity_reminder` | `jobsInRadiusProvider` |
| `proposal_received` | `clientJobsProvider`, `pendingProposalsForJobProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `jobByIdProvider(id)` |
| `proposal_withdrawn` | `clientJobsProvider`, `pendingProposalsForJobProvider`, `jobsInRadiusProvider`, `workerProposalForJobProvider`, `jobByIdProvider(id)` |
| `proposal_accepted` | `jobsInRadiusProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `proposalByIdProvider`, `workerProposalForJobProvider`, `jobByIdProvider`, `myWorkerPlanProvider` (limite do Grátis) |
| `proposal_rejected` | `jobsInRadiusProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `proposalByIdProvider`, `workerProposalForJobProvider` |
| `job_cancelled`, `job_reopened` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `jobsInRadiusProvider`, `jobByIdProvider` |
| `reschedule_proposed/accepted/rejected`, `job_reminder` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `jobByIdProvider` |
| `job_started`, `job_marked_done` | `clientJobsProvider`, `jobByIdProvider` |
| `job_completed` | `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider(0)`, Board, `jobByIdProvider`, `clientJobsProvider`, `myRatingForJobProvider(id)`, `myRatingForJobAndRateeProvider` |
| `job_no_response`, `direct_request_released`, `job_no_proposals_yet` | `clientJobsProvider`, `jobByIdProvider(id)` |
| `job_updated` | `jobsInRadiusProvider`, `pendingWorkerProposalsProvider`, `workerProposalForJobProvider`, Board, `jobByIdProvider(id)` |
| `help_request_approved` | `helpRequestsForJobProvider` |
| `help_accepted` | `jobByIdProvider`, `myHelpAcceptancesProvider`, Board |
| `help_rejected` | `myHelpAcceptancesProvider` |
| `help_job_cancelled` | `helpRequestSummariesInRadiusProvider`, `helpRequestsInRadiusProvider`, `myHelpAcceptancesProvider`, Board |
| `help_request_reopened`, `new_help_request_in_radius` | `helpRequestSummariesInRadiusProvider`, `helpRequestsInRadiusProvider` |
| `help_withdrew`, `help_candidate_applied`, `help_request_closed`, `help_request_closing_soon` | `helpRequestsForJobProvider`, `candidatesForHelpRequestProvider` |
| `help_request_pending_approval`, `help_request_auto_approved` | `clientJobsProvider`, `helpRequestsForJobProvider`, `jobByIdProvider(id)` |
| `help_removed`, `help_job_rescheduled`, `help_job_done`, `help_job_started` | `myHelpAcceptancesProvider`, `helpRequestSummariesInRadiusProvider`, Board |
| `help_job_completed` | `myHelpAcceptancesProvider`, Board, `myRatingForJobProvider(id)` |
| `seasonal_tip` | nenhum (só a lista de notificações) |

> **Invalidação de `myHelpAcceptancesProvider`:** além da tabela, é invalidado
> diretamente pela ação "Desistir" e pelo pull-to-refresh na tab "As minhas candidaturas"
> (`WorkerHelpRequestsScreen`).

## Pendente

Nada nesta máquina de estados. A timeline (antigo 8E.5) está feita desde 2026-10-15
(`StatusTimelineHorizontal`). "Ver o local primeiro" (visita paga antes do orçamento) foi
adiado para a fase 2 a 2026-10-22 e não tem estado nenhum ainda.
