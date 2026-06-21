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

## 2026-06-15 — Fase 8E.2 + 8E.3: Cancelamento e Remarcação
- Dois botões separados: Remarcar e Cancelar (não um menu).
- 4 razões de cancelamento (cliente vê 4, worker vê 3 — sem "já não preciso").
- Auto-reabertura: cliente máx 1 reabertura, worker máx 2; cria novo job (id diferente) com reopened_from.
- cancelJob usa RPC `cancel_job`; retorna novo job ID se reaberto, null caso contrário.
- proposeReschedule/acceptReschedule/rejectReschedule via RPCs homónimas.
- Regra das 24h aplica-se a cancelamento E remarcação (validado na BD).
- Remarcação: campos no próprio job (uma pendente de cada vez); quem propõe não pode aceitar.
- Client detail: após reschedule propose/accept/reject, actualiza _job local via copyWith.
- Worker detail: após qualquer ação de reschedule/cancel, navega back (widget.job é estático).
- currentUserIdProvider adicionado a auth_providers.dart para comparação de rescheduleProposedBy.
- RadioGroup (Flutter 3.32+) substitui groupValue/onChanged no RadioListTile.
- Null-aware element `?expr` em collection literals (Dart 3.4+) usado em detailChildren.

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

## 2026-06-14 — Tabs internas (cliente) e 3 tabs (worker)
- Cliente: detalhe do job tem 2 tabs (Detalhes / Propostas) só quando status == open.
  Outros estados: vista única sem tabs.
- Worker: "Os meus jobs" tem 3 tabs (Por confirmar / Agendados / Concluídos).
- Excluídos dos workers: rejected, superseded, cancelled, no_response — são ruído.

## 2026-06-15 — Bug fixes pós-testes
- Removido trigger on_proposal_updated (duplicava notificações de aceite/rejeição
  com as RPCs accept_proposal e reject_proposal).
- markJobCompleted migrado para RPC mark_job_done.
- Jobs open cancelados excluídos do histórico do cliente.
- awaitingConfirmation movido para tab Ativos (era Histórico).
- Cancelar job open: dialog simples sem justificação.
- Mensagem de erro de proposta duplicada melhorada.
- cancel_job RPC actualizado: cancelled_worker_id e excluded_worker_ids
  para blacklist de workers após 2 cancelamentos.
- get_jobs_in_radius exclui workers em excluded_worker_ids.
- Storage RLS para avatars corrigida (Bug 1 — feito na BD).

## 2026-06-16 — Optimizações de performance e UX
- App mostrava login ao abrir: corrigido com rota /loading enquanto sessão resolve.
- Splash preso ao minimizar: corrigido com WidgetsBindingObserver em App que
  invalida sessionStatusProvider apenas no resume, não em cada build.
- Jobs onde worker já tem proposta pending removidos da lista home (filtro
  client-side em fetchJobsInRadius — futura melhoria: mover para RPC).
- N+1 queries nos chips da lista home eliminados: workerProposalForJobProvider
  removido de _JobCard; lista mostra apenas contagem total de propostas.

## 2026-06-18 — Fase 8E.4 — Conclusão a dois lados
- proposal_repository: confirmJobCompletion (confirm_job_completion RPC) e reportJobProblem (insert em job_reports).
- job_repository: fetchJobById; job_providers: jobByIdProvider (FutureProvider.family).
- client_job_detail_screen: secção awaiting_confirmation — card informativo + botão confirmar (AlertDialog → RPC → go('/client/jobs')) + botão reportar problema (ModalBottomSheet com StatefulBuilder → RPC → snackbar → follow-up dialog).
- worker_my_job_detail_screen: liveJobStatus via jobByIdProvider; awaiting_confirmation mostra card "Aguarda confirmação do cliente"; confirmed mostra botão "Marcar como concluído".
- notification_providers: jobMarkedDone invalida clientJobsProvider + jobByIdProvider; jobCompleted invalida workerProposalsProvider + jobByIdProvider.
- notification_handler: jobMarkedDone e jobCompleted navegam para /client/jobs ou /worker/home conforme role.

## 2026-06-18 — Performance: notificações e workerProposals
- notificationsStreamProvider filtra só não lidas: stream leve, não dispara ao marcar lidas.
- allNotificationsProvider: fetch estático para histórico completo no ecrã de notificações.
- Ecrã de notificações: secções "Novas" / "Anteriores", botão "Limpar" manual.
- workerProposalsProvider dividido em 3 providers por tab (pending/scheduled/completed).
- Tab Concluídos paginada (20 items por página, "Carregar mais").
- Filtragem movida para a BD (queries focadas por estado).

