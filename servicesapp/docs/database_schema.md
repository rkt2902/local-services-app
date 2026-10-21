# LocalServices — Database Schema

> Schema Supabase (PostgreSQL). Ler antes de criar migrations ou alterar tabelas.
> Toda alteração de schema deve ser refletida aqui E em `decisions_log.md`.
>
> **Alinhado com a BD a 2026-10-17** (todas as migrations até à `0046` aplicadas,
> confirmado pelo Henrique). Para a lista completa e atual de RPCs, policies e views,
> `ARCHITECTURE.md` secção 7 e os ficheiros de `supabase/migrations/` são a referência;
> este ficheiro descreve as tabelas e colunas.

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
`pending_approval` | `open` | `filled` | `cancelled`

> `pending_approval`: usado quando `created_post_confirmation = true` — o help_request fica invisível a candidatos até o cliente aprovar via `approve_help_request`. Jobs criados como parte da proposta original aceite começam diretamente em `open`.

### help_acceptance_status
`pending` | `accepted` | `rejected` | `cancelled`

> `pending`: candidatura submetida, a aguardar decisão do principal. `accepted`: principal selecionou o candidato (agreed_rate definido). `rejected`: principal recusou. `cancelled`: candidato retirou-se.

---

## Tabelas

### profiles
Dados base de qualquer utilizador. 1:1 com `auth.users`.

| coluna       | tipo        | notas                                     |
|--------------|-------------|-------------------------------------------|
| id           | uuid PK     | FK → `auth.users.id`                      |
| role         | text        | CHECK in (`client`,`worker`)              |
| full_name    | text        |                                           |
| phone        | text        | nullable, usado para contacto pós-confirmação |
| avatar_url   | text        | nullable. Texto livre na BD; a app só mostra URLs do Storage do próprio projeto (`core/config/storage_urls.dart`) |
| created_at   | timestamptz | default `now()`                           |
| updated_at   | timestamptz | default `now()`                           |

`role` não muda por UPDATE direto (trigger `tg_prevent_profile_role_change`).

### worker_profiles
Dados específicos de quem presta serviço. 1:1 com `profiles` (apenas role=worker).

| coluna              | tipo        | notas                                        |
|---------------------|-------------|----------------------------------------------|
| profile_id          | uuid PK     | FK → `profiles.id`                           |
| bio                 | text        | nullable                                     |
| default_hourly_rate | numeric     | nullable (pode ser definido por proposta)    |
| radius_km           | int         | raio de atuação                              |
| base_lat            | numeric     | NOT NULL, latitude da base                   |
| base_lng            | numeric     | NOT NULL, longitude da base                  |
| tools               | text[]      | lista de ferramentas                         |
| photos              | text[]      | URLs de trabalhos anteriores (Storage)       |
| highlights          | text[]      | 0051: até 5 destaques, 1 a 80 caracteres (CHECK `worker_highlights_valid`) |
| social_links        | jsonb       | 0051: até 4 `{kind, url}`, kind instagram/facebook/website/other, url só `https://` (CHECK `worker_social_links_valid`) |
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
| sort_order | int     | default 100 (0045)             |

Desde a 0045: Jardinagem (`gardening`), Agricultura (`agriculture`) e Floresta
(`forestry`).

### service_types
Serviços dentro de uma categoria (corte de relva, poda, etc.).

| coluna       | tipo    | notas                              |
|--------------|---------|------------------------------------|
| id           | uuid PK |                                    |
| category_id  | uuid    | FK → `service_categories.id`       |
| slug         | text    |                                    |
| name         | text    | nome visível (PT)                  |
| active       | bool    | default `true`                     |
| icon         | text    | nullable (0045): nome de um ícone Material sem `_outlined`; a app traduz em `core/widgets/service_icon.dart` |
| sort_order   | int     | default 100 (0045)                 |

