# LocalServices — Decisions Log

> Registo de decisões técnicas importantes. Memória entre sessões Browser/Code.
> Formato: data — decisão — motivo.

## 2026-06-02 — Fotos: máximo 2 por job, compressão obrigatória
Supabase Free Plan tem 50mb de storage. Para maximizar espaço:
- Máximo 2 fotos por job_request.
- Compressão obrigatória antes do upload: largura máxima 800px, qualidade 60%.
- Implementar na Fase 8 com o package `flutter_image_compress`.
- Validação no cliente antes do upload (tamanho + número de fotos).

## 2026-06-02 — Credenciais Supabase via --dart-define + launch.json
As credenciais do Supabase (URL e anon key) são passadas via `--dart-define`
em tempo de execução. Configuradas em `.vscode/launch.json` (no .gitignore).
Sem packages extra (flutter_dotenv descartado). O launch.json nunca vai para
o repositório — cada developer configura o seu localmente.

## 2026-06-02 — Domínio "provider" renomeado para "worker"
No código Dart o domínio do prestador chama-se `worker` (não `provider`), para
evitar colisão com Riverpod e `package:provider`. UI mostra "jardineiro";
tabela na BD é `worker_profiles`.

## 2026-06-02 — Organização por feature
Estrutura `features/<feature>/{data,application,presentation}` em vez de
`data/` global. `core/` só para o que é partilhado por 2+ features.

## 2026-06-02 — Estados como enums + constraints
Estados de jobs/propostas são enums centralizados em `core/constants/` e
refletidos como CHECK/constraints na base de dados. Nunca strings soltas.

## 2026-06-02 — Associação de proposta resolvida na BD
"Primeiro worker a enviar proposta válida fica associado" tem condição de
corrida. Garantir na base de dados (transação/constraint), não na app.

## 2026-06-02 — Fase 7: Perfis
- Localização base do worker via GPS (geolocator).
- Foto de perfil para client e worker (câmara ou galeria, imageQuality 70, maxWidth 400).
- Fotos de trabalhos do worker deixadas para pós-MVP.
- Worker obrigado a completar perfil antes de entrar na home (router redirect).
- Serviços selecionados via FilterChips; ferramentas via texto livre.
- Perfil acessível via ícone no AppBar (designer integra navegação depois).

## 2026-06-02 — Auth: registo em 2 ecrãs
Registo dividido em: Ecrã 1 (email, password, nome, telefone) → Ecrã 2 (escolher
role: client ou worker). Perfil criado na tabela `profiles` após escolha de role.
Validações mínimas: email válido, password ≥ 6 chars, nome e telefone não vazios.
Recuperação de password deixada para pós-MVP.

## 2026-06-02 — /docs reduzido a 5 ficheiros
Essenciais: project_overview, architecture, database_schema,
implementation_plan, decisions_log. workflow/ai_roles/design_handoff ficam nos
documentos originais; só se criam aqui se divergirem.

## 2026-06-05 — Fase 7: bugs resolvidos
- Router redirect usava queries async à BD em cada navegação → refatorado para
  `AsyncNotifierProvider` (SessionNotifier) com refresh explícito.
- `currentUserProvider` era cached permanentemente → corrigido com
  `ref.watch(authStateProvider)` para re-avaliar em cada evento de auth.
- `createProfile` usava INSERT direto → substituído por upsert para ser
  idempotente (resolve duplicate key em retries e trigger handle_new_user).
- Worker setup não refrescava a sessão antes de navegar → adicionado
  `await sessionStatusProvider.notifier.refresh()` antes de `context.go`.
- `/choose-role` não estava na lista de rotas permitidas para utilizadores
  não autenticados → adicionado para evitar redirect loop no primeiro registo.
- Confirmação de email Supabase desativada para MVP — reativar antes do launch.

## 2026-06-08 — Fase 8C.1: Pedidos disponíveis (worker)
- Lista de jobs abertos no raio via RPC get_jobs_in_radius (Haversine na BD).
- Distância calculada no cliente (Geolocator.distanceBetween) para exibição.
- Ordenação por distância (da RPC). Morada só mostrada se existir.
- Envio de proposta via RPC create_proposal (resolve condição de corrida).
- Notificações ficam para a Fase 8C.2 (tabela dedicada + triggers + realtime).

