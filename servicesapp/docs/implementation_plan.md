# LocalServices — Implementation Plan

> Ordem de trabalho e estado atual. Atualizar à medida que se avança.
> O Claude Code lê este ficheiro para saber em que passo está.

## Estado atual
**Passo concluído:** 8B — Os meus pedidos (cliente).
**Próximo passo:** 8C — Pedidos disponíveis (worker).

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
- [ ] Feature `jobs/`: criar pedido (client), lista de pedidos no raio (worker),
      detalhe do pedido.
- [ ] Upload de fotos para `job-photos`.
- [ ] Feature `proposals/`: enviar proposta (worker), ver proposta (client),
      aceitar/recusar (client).
- [ ] Estado expira_at + job `no_response` após 48h (cron Supabase ou função).

### Fase 9 — Equipa e ajudantes
- [ ] Feature `help_requests/`: pedir ajudantes (worker principal),
      aprovação da equipa pelo client antes de confirmar.
- [ ] Listagem de help_requests no raio (workers candidatos).
- [ ] Aceitar/cancelar vaga; reabertura automática.

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