UNIQUE (`category_id`, `slug`). A 0045 semeia 33 tipos; os 3 originais (`lawn_mowing`,
`pruning`, `garden_setup`) mantêm o id e o nome.

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
| size_estimate             | text        | nullable — **sem CHECK na BD viva** (verificado via snapshot direto 2026-06-26; a correção de 2026-06-25 estava errada); validação só via enum `SizeEstimate` no Dart |
| description               | text        |                                                              |
| status                    | text        | CHECK in job_status                                          |
| accepted_proposal_id      | uuid        | nullable, FK → `job_proposals.id`                           |
| proposal_count            | int         | default 0 — contagem de propostas pending                    |
| confirmed_date            | date        | nullable — copiado de scheduled_date ao aceitar proposta     |
| confirmed_time            | time        | nullable                                                     |
| confirmed_flexible        | boolean     | nullable — sem default de coluna; definido via `COALESCE(scheduled_flexible, false)` em `accept_proposal` |
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
| location_area             | text        | nullable (0043): localidade; é o que os workers sem proposta aceite veem em vez da morada exata |
| completion_photo_path     | text        | nullable (0046): foto opcional do worker ao marcar concluído (bucket `job-photos`) |
| marked_done_at            | timestamptz | nullable (0046): quando passou a `awaiting_confirmation`; conta os 3 dias da auto-confirmação |
| day_reminder_sent_on      | date        | nullable (0046): controlo do lembrete da manhã do dia |
| overdue_notified_at       | timestamptz | nullable (0046): aviso "a data passou sem concluir" |
| confirmation_reminder_sent_at | timestamptz | nullable (0046): lembrete ao cliente para confirmar |
| created_at                | timestamptz |                                                              |
| updated_at                | timestamptz |                                                              |

Desde a 0043 os workers só leem esta tabela diretamente se forem o worker aceite (ou
ajudante aceite). Os outros leem por `get_job_by_id`, `get_jobs_in_radius` e
`get_worker_job_board`, que devolvem a localidade e coordenadas arredondadas (cerca de 1 km).

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
| people_needed                | int         | default 1 (>1 implica help_request)                        |
| helpers_equipment_required   | boolean     | default false — ajudantes devem trazer equipamento próprio |
| notes                        | text        | nullable                                                   |
| scheduled_date               | date        | nullable — data proposta pelo worker                       |
| scheduled_time               | time        | nullable                                                   |
| scheduled_flexible           | boolean     | default false — horário flexível no dia agendado           |
| status                       | text        | CHECK in proposal_status                                   |
| created_at                   | timestamptz |                                                            |
| updated_at                   | timestamptz |                                                            |