## 2026-06-08 — Fase 8A: decisões de criação de pedido
- Localização via flutter_map + GPS + morada texto; pino define coordenadas; sem geocoding.
- Serviço por dropdown (seleção única). Data com opção "flexível" (preferred_date nullable).
- Urgência: toggle (normal/urgent). Tamanho: chips (small/medium/large).
- Fotos comprimidas no cliente a 1280px/qualidade 72% (flutter_image_compress) antes do upload.
- preferred_date passou a nullable. Adicionadas políticas RLS a job_photos e storage (job-photos).
- ServiceType/serviceTypesProvider reutilizados de features/worker por agora; mover para shared no futuro se necessário.

## 2026-06-09 — Fase 8B: decisões de lista e detalhe de pedidos (cliente)
- Proposta aceite/recusada via update direto nas tabelas (não RPC) — suficiente para MVP single-user.
- cancelJob faz update direto (status→cancelled); não usa RPC para MVP.
- JobProposal.fetchProposalById adicionado para suportar secção "confirmado" quando a tela é aberta diretamente (não só após aceitar na sessão atual).
- workerBasicInfoProvider usa sentinel string vazia → fetchWorkerBasicInfo devolve {} imediatamente — evita ref.watch condicional.
- Contacto WhatsApp: limpa espaços/hífens do telefone, abre wa.me/<número> em app externa; requer package android.name="com.whatsapp" em queries.
- _statusInfo duplicado em client_jobs_screen e client_job_detail_screen (funções top-level privadas) — sem abstração partilhada para MVP.
- url_launcher adicionado (já era dependência transitiva via supabase_flutter; promovido a dependência direta).

## 2026-06-11 — Fase 8C.2: Sistema de notificações
- Tabela `notifications` dedicada na BD (user_id, type, title, body, related_id, related_type, read).
- Triggers na BD para: novo job no raio (workers), proposta recebida (cliente),
  proposta aceite/recusada (worker).
- Realtime via Supabase stream — um canal por utilizador, subscrito em notificationsStreamProvider.
- NotificationType: constantes centralizadas para todos os tipos.
- NotificationHandler: routing centralizado ao toque na notificação.
- notificationSyncProvider: invalida providers relevantes quando chegam notificações novas.
- Badge de contagem não lidas no sino do AppBar (Material 3 Badge widget).
- Extensível: novos tipos requerem apenas nova constante + caso no NotificationHandler.

## 2026-06-11 — Fase 8C.1 bugfixes + geocoding + horas como intervalo
- Bug: fetchWorkerBasicInfo usava .single() → PGRST116 quando perfil não existe; corrigido para .maybeSingle() com retorno {} em null.
- Bug: ecrã de detalhe do cliente mostrava morada vazia; corrigido com addressText.isNotEmpty nos dois ecrãs de cliente (detalhe e lista).
- Bug: secção "confirmado" no detalhe do cliente mostrava loading infinito em caso de erro; corrigido com handler explícito "Não foi possível carregar o contacto." para erro e para map vazio quando workerId ainda não foi resolvido.
- Horas estimadas na proposta passaram de valor único para intervalo (min/max); DB precisa de colunas estimated_hours_min e estimated_hours_max em job_proposals e função RPC create_proposal atualizada (TODO marcado).
- Geocoding adicionado ao ecrã de criação de pedido: botão de pesquisa no campo de morada move o pino no mapa para o resultado (package geocoding 4.0.0).

