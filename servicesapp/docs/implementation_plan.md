# LocalServices — Implementation Plan

> Ordem de trabalho e estado atual. Atualizar à medida que se avança.
> O Claude Code lê este ficheiro para saber em que passo está.

## Estado atual — MVP feature-complete (2026-06-27)

**Fases 0–11 todas implementadas.** O feature set do MVP está completo.
O projeto está agora na fase de **hardening e polish** — não de construção de features.

| Migrations | Estado |
|---|---|
| 0001–0014 | Aplicadas à BD viva (confirmado via snapshot directo 2026-06-26) |
| 0016–0021 | Criadas localmente — **aplicar manualmente via Supabase SQL Editor** |

> Nota: não existe ficheiro 0015 (número saltado em sessão anterior).

**Itens de melhoria abertos:** 14 (detalhados em `improvements.md`). Nenhum bloqueia o lançamento.
**Próximo:** Hardening — fechar os 14 itens abertos, completar checklist de testes manuais abaixo, decidir data de lançamento.

## Testes manuais pendentes — 8E.4
- [ ] Tab "Agendados" — jobs confirmados aparecem corretamente (filtro client-side)
- [ ] Tab "Concluídos" — jobs completed aparecem, "Carregar mais" funciona
- [ ] Marcar como concluído → job desaparece de "Agendados" sem refresh manual
- [ ] Notificações — badge mostra só não lidas, "Limpar" não dá flash vazio
- [ ] Pull-to-refresh em "Os meus jobs" → reseta paginação e recarrega tudo

## Fases

### Fase 0 — Memória do projeto ✅
- [x] `docs/project_overview.md`
- [x] `docs/architecture.md`
- [x] `docs/database_schema.md`
- [x] `docs/implementation_plan.md`
- [x] `docs/decisions_log.md`

### Fase 1 — Bootstrap dos projetos Flutter
- [x] Criar `local_services_app` (`flutter create`).
- [x] Criar `local_services_ui_playground` (`flutter create`).
- [x] Mover `/docs` para dentro de `local_services_app/docs/`.
- [x] Adicionar packages base ao projeto principal: `supabase_flutter`,
      `go_router`, `flutter_riverpod`, `image_picker`, `intl`, `uuid`.
- [x] `flutter analyze` sem erros.

### Fase 2 — Tema e estrutura base
- [x] Criar estrutura de pastas conforme `architecture.md`.
- [x] `core/theme/` — ThemeData Material 3, paleta verde.
- [x] `core/constants/` — enums (`JobStatus`, `ProposalStatus`, etc.).
- [x] `app.dart` — MaterialApp.router placeholder.
- [x] `main.dart` — `ProviderScope` + runApp.

### Fase 3 — Navegação
- [x] `core/router/` — go_router com rotas placeholder.
- [x] Rotas iniciais: `/`, `/login`, `/signup`, `/choose-role`,
      `/client/home`, `/worker/home`.
- [x] Redirect de auth (placeholder; lógica real na Fase 5).

### Fase 4 — Supabase: setup ✅
- [x] Criar projeto Supabase. Guardar URL e anon key.
- [x] `core/config/` — leitura de env via `--dart-define` (decisão: sem flutter_dotenv;
      credenciais em `.vscode/launch.json` no .gitignore — ver decisions_log.md 2026-06-02).
- [x] Inicializar `Supabase.initialize` no `main.dart` (parâmetro `publishableKey:` após fix de deprecation 2026-06-25).
- [x] Smoke test: app conecta e lê tabelas — confirmado em 2026-06-25.

### Fase 5 — Supabase: schema + RLS ✅
- [x] Criar tabelas conforme `database_schema.md` (migrations em `supabase/migrations/`;
      baseline `0001_baseline.sql` — migrations 0001–0014 todas aplicadas à BD viva, confirmado 2026-06-26).
- [x] Ativar RLS e criar políticas (RLS habilitado em todas as 13 tabelas base em 0001;
      políticas expandidas em migrations 0003–0012 — confirmado 2026-06-26).
- [x] Criar buckets de Storage (`job-photos`, `worker-photos`, `avatars` — definidos em 0001).
- [x] Seed mínimo: 1 `service_category` "Jardinagem" + 3 `service_types` ("Corte de relva",
      "Poda", "Limpeza de jardim") — confirmados via query live 2026-06-25.
- [x] Criar funções PL/pgSQL: `create_proposal`, `accept_proposal`, `reject_proposal`
      (resolvem condição de corrida) — presentes e auditadas ao longo das Fases 8–9.

### Fase 6 — Auth
- [x] Feature `auth/`: data + application + presentation.
- [x] Signup / login / logout com Supabase Auth.
- [x] Escolher role (client/worker) → cria registo em `profiles`.
- [x] Redirect real no go_router.

