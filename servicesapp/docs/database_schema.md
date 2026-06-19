# LocalServices — Database Schema

> Schema Supabase (PostgreSQL). Ler antes de criar migrations ou alterar tabelas.
> Toda alteração de schema deve ser refletida aqui E em `decisions_log.md`.

## Princípios
1. Nomes genéricos: a BD não sabe que isto é jardinagem.
2. Categorias e serviços vêm da BD, nunca hardcoded na app.
3. Estados são `text` com `CHECK` constraints (espelham os enums Dart).
4. Row Level Security (RLS) **ativada em todas as tabelas** antes de dados reais.
5. Timestamps `created_at` / `updated_at` em todas as tabelas de domínio.

## Enums (espelhados em `core/constants/enums.dart` no Dart)

### user_role
`client` | `worker`

### job_status
`open` — pedido criado, a receber propostas (N simultâneas)
`confirmed` — client aceitou uma proposta, data agendada
`awaiting_confirmation` — worker marcou como concluído, à espera da confirmação do cliente
`completed` — cliente confirmou conclusão
`no_response` — 48h sem propostas
`cancelled` — cancelado pelo client ou worker

> **Nota:** `proposal_received` foi removido (Fase 8E). Job mantém-se `open` enquanto
> acumula propostas. `proposal_count` indica quantas propostas pending existem.

### proposal_status
`pending` — proposta enviada, à espera de decisão
`accepted` — client aceitou
`rejected` — client recusou ou auto-rejeitada quando outra foi aceite
`superseded` — worker retirou a proposta

### reschedule_status
`pending` — remarcação proposta, à espera de resposta
`accepted` — nova data aceite, `confirmed_*` atualizado
`rejected` — recusada, mantém data original

### date_mode
`fixed` — data específica escolhida pelo cliente
`flexible` — qualquer data
`availability` — disponibilidade descrita em texto livre (`availability_text`)

### help_request_status
`open` | `filled` | `cancelled`

### help_acceptance_status
`accepted` | `cancelled`

---

## Tabelas

### profiles
Dados base de qualquer utilizador. 1:1 com `auth.users`.

| coluna       | tipo        | notas                                     |
|--------------|-------------|-------------------------------------------|
| id           | uuid PK     | FK → `auth.users.id`                      |
| role         | text        | CHECK in (`client`,`worker`)              |
| full_name    | text        |                                           |
| phone        | text        | usado para contacto pós-confirmação       |
| avatar_url   | text        | nullable                                  |
| created_at   | timestamptz | default `now()`                           |
| updated_at   | timestamptz | default `now()`                           |

### worker_profiles
Dados específicos de quem presta serviço. 1:1 com `profiles` (apenas role=worker).

| coluna              | tipo        | notas                                        |
|---------------------|-------------|----------------------------------------------|
| profile_id          | uuid PK     | FK → `profiles.id`                           |
| bio                 | text        | nullable                                     |
| default_hourly_rate | numeric     | nullable (pode ser definido por proposta)    |
| radius_km           | int         | raio de atuação                              |
| base_lat            | numeric     | latitude da base                             |
| base_lng            | numeric     | longitude da base                            |
| tools               | text[]      | lista de ferramentas                         |
| photos              | text[]      | URLs de trabalhos anteriores (Storage)       |
| created_at          | timestamptz |                                              |
| updated_at          | timestamptz |                                              |

### service_categories
Categorias de topo (Jardinagem, Limpeza, etc.). Geridas via dashboard Supabase no MVP.

| coluna     | tipo    | notas                          |
|------------|---------|--------------------------------|
| id         | uuid PK |                                |
| slug       | text U  | ex.: `gardening`               |
| name       | text    | nome visível (PT)              |
| icon       | text    | nullable                       |
| active     | bool    | default `true`                 |

### service_types
Serviços dentro de uma categoria (corte de relva, poda, etc.).

| coluna       | tipo    | notas                              |
|--------------|---------|------------------------------------|
| id           | uuid PK |                                    |
| category_id  | uuid    | FK → `service_categories.id`       |
| slug         | text    |                                    |
| name         | text    | nome visível (PT)                  |
| active       | bool    | default `true`                     |

UNIQUE (`category_id`, `slug`).

### worker_service_types
Que serviços cada worker faz (N:N).

| coluna           | tipo    | notas                             |
|------------------|---------|-----------------------------------|
| worker_id        | uuid    | FK → `worker_profiles.profile_id` |
| service_type_id  | uuid    | FK → `service_types.id`           |

PK composta (`worker_id`, `service_type_id`).

### job_requests
Pedidos criados por clientes.