## 2026-06-11 — Fase 8D: Worker "Os meus jobs"
- `fetchWorkerProposalsWithJobs` em ProposalRepository: join `job_proposals` + `job_requests` numa query (select('*, job_requests(*)')).
- `markJobCompleted` em ProposalRepository: update direto em `job_requests` (não RPC) — suficiente para MVP single-user, igual ao padrão de cancelJob.
- `fetchClientBasicInfo` em ClientRepository: busca `full_name` e `phone` da tabela `profiles` para o worker ver o contacto do cliente.
- `workerProposalsProvider`: FutureProvider que usa `currentUserProvider` (watch) + `proposalRepositoryProvider` (read) — consistente com outros providers da app.
- `clientBasicInfoProvider`: FutureProvider.family com sentinel string vazia (retorna imediatamente sem chamada à BD) — mesmo padrão que workerBasicInfoProvider.
- WorkerJobsScreen: DefaultTabController (Ativos / Histórico); parsing de List<Map> com records Dart 3 `(JobProposal, JobRequest)`; distância calculada no cliente com Geolocator.
- `_isActive`: proposta rejected ou superseded → histórico; job completed/cancelled → histórico; resto → ativo.
- WorkerMyJobDetailScreen: recebe proposal + job via GoRouter extra; secções distintas por ProposalStatus (accepted/rejected/pending); "Marcar como concluído" invalida workerProposalsProvider + jobsInRadiusProvider e navega para /worker/home.
- Rota `/worker/my-job/:id` dentro do worker ShellRoute — índice da tab bar não muda ao navegar para ela (startsWith('/worker/jobs') não corresponde a '/worker/my-job/').

## 2026-06-12 — Fase 8E.1: Agendamento
- Cliente escolhe date_mode: fixed / flexible / availability (texto dedicado).
- Proposta do worker inclui scheduled_date + scheduled_time (+ scheduled_flexible para horário flexível no dia).
- Ao aceitar, scheduled_* é copiado para confirmed_* no job (via RPC).
- Novo estado awaiting_confirmation adicionado ao enum JobStatus (para conclusão a dois lados, 8E.4).
- create_proposal e accept_proposal DB functions precisam de atualização (TODO marcado no repository).

## 2026-06-14 — Múltiplas propostas por pedido (remoção de proposal_received)
- Removido modelo "primeiro a chegar" — job mantém-se `open` com N propostas pending.
- Removido status `proposal_received` do enum JobStatus (compat: `fromValue` mapeia o valor legado de BD para `open`).
- Campo `proposal_count` adicionado a `job_requests` e ao modelo JobRequest (default 0).
- Cliente vê lista de propostas ordenável (preço / avaliação futura Phase 11).
- Aceitar uma proposta rejeita automaticamente as restantes (via `accept_proposal` RPC).
- Worker vê quantas propostas existem no job (`proposal_count` chip) e se já enviou uma (`workerProposalForJobProvider`).
- Retirar proposta via `withdraw_proposal` RPC (decrementa proposal_count + notifica cliente).
- `proposalWithdrawn` adicionado a NotificationType + notificationSyncProvider + notificationHandler.
- Rejeitadas passam a exibir "Não selecionada" em vez de "Recusada" na UI do worker.
- `proposalForJobProvider` substituído por `pendingProposalsForJobProvider` + `acceptedProposalForJobProvider`.
- `fetchWorkerName` adicionado a WorkerRepository; `workerNameProvider` adicionado a worker_providers.dart.

## 2026-06-09 — Tab bar navigation (client + worker)
- 5-tab NavigationBar (Material 3) para client e worker.
- Tab central (+): client faz push /client/create-job sem alterar índice selecionado; worker mostra bottom sheet "Em breve" sem alterar índice.
- ShellRoute envolve rotas de client e worker — NavigationBar persiste entre screens.
- Índice selecionado derivado de GoRouterState.of(context).matchedLocation (sem estado local).
- /client/messages e /worker/messages e /worker/jobs são rotas placeholder (_PlaceholderScreen) dentro do ShellRoute.
- _PlaceholderScreen definido no app_router.dart (file-private) e referenciado pelas rotas; shell files mantêm cópia privada anotada com ignore:unused_element para facilitar futura migração para StatefulShellRoute.
- Client home mostra últimos 3 pedidos ativos com link "Ver todos"; cumprimento usa primeiro nome de clientProfileProvider.
- FAB e ícone de perfil no AppBar removidos das home screens — substituídos pela NavigationBar.
- flutter/foundation.dart removido do router (flutter/material.dart é superset).