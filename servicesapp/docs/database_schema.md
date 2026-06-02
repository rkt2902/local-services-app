# LocalServices — Database Schema

> Schema Supabase (PostgreSQL). Ler antes de criar migrations ou alterar tabelas.
> Toda alteração de schema deve ser refletida aqui E em `decisions_log.md`.

## Princípios
1. Nomes genéricos: a BD não sabe que isto é jardinagem.
2. Categorias e serviços vêm da BD, nunca hardcoded na app.
3. Estados são `text` com `CHECK` constraints (espelham os enums Dart).
4. Row Level Security (RLS) **ativada em todas as tabelas** antes de dados reais.
5. Timestamps `created_at` / `updated_at` em todas as tabelas de domínio.

## Enums (espelhados em `core/constants/` no Dart)

### user_role
`client` | `worker`

### job_status
`open` — pedido criado, à espera de proposta
`proposal_received` — primeira proposta válida associada
`confirmed` — client aceitou a proposta (e equipa, se aplicável)
`completed` — serviço concluído
`no_response` — 48h sem proposta
`cancelled` — cancelado pelo client ou worker

### proposal_status
`pending` — proposta enviada, à espera de decisão
`accepted` — client aceitou
`rejected` — client recusou
`superseded` — substituída (ex.: nova proposta após adição de equipa)

### help_request_status
`open` | `filled` | `cancelled`

### help_acceptance_status
`accepted` | `cancelled`

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

| coluna             | tipo        | notas                                 |
|--------------------|-------------|---------------------------------------|
| profile_id         | uuid PK     | FK → `profiles.id`                    |
| bio                | text        | nullable                              |
| default_hourly_rate| numeric     | nullable (pode ser definido por proposta) |
| radius_km          | int         | raio de atuação                       |
| base_lat           | numeric     | latitude da base                      |
| base_lng           | numeric     | longitude da base                     |
| tools              | text[]      | lista de ferramentas                  |
| photos             | text[]      | URLs de trabalhos anteriores (Storage)|
| created_at         | timestamptz |                                       |
| updated_at         | timestamptz |                                       |

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

| coluna           | tipo    | notas                          |
|------------------|---------|--------------------------------|
| worker_id        | uuid    | FK → `worker_profiles.profile_id` |
| service_type_id  | uuid    | FK → `service_types.id`        |

PK composta (`worker_id`, `service_type_id`).

### job_requests
Pedidos criados por clientes.

| coluna             | tipo        | notas                                  |
|--------------------|-------------|----------------------------------------|
| id                 | uuid PK     |                                        |
| client_id          | uuid        | FK → `profiles.id` (role=client)       |
| service_type_id    | uuid        | FK → `service_types.id`                |
| address_text       | text        | morada legível                         |
| location_lat       | numeric     |                                        |
| location_lng       | numeric     |                                        |
| preferred_date     | date        |                                        |
| urgency            | text        | nullable (ex.: `normal`,`urgent`)      |
| size_estimate      | text        | nullable                               |
| description        | text        |                                        |
| status             | text        | CHECK in job_status                    |
| accepted_proposal_id | uuid      | nullable, FK → `job_proposals.id`      |
| expires_at         | timestamptz | criado_at + 48h (para `no_response`)   |
| created_at         | timestamptz |                                        |
| updated_at         | timestamptz |                                        |

### job_photos
Fotos anexadas a um pedido (Storage bucket `job-photos`).

| coluna     | tipo    | notas                       |
|------------|---------|-----------------------------|
| id         | uuid PK |                             |
| job_id     | uuid    | FK → `job_requests.id`      |
| storage_path | text  | path no bucket              |
| created_at | timestamptz |                         |

### job_proposals
Propostas de workers para jobs.

| coluna              | tipo        | notas                                |
|---------------------|-------------|--------------------------------------|
| id                  | uuid PK     |                                      |
| job_id              | uuid        | FK → `job_requests.id`               |
| worker_id           | uuid        | FK → `worker_profiles.profile_id`    |
| hourly_rate         | numeric     |                                      |
| estimated_hours     | numeric     |                                      |
| people_needed       | int         | default 1 (>1 implica help_request)  |
| notes               | text        | nullable                             |
| status              | text        | CHECK in proposal_status             |
| created_at          | timestamptz |                                      |
| updated_at          | timestamptz |                                      |

**Resolução da condição de corrida** ("primeiro worker a propor fica associado"):
- Constraint: PARTIAL UNIQUE INDEX em `job_proposals(job_id) WHERE status IN ('pending','accepted')`.
  → Garante que só existe uma proposta "viva" por job em simultâneo.
- A criação da proposta faz-se via função PL/pgSQL (`create_proposal`) que, numa
  transação, verifica `status='open'`, insere a proposta e marca o job como
  `proposal_received`. Se duas chegarem ao mesmo tempo, só uma vence.
- Se o client recusar, a função `reject_proposal` marca a proposta `rejected` e
  o job volta a `open`, libertando a constraint.

### help_requests
Pedido de ajudantes feito pelo worker principal.

| coluna         | tipo        | notas                              |
|----------------|-------------|------------------------------------|
| id             | uuid PK     |                                    |
| job_id         | uuid        | FK → `job_requests.id`             |
| proposal_id    | uuid        | FK → `job_proposals.id`            |
| slots_needed   | int         | nº de ajudantes pedidos            |
| status         | text        | CHECK in help_request_status       |
| created_at     | timestamptz |                                    |

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

| coluna       | tipo        | notas                                       |
|--------------|-------------|---------------------------------------------|
| id           | uuid PK     |                                             |
| job_id       | uuid        | FK → `job_requests.id`                      |
| rater_id     | uuid        | FK → `profiles.id` (quem avalia)            |
| ratee_id     | uuid        | FK → `profiles.id` (quem é avaliado)        |
| stars        | int         | CHECK 1..5                                  |
| comment      | text        | nullable                                    |
| created_at   | timestamptz |                                             |

UNIQUE (`job_id`,`rater_id`,`ratee_id`) — uma avaliação por par por job.

## Row Level Security (resumo)
A RLS é definida em detalhe nas migrations. Princípios:

- `profiles`: cada user vê/edita o seu; SELECT público limitado a `full_name`/`avatar_url`.
- `worker_profiles`: SELECT público (clientes precisam de ver workers); UPDATE só pelo próprio.
- `service_categories` / `service_types`: SELECT público; INSERT/UPDATE só admin.
- `job_requests`: client vê os seus; worker vê jobs `open` no seu raio + jobs em que tem proposta.
- `job_proposals`: client vê propostas dos seus jobs; worker vê só as suas.
- `help_requests` / `help_acceptances`: worker principal e workers candidatos/aceites.
- `ratings`: SELECT público (para reputação); INSERT só pelo `rater_id` autenticado.

## Storage
- Bucket `job-photos` (público de leitura, escrita autenticada).
- Bucket `worker-photos` (público de leitura, escrita só pelo dono).
- Bucket `avatars` (público de leitura, escrita só pelo dono).