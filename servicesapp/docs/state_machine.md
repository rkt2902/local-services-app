# LocalServices — Máquina de Estados do Ciclo de Vida

> Referência única de todas as transições de estado, notificações e providers invalidados.
> Cada transição: (1) muda estado na BD via RPC, (2) insere notificação, (3) invalida providers.
> Atualizado após Fases 8A–8E.3.

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

## Regras de cancelamento

- Só jobs `open` ou `confirmed` podem ser cancelados
- Jobs `confirmed`: regra das 24h (`confirmed_date` - hoje >= 1 dia)
- Cliente: máx 1 reabertura por job
- Worker: máx 2 reaberturas por job
- Cancelamento cria novo job (novo id, `reopened_from` aponta para o original)
- Contagens separadas: `reopen_count_client` e `reopen_count_worker`

## Regras de remarcação

- Só jobs `confirmed` podem ser remarcados
- Regra das 24h (igual ao cancelamento)
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
| `proposal_received` | `clientJobsProvider`, `pendingProposalsForJobProvider` |
| `proposal_withdrawn` | `clientJobsProvider`, `pendingProposalsForJobProvider` |
| `proposal_accepted` | `jobsInRadiusProvider`, `workerProposalsProvider`, `proposalByIdProvider`, `workerProposalForJobProvider` |
| `proposal_rejected` | `workerProposalsProvider`, `proposalByIdProvider` |
| `job_cancelled` | `clientJobsProvider`, `workerProposalsProvider`, `jobsInRadiusProvider` |
| `job_reopened` | `clientJobsProvider`, `workerProposalsProvider`, `jobsInRadiusProvider` |
| `reschedule_proposed` | `clientJobsProvider`, `workerProposalsProvider` |
| `reschedule_accepted` | `clientJobsProvider`, `workerProposalsProvider` |
| `reschedule_rejected` | `clientJobsProvider`, `workerProposalsProvider` |
| `job_marked_done` | `clientJobsProvider`, `jobByIdProvider` |
| `job_completed` | `workerProposalsProvider`, `jobByIdProvider` |

## Sub-fases pendentes

- **8E.5** — Timeline de estados no detalhe do job
