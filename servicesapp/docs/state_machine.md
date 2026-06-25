# LocalServices — Máquina de Estados do Ciclo de Vida

> Referência única de todas as transições de estado, notificações e providers invalidados.
> Cada transição: (1) muda estado na BD via RPC, (2) insere notificação, (3) invalida providers.
> Atualizado após Fases 8A–9 (cancellation handling gaps fechados 2026-06-24).

## Estados do job (`job_status`)

| Estado | Significado |
|---|---|
| `open` | Pedido criado, a receber propostas |
| `confirmed` | Proposta aceite, data agendada |
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
| 12 | Marcar concluído | Worker | `mark_job_done` | Cliente → `job_marked_done` | `awaiting_confirmation` | `accepted` |
| 13 | Confirmar conclusão | Cliente | `confirm_job_completion` | Worker → `job_completed` | `completed` | `accepted` |
| 14 | Sem resposta 48h | Sistema | — (cron/check) | Cliente → `job_no_response` | `no_response` | — |

## Transições de equipa de ajudantes (Fase 9)

| # | Transição | Quem | RPC | Notifica | help_request_status | help_acceptance_status |
|---|---|---|---|---|---|---|
| T1 | Criar pedido de ajuda | Worker principal | — (INSERT direto) | — | `open` ou `pending_approval` | — |
| T2 | Aprovar pedido de ajuda | Cliente | `approve_help_request` | Worker principal → `help_request_approved` | `open` | — |
| T3 | Candidatar-se | Worker ajudante | — (INSERT direto) | — | inalterado | `pending` |
| T4 | Rejeitar candidatura | Worker principal | `reject_help_candidate` | Ajudante → `help_rejected` | inalterado | `rejected` |
| T5 | Aceitar candidatura | Worker principal | `accept_help_candidate` | Ajudante → `help_accepted`; se slots preenchidos → `filled` | `open` ou `filled` | `accepted` |
| T6 | Ajudante retira-se | Worker ajudante | `withdraw_help_acceptance` | Principal → `help_withdrew`; candidatos rejeitados → `help_request_reopened` (se era filled) | `filled → open` ou inalterado | `cancelled` |
| T7 | Job cancelado (cascade) | Sistema via cancel_job | — | Ajudantes `accepted` → `help_job_cancelled` | `cancelled` | `rejected` (pending) / `accepted` (inalterado) |

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

| Tipo de notificação | Providers invalidados |
|---|---|
| `new_job_in_radius` | `jobsInRadiusProvider` |
| `proposal_received` | `clientJobsProvider`, `pendingProposalsForJobProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider` |
| `proposal_withdrawn` | `clientJobsProvider`, `pendingProposalsForJobProvider`, `jobsInRadiusProvider`, `workerProposalForJobProvider` |
| `proposal_accepted` | `jobsInRadiusProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `proposalByIdProvider`, `workerProposalForJobProvider`, `jobByIdProvider` |
| `proposal_rejected` | `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `proposalByIdProvider` |
| `job_cancelled` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobsInRadiusProvider`, `jobByIdProvider` |
| `job_reopened` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobsInRadiusProvider`, `jobByIdProvider` |
| `reschedule_proposed` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobByIdProvider` |
| `reschedule_accepted` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobByIdProvider` |
| `reschedule_rejected` | `clientJobsProvider`, `pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobByIdProvider` |
| `job_marked_done` | `clientJobsProvider`, `jobByIdProvider` |
| `job_completed` | `scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobByIdProvider` |
| `help_request_approved` | `helpRequestsForJobProvider` |
| `help_accepted` | `jobByIdProvider`, `myHelpAcceptancesProvider` |
| `help_rejected` | `myHelpAcceptancesProvider` |
| `help_job_cancelled` | `helpRequestSummariesInRadiusProvider`, `helpRequestsInRadiusProvider`, `myHelpAcceptancesProvider` |
| `help_request_reopened` | `helpRequestSummariesInRadiusProvider`, `helpRequestsInRadiusProvider` |
| `help_withdrew` | `helpRequestsForJobProvider` |

> **`myHelpAcceptancesProvider` — invalidação:** invalidado por `notificationSyncProvider`
> para `help_accepted`, `help_rejected` e `help_job_cancelled` (ver tabela acima).
> Também invalidado directamente por: acção "Desistir" na tab "As minhas candidaturas"
> (`_withdraw` em `WorkerHelpRequestsScreen`) e pull-to-refresh na mesma tab (`_onRefresh`).

## Sub-fases pendentes

- **8E.5** — Timeline de estados no detalhe do job