## 2026-06-18 — Performance review fixes
- fetchScheduledWorkerProposals e fetchCompletedWorkerProposals: filtro client-side em vez de joined column filter (comportamento Supabase Dart não verificado para embedded resources).
- invalidateAllWorkerProposalProviders helper criado para invalidar os 3 providers em conjunto.
- worker_my_job_detail_screen: todas as 6 invalidações corrigidas para os providers corretos por ação.
- Paginação: ref.listen em worker_jobs_screen.dart reseta estado quando provider é invalidado externamente.
- "Limpar" notificações: _optimisticClear elimina flash de lista vazia entre tap e resposta da BD.
- allNotificationsProvider invalidado no final de cada ciclo de notificationSyncProvider.

## 2026-06-19 — job_reports: política SELECT em falta corrigida
Durante a revisão do baseline de migrations detectou-se que a tabela `job_reports`
tinha política de INSERT mas nenhuma de SELECT para utilizadores autenticados.
Um reporter que submetesse um report não conseguia depois ler de volta os seus
próprios registos — o que bloquearia qualquer futura UI de "os meus reports".
Corrigido em `supabase/migrations/0002_job_reports_select_policy.sql`:
`CREATE POLICY "Utilizador vê os seus reports" ON job_reports FOR SELECT USING (auth.uid() = reporter_id);`
SELECT de reports de outros utilizadores continua restrito ao service_role
(acesso via Supabase Studio para moderação). Não há alteração ao código Dart.

## 2026-06-19 — Exclusão de workers em jobs reabertos
Implementado via dois campos em `job_requests`: `cancelled_worker_id` (uuid nullable)
e `excluded_worker_ids` (uuid[], default `'{}'`).
- `cancel_job` RPC guarda o worker cancelador em `cancelled_worker_id` e acrescenta-o
  a `excluded_worker_ids` no job reaberto.
- `get_jobs_in_radius` filtra jobs onde `auth.uid() = ANY(excluded_worker_ids)`.
- A generalização para array (`excluded_worker_ids`) em vez de campo único
  (`cancelled_worker_id` sozinho) permite futuramente excluir múltiplos workers
  (ex: após vários cancelamentos sucessivos no mesmo job reaberto). O campo
  `cancelled_worker_id` mantém-se para auditoria do cancelador específico.
- Dart model (`JobRequest`) mapeia ambos os campos; lógica de exclusão fica
  inteiramente no lado da BD, a app não filtra client-side.

## 2026-06-19 — Reporting de problemas (job_reports)
Implementado via tabela `job_reports` (job_id, reporter_id, description, created_at).
- `reportJobProblem` em `ProposalRepository` faz INSERT direto (não via RPC) com
  `reporter_id = auth.currentUser.id`.
- UI: botão "Reportar problema" no `client_job_detail_screen` quando job está em
  `awaiting_confirmation`; abre bottom sheet com campo de descrição (mín. 10 chars);
  após submit, snackbar + follow-up dialog a perguntar se quer confirmar conclusão
  na mesma.
- RLS: política de INSERT permite ao utilizador autenticado inserir registos onde
  `reporter_id = auth.uid()`. SELECT restrito (TODO: confirmar política exacta nas
  migrations — sem ficheiros SQL no repositório para verificar).
- A tabela foi nomeada `job_reports` (não `reports`) para ser específica ao domínio
  de jobs. O campo original em `improvements.md` referia uma tabela genérica `reports`
  — optámos por escopo mais restrito no MVP.

## 2026-06-19 — jobByIdProvider: invalidações em falta no notificationSyncProvider
`jobByIdProvider` não era invalidado para 5 tipos de notificação, descoberto
durante a code review da 8E.5 (timeline de estados). Efeito: ecrãs de detalhe
de job mantinham dados stale (confirmed_date, reschedule_status, job status)
enquanto o utilizador estava no ecrã e o outro lado efectuava uma acção.
Mais crítico: rescheduleAccepted — o campo confirmed_date muda e o badge
"Remarcação pendente" ficava exibido indefinidamente.
Corrigido adicionando `ref.invalidate(jobByIdProvider)` (forma broad, sem key
de família — consistente com jobMarkedDone/jobCompleted já existentes) aos
casos: `rescheduleProposed`, `rescheduleAccepted`, `rescheduleRejected`,
`proposalAccepted`, `jobCancelled`/`jobReopened` (case partilhado).
A tabela de providers em `docs/state_machine.md` foi também corrigida:
`workerProposalsProvider` (nome fictício) substituído pelos nomes reais
`pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`,
`completedWorkerProposalsProvider`.

## 2026-06-21 — Fase 9 data layer: help_acceptance_status expandido
- `help_acceptance_status` alargado de `accepted|cancelled` para
  `pending|accepted|rejected|cancelled` (migration 0004).
- `pending`: estado inicial quando worker se candidata (applyToHelpRequest).
  Necessário para o modelo lobby onde o principal escolhe entre candidatos.
- `rejected`: novo estado quando o principal recusa um candidato (não confundir
  com `cancelled` que é retirada pelo próprio candidato).