| coluna                    | tipo        | notas                                                        |
|---------------------------|-------------|--------------------------------------------------------------|
| id                        | uuid PK     |                                                              |
| client_id                 | uuid        | FK → `profiles.id` (role=client)                            |
| service_type_id           | uuid        | FK → `service_types.id`                                     |
| address_text              | text        | morada legível                                               |
| location_lat              | numeric     |                                                              |
| location_lng              | numeric     |                                                              |
| date_mode                 | text        | CHECK in (`fixed`,`flexible`,`availability`), default `flexible` |
| preferred_date            | date        | nullable — preenchida quando date_mode = `fixed`             |
| availability_text         | text        | nullable — preenchida quando date_mode = `availability`      |
| urgency                   | text        | nullable, CHECK in (`normal`,`urgent`)                       |
| size_estimate             | text        | nullable, CHECK in (`small`,`medium`,`large`)                |
| description               | text        |                                                              |
| status                    | text        | CHECK in job_status                                          |
| accepted_proposal_id      | uuid        | nullable, FK → `job_proposals.id`                           |
| proposal_count            | int         | default 0 — contagem de propostas pending                    |
| confirmed_date            | date        | nullable — copiado de scheduled_date ao aceitar proposta     |
| confirmed_time            | time        | nullable                                                     |
| confirmed_flexible        | boolean     | nullable, default false                                      |
| cancelled_by              | uuid        | nullable, FK → `profiles.id`                                |
| cancel_reason             | text        | nullable                                                     |
| cancel_reason_detail      | text        | nullable                                                     |
| reopened_from             | uuid        | nullable, FK → `job_requests.id`                            |
| reopen_count_client       | int         | default 0 — máx 1 reabertura pelo cliente                   |
| reopen_count_worker       | int         | default 0 — máx 2 reaberturas pelo worker                   |
| reschedule_proposed_date  | date        | nullable                                                     |
| reschedule_proposed_time  | time        | nullable                                                     |
| reschedule_proposed_flexible | boolean  | nullable                                                     |
| reschedule_proposed_by    | uuid        | nullable, FK → `profiles.id`                                |
| reschedule_status         | text        | nullable, CHECK in (`pending`,`accepted`,`rejected`)         |
| cancelled_worker_id       | uuid        | nullable, FK → `profiles.id` — worker que cancelou um job confirmado; excluído do novo job reaberto |
| excluded_worker_ids       | uuid[]      | default `'{}'` — lista generalizada de workers excluídos de ver/propor no job reaberto |
| expires_at                | timestamptz | created_at + 48h (para `no_response`)                       |
| created_at                | timestamptz |                                                              |
| updated_at                | timestamptz |                                                              |

### job_photos
Fotos anexadas a um pedido (Storage bucket `job-photos`). Máximo 2 por pedido.

| coluna       | tipo        | notas                       |
|--------------|-------------|-----------------------------|
| id           | uuid PK     |                             |
| job_id       | uuid        | FK → `job_requests.id`      |
| storage_path | text        | path no bucket              |
| created_at   | timestamptz |                             |

### job_proposals
Propostas de workers para jobs.

| coluna               | tipo        | notas                                                      |
|----------------------|-------------|------------------------------------------------------------|
| id                   | uuid PK     |                                                            |
| job_id               | uuid        | FK → `job_requests.id`                                    |
| worker_id            | uuid        | FK → `worker_profiles.profile_id`                         |
| hourly_rate          | numeric     |                                                            |
| estimated_hours      | numeric     | nullable — mantido por compatibilidade                     |
| estimated_hours_min  | numeric     | nullable — substitui estimated_hours                       |
| estimated_hours_max  | numeric     | nullable                                                   |
| people_needed        | int         | default 1 (>1 implica help_request)                        |
| notes                | text        | nullable                                                   |
| scheduled_date       | date        | nullable — data proposta pelo worker                       |
| scheduled_time       | time        | nullable                                                   |
| scheduled_flexible   | boolean     | default false — horário flexível no dia agendado           |
| status               | text        | CHECK in proposal_status                                   |
| created_at           | timestamptz |                                                            |
| updated_at           | timestamptz |                                                            |

### job_reports
Relatos de problemas submetidos por utilizadores após conclusão do trabalho. Para revisão manual pela equipa.

| coluna       | tipo        | notas                                    |
|--------------|-------------|------------------------------------------|
| id           | uuid PK     |                                          |
| job_id       | uuid        | FK → `job_requests.id`                   |
| reporter_id  | uuid        | FK → `profiles.id` (quem reportou)       |
| description  | text        |                                          |
| created_at   | timestamptz |                                          |

### notifications
Notificações persistidas por triggers na BD. Lidas via Supabase Realtime.

```sql
-- Tipos: new_job_in_radius, proposal_received, proposal_withdrawn,
--        proposal_accepted, proposal_rejected, job_cancelled, job_reopened,
--        job_marked_done, job_completed, job_no_response,
--        reschedule_proposed, reschedule_accepted, reschedule_rejected
```

| coluna       | tipo        | notas                                       |
|--------------|-------------|---------------------------------------------|
| id           | uuid PK     |                                             |
| user_id      | uuid        | FK → `profiles.id` (destinatário)           |
| type         | text        | ver tipos acima                             |
| title        | text        | título legível                              |
| body         | text        | corpo da notificação                        |
| related_id   | uuid        | nullable — id do job, proposta, etc.        |
| related_type | text        | nullable — `job_request`, `job_proposal`    |
| read         | bool        | default false                               |
| created_at   | timestamptz |                                             |

### help_requests
Pedido de ajudantes feito pelo worker principal.

