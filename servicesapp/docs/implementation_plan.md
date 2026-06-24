# LocalServices — Implementation Plan

> Ordem de trabalho e estado atual. Atualizar à medida que se avança.
> O Claude Code lê este ficheiro para saber em que passo está.

## Estado atual
**Passo concluído:** Fase 9 — Equipa e ajudantes. Implementada, revistada e aplicada à BD de produção (2026-06-24). Migrations 0001–0010 todas aplicadas à BD viva.
**Próximo passo:** Fase 10 — Contactos e conclusão (ou definir próxima fase).

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

### Fase 4 — Supabase: setup
- [ ] Criar projeto Supabase. Guardar URL e anon key.
- [ ] `core/config/` — leitura de env (`.env` + `flutter_dotenv` OU
      `--dart-define`; decisão a registar em `decisions_log.md`).
- [ ] Inicializar `Supabase.initialize` no `main.dart`.
- [ ] Smoke test: ligar e ler tabela vazia.

### Fase 5 — Supabase: schema + RLS
- [ ] Criar tabelas conforme `database_schema.md` (via SQL editor; guardar
      ficheiro SQL em `local_services_app/supabase/migrations/`).
- [ ] Ativar RLS e criar políticas.
- [ ] Criar buckets de Storage.
- [ ] Seed mínimo: 1 `service_category` (Jardinagem) + 3 `service_types`.
- [ ] Criar funções PL/pgSQL: `create_proposal`, `accept_proposal`,
      `reject_proposal` (resolvem condição de corrida).

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
- [ ] Estado expira_at + job `no_response` após 48h (cron Supabase ou função).

### Fase 9 — Equipa e ajudantes ✅
> Implementada e aplicada à BD de produção em 2026-06-24.
> Code review completa realizada em 2026-06-24 — ver decisions_log.md para todos os
> findings e fixes aplicados (migrations 0003–0008, 2 fixes Dart).

- [x] Schema: `help_requests`, `help_acceptances`, `helpers_equipment_required` em
      `job_proposals` (migrations 0003–0007).
- [x] RPCs: `approve_help_request`, `accept_help_candidate`, `reject_help_candidate`,
      `get_help_requests_in_radius` (com joins de contexto via migration 0006).
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
- [x] Notificações: `help_request_approved`, `help_accepted`, `help_rejected` (handler
      + sync provider + 3 constantes em notification_types.dart).
- [x] `agreed_rate` CHECK constraint na BD: `status <> 'accepted' OR agreed_rate > 0`.
- [x] Validação client-side da taxa no lobby antes de chamar `accept_help_candidate`.
- [x] `FilledButton` de aceitação de proposta mostra estilo desativado durante loading.

**Gap intencional de MVP (infraestrutura pronta, sem UI):**
A aprovação pelo cliente de help_requests criados pós-confirmação (`created_post_confirmation
= true`, estado `pending_approval`) tem toda a infraestrutura de dados pronta — RPC
`approve_help_request`, política RLS de SELECT para o cliente, método `approveHelpRequest`
no repository — mas nenhum ecrã de UI foi construído para este fluxo. O `accept_proposal`
auto-cria sempre com `created_post_confirmation = false` (aprovação implícita), por isso
este gap não afeta o fluxo MVP principal.

### Fase 10 — Contactos e conclusão
- [ ] Mostrar contactos (WhatsApp/tel) só após `confirmed`.
- [ ] Marcar job como `completed`.
- [ ] Cancelamento até 24h antes (client e worker).

### Fase 11 — Avaliações
- [ ] Feature `ratings/`: client avalia worker principal; worker avalia ajudantes.
- [ ] Exibir média de estrelas no perfil do worker.

### Fase 12 — Integração da UI do Playground
- Ao longo das Fases 6–11, à medida que os ecrãs vão saindo do UI Playground,
  o Tech Lead integra-os refatorando para usar Riverpod e repositories.

## Regras de execução
- Passos pequenos. Nunca implementar várias fases ao mesmo tempo.
- Antes de cada alteração relevante: commit/checkpoint.
- Depois de cada alteração: `flutter analyze`.
- Cada fase concluída → marcar `[x]` aqui e adicionar entrada relevante em
  `decisions_log.md` se houver decisão técnica.
- Claude Code: ler `docs/` antes de qualquer alteração de código.