- Ordem deliberada espelha ProposalStatus: pending → accepted/rejected → cancelled.
- `accept_help_candidate` atualizado para verificar status = 'pending' antes
  de aceitar (idempotência — previne aceitar o mesmo candidato duas vezes).
- Nova RPC `reject_help_candidate`: verifica caller = principal worker, verifica
  status = 'pending', atualiza para 'rejected', insere notificação 'help_rejected'.
- Três novos notification types adicionados: `help_request_approved`,
  `help_accepted`, `help_rejected` (constantes em notification_types.dart).
- RLS em help_acceptances completado: INSERT só pelo próprio worker com
  status = 'pending'; SELECT por candidatos (próprias linhas) e pelo principal
  (todas as candidaturas dos seus help_requests via is_principal_worker_for_help_request).
- `applyToHelpRequest` em HelpRequestRepository: INSERT com agreed_rate = 0
  (placeholder; o valor real é definido pelo principal via accept_help_candidate).

## 2026-06-19 — Design da Fase 9 (Equipa e ajudantes)
Design de dados aprovado. Implementação aguarda sessão de design de UI/notificações.

1. **Sem tipo de conta "helper" separado.** Qualquer worker pode candidatar-se a
   ajudar noutro job. A diferença é por participação (brought_equipment), não por
   tipo de pessoa.

2. **Rate do ajudante determinado por equipamento.**
   - Se `equipment_required = true` no help_request: o candidato tem obrigatoriamente
     de trazer equipamento → rate cheio (igual ao do principal).
   - Se `equipment_required = false`: o candidato PROPÕE se leva equipamento ou não
     (com o rate correspondente) e o principal escolhe entre os candidatos — modelo
     "tipo um lobby" (terminologia do Henrique). O principal decide quem aceita, não
     é primeiro-a-chegar.

3. **Critérios mistos no mesmo job resolvidos com múltiplos help_requests.**
   Em vez de slots individuais dentro de um único help_request com critérios mistos,
   publicam-se múltiplos help_requests separados (um por critério). Mantém a estrutura
   simples e reutiliza o suporte já existente a múltiplas linhas por job_id.

4. **Aprovação do cliente depende do momento de criação.**
   - Criado como parte da proposta original aceite (`created_post_confirmation = false`)
     → aprovação implícita, começa diretamente em `open`.
   - Criado depois do job já `confirmed` (`created_post_confirmation = true`) → começa
     em `pending_approval`; só passa a `open` após o cliente aprovar explicitamente
     via RPC `approve_help_request`.

5. **Estimativa de custo extra na proposta inicial.** Quando `people_needed > 1`, a
   app destaca ao cliente: `(people_needed - 1) × hourly_rate × 0.7 × estimated_hours`
   (taxa padrão 70% por ajudante sem equipamento). Sempre como estimativa; o custo
   real fica registado em `help_acceptance.agreed_rate` no momento da aceitação.

6. **`agreed_rate` guardado no momento, nunca recalculado.** Protege o histórico de
   pagamentos contra alterações futuras à regra dos 70%. Mesmo que a percentagem
   default mude no futuro, aceitações passadas refletem o valor acordado na altura.

UI e fluxo de notificações ainda NÃO foram desenhados — ficam para uma sessão de
design futura antes de qualquer implementação.

## 2026-06-19 — Duas ideias de produto registadas em improvements.md
Carteira digital de cartões de benefícios (combustível/seguro): visão de
longo prazo, bloqueada por decisão de negócio (nenhuma parceria fechada),
sem integração NFC/pagamento — versão viável é foto do cartão + campos
texto, mostrado em full-screen para leitura manual. Não avançar antes de
parceria real.
Perfil de worker visitável em 3 camadas: Camada 1 (perfil read-only dentro
da app, RLS a partir de proposta pending, ecrã único com modo próprio/visitante,
sem expor base_lat/base_lng) pode iniciar a qualquer momento. Camadas 2
(portfólio) e 3 (feed na home) sequenciais. Relacionado com "Perfil público
partilhável" mas distinto: esse é partilha fora da app, este é visibilidade
dentro. Nenhuma implementação feita — só registo de visão e decisões de scope.

## 2026-06-16 — Polish e fixes pré-8E.4
- workerProposalForJobProvider: guard para userId vazio + watch reactivo via currentUserIdProvider.
- proposalWithdrawn invalida jobsInRadiusProvider (job volta à lista disponível) e workerProposalForJobProvider.
- Mensagens de erro: helper friendlyError centralizado em core/utils/error_utils.dart; substitui todos os 'Erro: $e' raw.
- Preço €0/null: substituído por "Preço a definir" em client_job_detail, worker_my_job_detail, worker_jobs list; perfil e proposta sheet ignoram rate ≤ 0.
- Datas verificadas: formato dd/MM/yyyy em todos os DateFormat; hora explicitamente HH:mm (padLeft) em reschedule_dialog.
- worker_jobs_screen pull-to-refresh invalida também jobsInRadiusProvider.