> **`people_needed` e estimativa de custo:** quando `people_needed > 1`, a app exibe ao cliente a estimativa do custo total da equipa: `hourly_rate × estimated_hours × (1 + (people_needed - 1) × factor)`, onde `factor = 1.0` se `helpers_equipment_required = true`, ou `0.75` caso contrário (buffer de estimativa; o pagamento real ao ajudante sem equipamento é 70%, mas mostra-se 75% para dar margem). Custo real registado em `help_acceptance.agreed_rate` no momento da aceitação.

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
--        reschedule_proposed, reschedule_accepted, reschedule_rejected,
--        help_request_approved, help_accepted, help_rejected,
--        help_job_cancelled, help_request_reopened, help_withdrew,
--        job_reminder (0046)
```

20 tipos. Cada INSERT dispara o trigger `notifications_send_push` (0041), que chama a
Edge Function `send-push` se o destinatário tiver dispositivos em `device_tokens` e o
Vault tiver os segredos (ver `SETUP.md`). Notificações lidas com mais de 90 dias, ou
quaisquer com mais de 180, são apagadas pelo cron `cleanup-old-notifications` (0042).

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

| coluna                    | tipo        | notas                                                                          |
|---------------------------|-------------|--------------------------------------------------------------------------------|
| id                        | uuid PK     |                                                                                |
| job_id                    | uuid        | FK → `job_requests.id`                                                         |
| proposal_id               | uuid        | FK → `job_proposals.id`                                                        |
| slots_needed              | int         | nº de ajudantes pedidos                                                        |
| status                    | text        | CHECK in help_request_status                                                   |
| equipment_required        | boolean     | default false — o helper deve trazer equipamento próprio                       |
| created_post_confirmation | boolean     | default false — true se criado após job `confirmed` (implica `pending_approval`) |
| created_at                | timestamptz |                                                                                |

### help_acceptances
Ajudantes que aceitaram.

| coluna           | tipo        | notas                                                                                   |
|------------------|-------------|-----------------------------------------------------------------------------------------|
| id               | uuid PK     |                                                                                         |
| help_request_id  | uuid        | FK → `help_requests.id`                                                                 |
| worker_id        | uuid        | FK → `worker_profiles.profile_id`                                                       |
| status           | text        | CHECK in help_acceptance_status                                                         |
| agreed_rate      | numeric     | not null, CHECK (`status <> 'accepted' OR agreed_rate > 0`) — rate acordado no momento da aceitação (nunca recalculado a posteriori); placeholder `0` permitido para candidaturas pending |
| brought_equipment| boolean     | not null — se este helper trouxe equipamento próprio                                    |
| created_at       | timestamptz |                                                                                         |

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

### device_tokens (0041)
Um token FCM por dispositivo. Escrita só pelas RPCs `register_device_token` /
`unregister_device_token` (identidade por `auth.uid()`); SELECT só do próprio.

| coluna     | tipo        | notas                                         |
|------------|-------------|-----------------------------------------------|
| token      | text PK     | token FCM                                     |
| user_id    | uuid        | FK → `profiles.id`, `ON DELETE CASCADE`       |
| platform   | text        | CHECK in (`android`,`ios`,`web`)              |
| created_at | timestamptz |                                               |
| updated_at | timestamptz |                                               |

### worker_fleet_cards (0037)
Pedidos de cartão frota (demo). O worker só insere com `status = 'pending'` e só vê os
seus; a ativação é manual por SQL (service role). Ver a migration para as colunas.

---

## RPC Functions (security definer)

Todas as funções de transição de estado são `SECURITY DEFINER` e correm numa
transação: validam permissões, atualizam tabelas e inserem notificação. Identidade
sempre por `auth.uid()`, nunca um `p_worker_id`/`p_client_id` vindo da app.

> A tabela abaixo é o núcleo histórico. A lista completa e atual (incluindo as RPCs das
> migrations 0035, 0038, 0040, 0041, 0043 e 0046) está em `ARCHITECTURE.md` secção 7.
> `create_user_profile` foi apagada na 0042 (a app cria o perfil por upsert em `profiles`).
> `mark_job_done` ganhou `p_photo_path` opcional e só funciona a partir do dia do trabalho
> (0046). `create_proposal`, `get_jobs_in_radius` e `sync_worker_service_types` deixaram
> de receber `p_worker_id` (0044).

| Função                       | Descrição                                                          |
|------------------------------|--------------------------------------------------------------------|
| `create_proposal`            | Cria proposta com data agendada (resolve condição de corrida)      |
| `accept_proposal`            | Aceita proposta, rejeita outras, copia data para job; auto-cria `help_request` quando `people_needed > 1` |
| `reject_proposal`            | Recusa proposta, job volta a `open`                                |
| `withdraw_proposal`          | Worker retira proposta, decrementa `proposal_count`                |
| `cancel_job`                 | Cancela job, cria novo se dentro do limite de reabertura; faz cascade: cancela `help_requests` abertos e rejeita `help_acceptances` pending (migration 0007) |
| `propose_reschedule`         | Propõe nova data (regra 24h, só uma pendente por vez)              |
| `accept_reschedule`          | Aceita remarcação, copia nova data para `confirmed_*`              |
| `reject_reschedule`          | Recusa remarcação, mantém data original                            |
| `worker_has_proposal_for_job`| Helper para RLS (evita recursão infinita)                          |
| `get_jobs_in_radius`         | Haversine — jobs abertos dentro do raio do worker                  |
| `mark_job_done`              | Worker marca job como concluído → `awaiting_confirmation`          |
| `confirm_job_completion`     | Cliente confirma conclusão → `completed`                           |
| `get_help_requests_in_radius`| Haversine — help_requests `open` dentro do raio do worker; exclui jobs `cancelled`/`completed` e help_requests onde o caller é o principal (migration 0007) |
| `approve_help_request`       | Cliente aprova um help_request `pending_approval` → passa a `open` |
| `accept_help_candidate`      | Principal worker aceita candidato `pending` → `accepted`, define `agreed_rate`; marca `help_request` como `filled` se `accepted count = slots_needed`; notifica ajudante (`help_accepted`) |
| `reject_help_candidate`      | Principal worker recusa candidato `pending` → `rejected`, notifica candidato (`help_rejected`) |
| `withdraw_help_acceptance`   | Ajudante retira candidatura aceite → `cancelled`; reabre `help_request` se estava `filled`; notifica candidatos rejeitados (`help_request_reopened`) e principal (`help_withdrew`) |
| `get_my_help_acceptances`    | Devolve todas as candidaturas do ajudante autenticado com contexto: `service_type_name`, `principal_name`, `job_status` — SECURITY DEFINER STABLE; two-hop FK (`job_proposals.worker_id → worker_profiles.profile_id → profiles.id`) inviabiliza PostgREST embedded join |
| `auto_confirm_completed_jobs`| Batch function (sistema, sem `auth.uid()`): percorre jobs em `awaiting_confirmation` há mais de 3 dias e move-os para `completed`; notifica o worker via `job_completed`. Chamada pelo pg_cron a cada 3h (ver secção abaixo). |

### Funções internas (não chamadas directamente pelo Flutter)

| Função                                     | Tipo       | Descrição |
|--------------------------------------------|------------|-----------|
| `client_has_confirmed_job_with_worker(uuid)` | RLS helper | Devolve `true` se o `auth.uid()` (cliente) tem um job `confirmed`, `awaiting_confirmation` ou `completed` com o worker passado. Usado nas políticas SELECT de `profiles` e `worker_profiles`. Confirmado via snapshot 2026-06-26: inclui os três estados. |
| `is_principal_worker_for_help_request(uuid)` | RLS helper | Devolve `true` se o `auth.uid()` é o worker principal do `help_request` dado. Usado em políticas de `help_acceptances`. |
| `notify_workers_new_job()`                   | Trigger fn | Trigger AFTER INSERT em `job_requests`; notifica todos os workers dentro do raio via `new_job_in_radius`. Chamada pelo trigger `on_job_created`, nunca directamente pelo Flutter. |

> **Nota sobre `propose_reschedule`:** a assinatura live tem `p_new_time time without time zone DEFAULT NULL` (não `text` como em 0001_baseline.sql — alterado interactivamente na BD). O corpo também foi actualizado com verificação completa de autorização (v_is_client / v_is_worker). Ver decisions_log 2026-06-26.
>
> **Nota sobre `accept_reschedule`:** corpo igualmente actualizado com verificação completa de autorização. Ver decisions_log 2026-06-26.
>
> **Nota sobre `reject_reschedule`:** corrigida em migration 0016 com o mesmo padrão `v_is_client` / `v_is_worker` de `accept_reschedule` (aplicada; está na baseline consolidada). Ver decisions_log 2026-06-26.

---

## Jobs agendados (pg_cron)

A extensão `pg_cron` foi activada manualmente neste projecto em 2026-06-25.

| Jobname | Cron | Função | Descrição |
|---|---|---|---|
| `auto-confirm-completed-jobs` | `0 */3 * * *` (cada 3h) | `auto_confirm_completed_jobs()` | Confirma automaticamente jobs em `awaiting_confirmation` há mais de 3 dias (desde a 0046 contados a partir de `marked_done_at`) |
| `auto-expire-jobs` | `0 */3 * * *` (cada 3h) | `auto_expire_jobs()` | 48h sem proposta aceite → `no_response`; desde a 0046 também pedidos abertos com data fixa passada, e trabalhos confirmados 3 dias depois da data → `cancelled` (`cancel_reason = 'expired'`) |
| `job-reminders` | `30 7 * * *` | `send_job_reminders()` | 0046: lembrete na manhã do dia, aviso de data passada e lembrete ao cliente para confirmar (`job_reminder`) |
| `cleanup-old-notifications` | `30 3 * * *` | `cleanup_old_notifications()` | 0042: apaga notificações antigas |

**Verificar registo do cron após aplicar migration 0014:**
```sql
SELECT * FROM cron.job WHERE jobname = 'auto-confirm-completed-jobs';
```

**Nota sobre `updated_at` como proxy temporal:** `awaiting_confirmation` é um estado
terminal de escrita — não há nenhum UPDATE posterior até a confirmação. Logo `updated_at`
reflecte fielmente "quando o job entrou neste estado" e é um proxy seguro para a janela
de 3 dias.

---

## Indexes

- `idx_one_proposal_per_worker_per_job` — UNIQUE PARTIAL on `job_proposals(job_id, worker_id)` WHERE `status = 'pending'`
  Garante que um worker só tem uma proposta pending por job.

Todas as tabelas têm índices `_pkey` gerados automaticamente pelas constraints PRIMARY KEY (e índices UNIQUE para constraints UNIQUE). O único índice explícito criado manualmente é o acima.

---

## Triggers

| Trigger | Tabela | Evento | Função |
|---|---|---|---|
| `on_job_created` | `job_requests` | AFTER INSERT FOR EACH ROW | `notify_workers_new_job()` |
| `tg_prevent_profile_role_change` | `profiles` | BEFORE UPDATE | `prevent_profile_role_change()` |
| `notifications_send_push` | `notifications` | AFTER INSERT | `notifications_send_push()` (0041, via `pg_net`) |

Nota: na BD viva o trigger de `job_requests` chama-se `on_job_created`; o ficheiro
`0001_consolidated_baseline.sql` chama-lhe `trigger_notify_workers_new_job`. Mesma
função e evento, sem impacto (ver `ARCHITECTURE.md` secção 16).

O trigger `on_job_created` percorre todos os `worker_profiles` dentro do raio Haversine do novo job e insere uma notificação `new_job_in_radius` para cada um.

---

## Row Level Security (resumo)
A RLS é definida em detalhe nas migrations. Princípios:

- `profiles`: cada user vê/edita o seu. **Sem SELECT público** desde a 0032: o worker só
  vê o cliente com proposta aceite e o cliente só vê o worker com job confirmado
  (`client_has_confirmed_job_with_worker`). Nome e foto da contraparte noutros momentos
  (oportunidade aberta, propostas pendentes, candidatos a ajudante, avaliações) vêm das
  RPCs da 0040. São 5 policies: dono vê, dono insere, dono atualiza e as 2 cruzadas.
- `worker_profiles`: SELECT só do próprio (0030); a descoberta passa pela view
  `worker_profiles_public` (sem coordenadas) e o cartão público pela view
  `worker_public_card` (0033, também para `anon`).
- `service_categories` / `service_types`: SELECT público; INSERT/UPDATE só admin.
- `job_requests`: client vê os seus; desde a 0043 o worker só lê diretamente os jobs em
  que é o worker aceite ou ajudante aceite. O resto passa pelas RPCs mascaradas. INSERT
  direto pelo cliente com limite de pedidos recentes (0042).
- `job_proposals`: client vê propostas dos seus jobs; worker vê só as suas.
- `notifications`: cada user vê e gere só as suas; sem política INSERT — todas as inserções acontecem dentro de funções SECURITY DEFINER (que contornam RLS). Não existe uma política "Sistema insere notificações" na BD viva.
- `help_requests` / `help_acceptances`: worker principal e workers candidatos/aceites. SELECT em `help_requests` para candidatos adicionado em migration 0012 (sem esta política, `fetchHelpRequestById` retornava null para workers que aplicaram mas não são o principal). SELECT para o **worker principal** adicionado em migration 0026 (`"Worker principal vê os seus help requests"` — `EXISTS job_proposals WHERE worker_id = auth.uid()`); a ausência desta policy causava tanto o erro de permissão ao criar (RETURNING falhava) como o lobby vazio (C3.2 — fechado para o principal). **Gap residual (C3.2 cliente):** cliente só vê `pending_approval`; SELECT de `open`/`filled` pelo cliente continua backlog (ver M5 em improvements.md Fases 4-5).
- `ratings`: SELECT público (para reputação); sem INSERT direto desde a 0042, só pelas RPCs
  `submit_*_rating`.
- `job_reports`: INSERT pelo próprio reporter; SELECT só dos seus próprios reports (sem acesso a reports de outros — moderação é feita via Studio/service role).

Desde a 0042 as escritas de negócio (propostas, avaliações, decisões sobre candidatos)
são só por RPC; as escritas diretas que restam têm `WITH CHECK` apertado (ver o
cabeçalho da 0042). Cada função nova faz `REVOKE EXECUTE ... FROM PUBLIC, anon`.

---

## Storage

Os buckets são `public = true` (os URLs de `getPublicUrl` funcionam sem policy de
SELECT). Desde a 0042, `avatars` e `job-photos` têm limite de 2 MB e só aceitam JPEG, PNG
e WebP; o SELECT por policy ficou só para o dono (para não se poder listar o bucket).

| Bucket | public | Políticas RLS activas |
|---|---|---|
| `job-photos` | true | SELECT/UPDATE só pelo dono (primeira pasta = `auth.uid()`); INSERT pelo dono |
| `avatars` | true | SELECT/UPDATE só pelo dono (nome do ficheiro = `auth.uid()`); INSERT pelo dono |
| `worker-photos` | true | **Nenhuma política RLS activa** — bucket criado mas upload via API bloqueado; funcionalidade de fotos de trabalho do worker deixada para pós-MVP |

---

## Migrations

**Estado a 2026-10-17:** `0001_consolidated_baseline.sql` (estado da BD a 2026-07-09) e
todas as migrations de `0033` a `0046` estão aplicadas na BD viva. A `0047`
(`get_candidates_for_help_request` passa a devolver `message`) está criada mas por aplicar.
A próxima é a `0048`.
As 32 migrations incrementais antigas estão em `supabase/migrations/archive/`, só para
histórico (não aplicar). O histórico abaixo é anterior à consolidação.

Histórico: `supabase/migrations/0001_baseline.sql` foi a fonte de verdade do schema a partir de 2026-06-19.
Criado por inspeção do código Dart + docs; os corpos das funções são reconstruídos — verificar
contra um `pg_dump` live antes de usar num réplica de produção.

**Regra:** qualquer alteração ao schema (nova coluna, nova tabela, nova função, nova política RLS)
deve vir acompanhada de um novo ficheiro de migration numerado sequencialmente
(`0002_...sql`, `0003_...sql`, etc.). Nunca alterar o `0001_baseline.sql` após o primeiro deploy.

> **0001–0014 todas confirmadas como aplicadas à BD viva.** Verificação definitiva
> via snapshot directo da BD em 2026-06-26 (ver `decisions_log.md` entrada 2026-06-26).
> Evidências por migration:
> - 0011: `get_jobs_in_radius` existe apenas na versão de 4 parâmetros (overload antigo ausente)
> - 0012: políticas de `job_proposals` sem duplicados; política SELECT para candidatos em `help_requests` presente
> - 0013: corpo de `cancel_job` inclui a regra das 24h
> - 0014: função `auto_confirm_completed_jobs` presente; job `auto-confirm-completed-jobs` activo em `cron.job`