### Fase 7 — Perfil
- [x] Feature `client/`: ver/editar perfil base.
- [x] Feature `worker/`: ver/editar `worker_profiles` (raio, base, ferramentas,
      serviços, fotos).

### Fase 8 — Jobs e Propostas (núcleo do MVP)
- [x] Feature `jobs/`: criar pedido (client), lista de pedidos no raio (worker),
      detalhe do pedido.
- [x] Upload de fotos para `job-photos`.
- [x] Feature `proposals/`: enviar proposta (worker), ver proposta (client),
      aceitar/recusar (client).
- [x] Estado expira_at + job `no_response` após 48h — `auto_expire_jobs()` + cron `'auto-expire-jobs'` em migration 0020 (não aplicada à BD viva).

### Fase 9 — Equipa e ajudantes ✅
> Implementada e aplicada à BD de produção em 2026-06-24.
> Code review completa realizada em 2026-06-24 — ver decisions_log.md para todos os
> findings e fixes aplicados (migrations 0003–0008, 2 fixes Dart).

- [x] Schema: `help_requests`, `help_acceptances`, `helpers_equipment_required` em
      `job_proposals` (migrations 0003–0007).
- [x] RPCs: `approve_help_request`, `accept_help_candidate`, `reject_help_candidate`,
      `get_help_requests_in_radius` (com joins de contexto via migration 0006),
      `withdraw_help_acceptance`, `get_my_help_acceptances` (migrations 0009–0010).
- [x] `cancel_job` faz cascade para `help_requests`/`help_acceptances` (migration 0007).
- [x] RLS completo e auditado: INSERT restrito a candidaturas pending; UPDATE restrito
      a retirada (status='cancelled'); INSERT em `help_requests` apenas para propostas
      accepted; políticas redundantes removidas (migration 0007).
- [x] Lobby screen (worker principal): aceitar/rejeitar candidatos, taxa editável,
      visualização de slots, overflow de candidatos.
- [x] Discovery screen (workers candidatos): `get_help_requests_in_radius` com dados
      de contexto; botão de candidatura; estado local de candidaturas enviadas.
- [x] Estimativa de custo de equipa no detalhe da proposta (cliente), factor 0.75 para
      display vs 0.70 para taxa real.
- [x] Notificações: `help_request_approved`, `help_accepted`, `help_rejected`,
      `help_job_cancelled`, `help_request_reopened`, `help_withdrew` (handler
      + sync provider + constantes em notification_types.dart).
- [x] `agreed_rate` CHECK constraint na BD: `status <> 'accepted' OR agreed_rate > 0`.
- [x] Validação client-side da taxa no lobby antes de chamar `accept_help_candidate`.
- [x] `FilledButton` de aceitação de proposta mostra estilo desativado durante loading.
- [x] Cancelamento em cascade para `help_requests`/`help_acceptances` com notificações
      `help_job_cancelled` ao ser cancelado o job (migration 0009).
- [x] RPC `withdraw_help_acceptance` — ajudante retira candidatura aceite; reabre a
      vaga (`help_request` volta a `open`) e notifica o worker principal com
      `help_withdrew`; notificação `help_request_reopened` ao próprio se reaberto
      (migration 0009).
- [x] RPC `get_my_help_acceptances` + `myHelpAcceptancesProvider` (migration 0010).
- [x] Tab "As minhas candidaturas" na discovery screen do worker candidato.

**Gap intencional de MVP (infraestrutura pronta, sem UI):**
O único gap de UI que resta é a aprovação pelo cliente de help_requests criados
pós-confirmação (`created_post_confirmation = true`, estado `pending_approval`). Toda a
infraestrutura está pronta — RPC `approve_help_request`, política RLS de SELECT para o
cliente, método `approveHelpRequest` no repository — mas nenhum ecrã de UI foi construído
para este fluxo. O `accept_proposal` auto-cria sempre com `created_post_confirmation = false`
(aprovação implícita), por isso este gap não afeta o fluxo MVP principal. A visibilidade
dos helpers (tab "As minhas candidaturas") já está implementada e não é mais um gap.

### Fase 10 — Contactos e conclusão ✅
- [x] Mostrar contactos (WhatsApp/tel) — card de contacto visível ao cliente em
      `confirmed`, `awaiting_confirmation` e `completed`; ao worker em todos os estados
      `accepted` da proposta. RLS confirmado via `client_has_confirmed_job_with_worker`.
- [x] Marcar job como `completed` — `mark_job_done` + `confirm_job_completion` RPCs
      existentes; auto-confirmação após 3 dias via pg_cron (migration 0014 — aplicada, confirmado 2026-06-26).
- [x] Cancelamento até 24h antes (client e worker) — regra na BD via `cancel_job`
      (migration 0013 — aplicada, confirmado 2026-06-26) e UI client-side (botão desativado + mensagem).

### Fase 11 — Avaliações ✅ (2026-06-27)

**Migration:** `0021_ratings_hardening.sql` — aplicar manualmente antes de testar.