| coluna       | tipo        | notas                              |
|--------------|-------------|------------------------------------|
| id           | uuid PK     |                                    |
| job_id       | uuid        | FK → `job_requests.id`             |
| proposal_id  | uuid        | FK → `job_proposals.id`            |
| slots_needed | int         | nº de ajudantes pedidos            |
| status       | text        | CHECK in help_request_status       |
| created_at   | timestamptz |                                    |

### help_acceptances
Ajudantes que aceitaram.

| coluna           | tipo        | notas                                |
|------------------|-------------|--------------------------------------|
| id               | uuid PK     |                                      |
| help_request_id  | uuid        | FK → `help_requests.id`              |
| worker_id        | uuid        | FK → `worker_profiles.profile_id`    |
| status           | text        | CHECK in help_acceptance_status      |
| created_at       | timestamptz |                                      |

UNIQUE (`help_request_id`, `worker_id`).
Quando #aceites = `slots_needed`, o `help_request` passa a `filled`.
Se um cancela, volta a `open` e a vaga reabre.

### ratings
Avaliações simples.

| coluna     | tipo        | notas                                       |
|------------|-------------|---------------------------------------------|
| id         | uuid PK     |                                             |
| job_id     | uuid        | FK → `job_requests.id`                      |
| rater_id   | uuid        | FK → `profiles.id` (quem avalia)            |
| ratee_id   | uuid        | FK → `profiles.id` (quem é avaliado)        |
| stars      | int         | CHECK 1..5                                  |
| comment    | text        | nullable                                    |
| created_at | timestamptz |                                             |

UNIQUE (`job_id`, `rater_id`, `ratee_id`) — uma avaliação por par por job.

---

## RPC Functions (security definer)

Todas as funções de transição de estado são `SECURITY DEFINER` e correm numa
transação: validam permissões, atualizam tabelas e inserem notificação.

| Função                       | Descrição                                                          |
|------------------------------|--------------------------------------------------------------------|
| `create_user_profile`        | Cria perfil após registo (upsert)                                  |
| `create_proposal`            | Cria proposta com data agendada (resolve condição de corrida)      |
| `accept_proposal`            | Aceita proposta, rejeita outras, copia data para job               |
| `reject_proposal`            | Recusa proposta, job volta a `open`                                |
| `withdraw_proposal`          | Worker retira proposta, decrementa `proposal_count`                |
| `cancel_job`                 | Cancela job, cria novo se dentro do limite de reabertura           |
| `propose_reschedule`         | Propõe nova data (regra 24h, só uma pendente por vez)              |
| `accept_reschedule`          | Aceita remarcação, copia nova data para `confirmed_*`              |
| `reject_reschedule`          | Recusa remarcação, mantém data original                            |
| `worker_has_proposal_for_job`| Helper para RLS (evita recursão infinita)                          |
| `get_jobs_in_radius`         | Haversine — jobs abertos dentro do raio do worker                  |
| `mark_job_done`              | Worker marca job como concluído → `awaiting_confirmation`          |
| `confirm_job_completion`     | Cliente confirma conclusão → `completed`                           |

---

## Indexes

- `idx_one_proposal_per_worker_per_job` — UNIQUE PARTIAL on `job_proposals(job_id, worker_id)` WHERE `status = 'pending'`
  Garante que um worker só tem uma proposta pending por job.

---

## Row Level Security (resumo)
A RLS é definida em detalhe nas migrations. Princípios:

- `profiles`: cada user vê/edita o seu; SELECT público limitado a `full_name`/`avatar_url`.
- `worker_profiles`: SELECT público (clientes precisam de ver workers); UPDATE só pelo próprio.
- `service_categories` / `service_types`: SELECT público; INSERT/UPDATE só admin.
- `job_requests`: client vê os seus; worker vê jobs `open` + jobs em que tem proposta.
- `job_proposals`: client vê propostas dos seus jobs; worker vê só as suas.
- `notifications`: cada user vê e gere só as suas.
- `help_requests` / `help_acceptances`: worker principal e workers candidatos/aceites.
- `ratings`: SELECT público (para reputação); INSERT só pelo `rater_id` autenticado.
- `job_reports`: INSERT pelo próprio reporter; SELECT só dos seus próprios reports (sem acesso a reports de outros — moderação é feita via Studio/service role).

---

## Storage
- Bucket `job-photos` (público de leitura, escrita autenticada, máx. 2 fotos por job).
- Bucket `worker-photos` (público de leitura, escrita só pelo dono).
- Bucket `avatars` (público de leitura, escrita só pelo dono).

---

## Migrations

`supabase/migrations/0001_baseline.sql` é a fonte de verdade do schema a partir de 2026-06-19.
Criado por inspeção do código Dart + docs; os corpos das funções são reconstruídos — verificar
contra um `pg_dump` live antes de usar num réplica de produção.

**Regra:** qualquer alteração ao schema (nova coluna, nova tabela, nova função, nova política RLS)
deve vir acompanhada de um novo ficheiro de migration numerado sequencialmente
(`0002_...sql`, `0003_...sql`, etc.). Nunca alterar o `0001_baseline.sql` após o primeiro deploy.
