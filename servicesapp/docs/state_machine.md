# LocalServices — Máquina de Estados do Ciclo de Vida (Fase 8E)

> Referência única de todas as transições de estado, notificações e atualizações de UI.
> Cada transição DEVE: (1) mudar o estado na BD, (2) criar notificação para o lado certo,
> (3) invalidar os providers relevantes para a UI atualizar em tempo real.

## Estados do job (`job_status`)

| Estado | Significado |
|---|---|
| `open` | Pedido criado; aceita 0..N propostas em simultâneo |
| `confirmed` | Proposta aceite (auto-rejeita as restantes), data agendada |
| `awaiting_confirmation` | Worker marcou como concluído, à espera da confirmação do cliente |
| `completed` | Cliente confirmou conclusão |
| `no_response` | 48h sem proposta |
| `cancelled` | Cancelado por um dos lados |

> **Nota:** `proposal_received` foi removido. O job mantém-se `open` enquanto acumula propostas. O campo `proposal_count` no job indica quantas propostas pending existem.

## Estados da proposta (`proposal_status`)

`pending` | `accepted` | `rejected` | `superseded`

## Preferência de data do cliente

- **Data fixa**: `preferred_date` preenchida, `date_mode = 'fixed'`
- **Flexível**: `preferred_date` null, `date_mode = 'flexible'`
- **Disponibilidade**: `date_mode = 'availability'`, detalhes na `description`

## Data agendada (definida pelo worker na proposta)

- A proposta inclui `scheduled_date` + `scheduled_time`
- Ao aceitar, o job copia estes valores para `confirmed_date` / `confirmed_time`

## Remarcação (job confirmado)

Campos no job:
- `reschedule_proposed_date`, `reschedule_proposed_time`
- `reschedule_proposed_by` (uuid)
- `reschedule_status`: null | `pending` | `accepted` | `rejected`

Regra das 24h aplica-se a cancelamento E remarcação: bloqueado se faltarem < 24h para a data confirmada.

## Tabela de transições

| # | Transição | Quem | Notifica | job_status | proposal_status |
|---|---|---|---|---|---|
| 1 | Criar pedido | Cliente | Workers no raio | `open` | — |
| 2 | Enviar proposta | Worker | Cliente | `open` (incrementa proposal_count) | `pending` |
| 3 | Retirar proposta | Worker | Cliente | `open` | `superseded` |
| 4 | Aceitar proposta | Cliente | Worker | `confirmed` | `accepted` |
| 5 | Recusar proposta | Cliente | Worker | `open` | `rejected` |
| 6 | Cancelar open/proposal | Cliente | Worker (se houver proposta) | `cancelled` | `rejected` |
| 7 | Cancelar confirmado | Cliente ou Worker | o outro lado | `cancelled` | `rejected` |
| 8 | Propor remarcação | Cliente ou Worker | o outro lado | `confirmed` (inalterado) | `accepted` |
| 9 | Aceitar remarcação | o outro lado | quem propôs | `confirmed` (nova data) | `accepted` |
| 10 | Recusar remarcação | o outro lado | quem propôs | `confirmed` (data original) | `accepted` |
| 11 | Marcar concluído | Worker | Cliente | `awaiting_confirmation` | `accepted` |
| 12 | Confirmar conclusão | Cliente | Worker | `completed` | `accepted` |
| 13 | Sem resposta 48h | Sistema | Cliente | `no_response` | — |

## Tipos de notificação (NotificationType)

| Tipo | Destinatário | Disparado por |
|---|---|---|
| `new_job_in_radius` | Worker | #1 |
| `proposal_received` | Cliente | #2 |
| `proposal_withdrawn` | Cliente | #3 |
| `proposal_accepted` | Worker | #4 |
| `proposal_rejected` | Worker | #5 |
| `job_cancelled` | o outro lado | #6, #7 |
| `reschedule_proposed` | o outro lado | #8 |
| `reschedule_accepted` | quem propôs | #9 |
| `reschedule_rejected` | quem propôs | #10 |
| `job_marked_done` | Cliente | #11 |
| `job_completed` | Worker | #12 |
| `job_no_response` | Cliente | #13 |

## Regra de ouro de implementação

Cada função de transição na BD (RPC `security definer`) faz tudo numa transação:
1. Valida permissões e regras (ex: 24h)
2. Atualiza `job_requests` e/ou `job_proposals`
3. Insere a notificação para o destinatário correto

No lado Flutter, o `notificationSyncProvider` invalida os providers relevantes
(`clientJobsProvider`, `workerProposalsProvider`, `jobsInRadiusProvider`,
`proposalByIdProvider`) consoante o `type` da notificação recebida.

## Sub-fases de execução

- **8E.1** — Agendamento (preferência de data do cliente + data na proposta + data confirmada)
- **8E.2** — Cancelamento completo (open/proposal/confirmado + regra 24h + notificações)
- **8E.3** — Remarcação (propor/aceitar/recusar + regra 24h)
- **8E.4** — Conclusão a dois lados (worker marca → cliente confirma)
- **8E.5** — Timeline de estados no detalhe