**4 relações de avaliação implementadas:**

| Rater | Ratee | RPC | Notas |
|---|---|---|---|
| Cliente | Prestador principal | `submit_client_rating` | Mesmas estrelas propagam; comentário guardado aqui |
| Cliente | Cada ajudante aceite | `submit_client_rating` (auto) | Mesmas estrelas, sem comentário |
| Prestador | Cliente | `submit_principal_rating` | `p_ratee_id = job.client_id` |
| Prestador | Cada ajudante | `submit_principal_rating` | `p_ratee_id = helper.worker_id` |
| Ajudante | Prestador | `submit_helper_rating` | Principal auto-resolvido da `accepted_proposal_id` |

**Decisões de design (2026-06-26):**
- **UX Option A (inline):** sem popup, sem novo tipo de notificação. Card persistente no
  bloco `completed` de cada ecrã de detalhe; o utilizador vê o prompt sempre que volta ao
  trabalho concluído, até avaliar.
- **Propagação do cliente:** uma única ação aplica a mesma nota ao prestador e a cada
  ajudante; o comentário fica só na linha do prestador. `submit_client_rating` itera sobre
  `help_acceptances` em PL/pgSQL — sem round-trips do cliente.
- **Unicidade:** `UNIQUE (job_id, rater_id, ratee_id)` preexistente + novo
  `CHECK (rater_id <> ratee_id)` adicionado em 0021. `ON CONFLICT DO NOTHING` garante
  idempotência (resubmissão não duplica).
- **Sem novo enum:** `NotificationType` não foi alterado; avaliações não geram notificação.
- **`get_accepted_helpers_for_job(p_job_id)`:** novo RPC em 0021 para o prestador principal
  listar ajudantes com nome — usado no card de avaliação por ajudante.
- **`get_my_help_acceptances` atualizado:** adicionadas colunas `job_id` e
  `principal_worker_id`; `HelpAcceptanceSummary` é retrocompatível (default `''` quando
  RPC antigo). Requer `DROP FUNCTION` antes de `CREATE` (não `CREATE OR REPLACE`) por
  mudança de shape do `RETURNS TABLE` — ver nota no ficheiro 0021.

**Dart adicionado:**

| Ficheiro | Conteúdo |
|---|---|
| `ratings/data/rating_model.dart` | `Rating` + `AcceptedHelper` |
| `ratings/data/rating_repository.dart` | 7 métodos: fetch, submit×3, helpers, profile |
| `ratings/application/rating_providers.dart` | `myRatingForJobProvider` (`family<Rating?, String>`), `myRatingForJobAndRateeProvider` (`family<Rating?, (String, String)>` — Dart 3 record), `acceptedHelpersForJobProvider` |
| `ratings/presentation/rating_sheet.dart` | `showRatingSheet()` partilhado (estrelas + comentário opcional) |

**UI por ecrã:**
- [x] `client_job_detail_screen.dart` — bloco `completed`: card "Avaliar o trabalho" →
      bottom sheet → `submit_client_rating` → invalida `myRatingForJobProvider`
- [x] `worker_my_job_detail_screen.dart` — bloco `completed`: banner de conclusão + um
      `_PrincipalRatingCard` (ConsumerStatefulWidget) por ratee — cliente e cada ajudante
      (lista via `acceptedHelpersForJobProvider`)
- [x] `worker_help_requests_screen.dart` — `_AcceptedCard` convertido para
      `ConsumerStatefulWidget`; quando `jobStatus == 'completed'`, mostra
      "Avaliar o prestador" em vez de "Desistir"

**Deferred — pós-MVP (Fase 12+):**
- [ ] Exibir média de estrelas no perfil do worker — `fetchRatingsForProfile` já existe no
      repositório; falta calcular e mostrar no `worker_profile_screen.dart` e nos cards de proposta
- [ ] Ordenação de propostas por rating — `ButtonSegment` desativado em
      `client_job_detail_screen.dart` aguarda dados de avaliação suficientes
- [ ] Resposta pública do worker a uma avaliação — requer nova coluna `reply_text` em
      `ratings` e UI dedicada

### Fase 12 — Integração da UI do Playground / polish pós-MVP
- Integração dos ecrãs do UI Playground (refatoração para Riverpod e repositories).
- Exibição de média de estrelas no perfil do worker.
- Fechar os 14 itens abertos em `improvements.md`.
- Preparação para lançamento público (nome, logo, store listings).

## Regras de execução
- Passos pequenos. Nunca implementar várias fases ao mesmo tempo.
- Antes de cada alteração relevante: commit/checkpoint.
- Depois de cada alteração: `flutter analyze`.
- Cada fase concluída → marcar `[x]` aqui e adicionar entrada relevante em
  `decisions_log.md` se houver decisão técnica.
- Claude Code: ler `docs/` antes de qualquer alteração de código.