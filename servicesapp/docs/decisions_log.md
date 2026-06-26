# LocalServices — Decisions Log

> Registo de decisões técnicas importantes. Memória entre sessões Browser/Code.
> Formato: data — decisão — motivo.

## 2026-06-26 — Sincronização total via schema snapshot direto da BD viva

### Método
Query SQL única (UNION ALL 7 secções) executada directamente no SQL Editor do Supabase e gravada em `schema_snapshot_2026-06-26.csv`. Resultado: 1 339 linhas cobrindo tabelas, constraints, índices, funções (corpos completos), políticas RLS, triggers, storage buckets e cron jobs. Ficheiro apagado após sync (era artefacto temporário).

### Achado crítico — migrations 0011–0014 confirmadas todas aplicadas

Anteriormente os docs diziam que 0011–0014 estavam apenas escritas localmente. A BD viva prova o contrário:

| Migration | Evidência no snapshot |
|---|---|
| 0011 | `get_jobs_in_radius` só existe na versão de 4 parâmetros; overload antigo de 3 parâmetros ausente |
| 0012 | políticas de `job_proposals` sem duplicados; política SELECT "Worker candidato vê help requests onde se candidatou" presente |
| 0013 | corpo de `cancel_job` contém a regra das 24h (`IF v_job.status = 'confirmed' AND v_job.confirmed_date IS NOT NULL AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN RAISE EXCEPTION '...'`) |
| 0014 | função `auto_confirm_completed_jobs` presente; registo `auto-confirm-completed-jobs` activo em `cron.job` com schedule `0 */3 * * *` |

Todos os docs actualizados para reflectir estado real: `database_schema.md`, `implementation_plan.md`.

### Overloads — nenhum encontrado

23 funções no schema público, todas com exactamente uma versão. Não há `⚠ OVERLOAD` no snapshot. Histórico de overloads limpo.

### Correcção de correcção — size_estimate CHECK

A entrada de 2026-06-25 neste log registou: "migration 0001 inclui CHECK (size_estimate IN ('small', 'medium', 'large')). Corrigido." Essa correcção estava **errada**: o snapshot directo da BD mostra claramente que `job_requests` não tem nenhuma constraint CHECK sobre `size_estimate`. A validação é exclusivamente do lado do Dart via enum `SizeEstimate`. `database_schema.md` corrigido novamente para dizer "sem CHECK na BD viva".

### P-8-4 (auth bypass em reschedule RPCs) — estado definitivo

| Função | Estado |
|---|---|
| `propose_reschedule` | **Corrigido na BD viva** — corpo tem verificação completa `v_is_client` / `v_is_worker` / `not (v_is_client or v_is_worker) → RAISE`. `p_new_time` é `time without time zone` (não `text` como em 0001_baseline.sql). Ambas as alterações foram feitas interactivamente na BD, sem migration registada. |
| `accept_reschedule` | **Corrigido na BD viva** — mesmo padrão de verificação de autorização. |
| `reject_reschedule` | **Ainda vulnerável** — só verifica `reschedule_proposed_by = auth.uid()` (quem propôs não pode rejeitar). Não verifica se o caller é o cliente ou o worker do job. Qualquer utilizador autenticado que conheça o `job_id` pode rejeitar uma remarcação pendente. Flagged em `database_schema.md` para triage. |

### P-FA4 (job_proposals UPDATE sem WITH CHECK) — ainda aberto

A política `[UPDATE] Worker atualiza as suas propostas` tem `check=[ — ]` (sem WITH CHECK). Confirmado no snapshot. Não foi corrigido. Flagged em `database_schema.md`.

### P-10-1 — falso alarme confirmado definitivamente

`client_has_confirmed_job_with_worker` corpo live:
```sql
select exists (
  select 1 from public.job_requests jr
  join public.job_proposals jp on jp.id = jr.accepted_proposal_id
  where jr.client_id = auth.uid()
  and jp.worker_id = client_has_confirmed_job_with_worker.worker_id
  and jr.status in ('confirmed', 'awaiting_confirmation', 'completed')
);
```
Inclui os três estados. O card de contacto do worker funciona correctamente em todos eles. P-10-1 é falso alarme confirmado — fechar no triage.

### Outros achados documentados

- `profiles.phone` é `nullable` na BD viva (não estava documentado) — corrigido em `database_schema.md`.
- `worker_profiles.base_lat` / `base_lng` são NOT NULL — adicionado à doc.
- `confirmed_flexible` não tem default de coluna (só COALESCE na RPC) — corrigido.
- `worker-photos` storage bucket: **zero políticas RLS** — bucket existe mas upload via API falha. Bucket criado como stub para fotos de trabalho do worker (pós-MVP). Documentado em `database_schema.md`.
- Trigger `on_job_created` (AFTER INSERT em `job_requests` → `notify_workers_new_job()`) adicionado ao `database_schema.md` numa nova secção Triggers.
- Funções internas `client_has_confirmed_job_with_worker`, `is_principal_worker_for_help_request`, `notify_workers_new_job` documentadas em `database_schema.md`.
- Gap C3.2 ainda aberto: worker principal e cliente não têm política SELECT para `help_requests` em estado `open`/`filled`. Documentado em RLS section.

---

## 2026-06-26 — P-8-4 e P-FA4 corrigidos (migration 0016)

### Contexto

Dois gaps de segurança confirmados via corpo exacto de cada função no snapshot directo da BD (`schema_snapshot_2026-06-26.csv` — `pg_get_functiondef`), não inferidos de ficheiros de migration.

### P-8-4 — `reject_reschedule` sem verificação de autorização

`propose_reschedule` e `accept_reschedule` já tinham a verificação completa de que o caller é o cliente ou o worker aceite do job (padrão `v_is_client` / `v_is_worker` / `if not (v_is_client or v_is_worker) then raise exception 'Não autorizado'`). Estas foram provavelmente corrigidas interactivamente na BD numa sessão anterior não registada explicitamente neste log.

`reject_reschedule` não tinha essa verificação — apenas bloqueava o próprio proponente (`if v_job.reschedule_proposed_by = v_user_id then raise`). Qualquer utilizador autenticado que conhecesse o `job_id` e não fosse o proponente podia rejeitar remarcações alheias.

**Correcção (migration 0016):** corpo de `reject_reschedule` substituído por `CREATE OR REPLACE FUNCTION` copiando o padrão de `accept_reschedule` — adiciona as duas variáveis `v_is_client` / `v_is_worker` e o bloco `if not (v_is_client or v_is_worker) then raise exception 'Não autorizado'` antes de qualquer efeito na BD.

### P-FA4 — `job_proposals` UPDATE sem `WITH CHECK`

A política `"Worker atualiza as suas propostas"` tinha `USING (auth.uid() = worker_id)` mas nenhum `WITH CHECK`. Um worker podia fazer UPDATE directo via REST API em qualquer coluna da sua proposta (incluindo `status = 'accepted'`, `status = 'rejected'`, `hourly_rate`, etc.), contornando completamente as RPCs e toda a lógica de negócio associada.

**Correcção (migration 0016):** política recriada com `WITH CHECK (auth.uid() = worker_id AND status = 'superseded')`. O único estado que o worker pode escrever directamente via REST é `superseded` (retirada de proposta). Todas as outras transições (`accepted`, `rejected`) são feitas por RPCs `SECURITY DEFINER` que contornam RLS — ficam inalteradas.

### Estado

**migration 0016 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

Após aplicar, verificar:
```sql
-- Confirmar corpo de reject_reschedule tem ambas as variáveis v_is_client/v_is_worker
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'reject_reschedule';

-- Confirmar WITH CHECK na nova política
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'job_proposals' AND cmd = 'UPDATE';
```

---

## 2026-06-25 — Verificação retroativa das Fases 0–7

Verificação completa e independente das Fases 0–7 (marcadas `[x]` no plano mas nunca
auditadas contra o estado real do código e da BD viva). Resultado: **nenhum gap funcional**
encontrado — ao contrário das Fases 8–10, que tinham gaps reais (contactos limitados a
`confirmed`, 24h rule ausente de `cancel_job`, etc.).

**4 issues de documentação corrigidos nesta sessão:**
1. `implementation_plan.md` — Fase 4: todos os itens estavam `[ ]` (não marcados). Corrigido.
2. `implementation_plan.md` — Fase 5: todos os itens estavam `[ ]` (não marcados). Corrigido.
3. `implementation_plan.md` — Fase 10: todos os itens estavam `[ ]` apesar de implementados hoje. Corrigido.
4. `database_schema.md` — `size_estimate`: dizia "sem CHECK na BD viva" mas migration 0001
   inclui `CHECK (size_estimate IN ('small', 'medium', 'large'))`. Corrigido.

**Nota informativa — `create_user_profile` RPC:** existe na BD (migration 0001, linha 473)
mas nunca é chamado pelo código Dart. A app usa `from('profiles').upsert(...)` diretamente,
autorizado pela política INSERT em `profiles`. A própria migration documenta esta escolha:
*"The Dart app currently uses a direct upsert on profiles; this function is kept for
DB-level or admin use."* Não é um bug — é uma decisão de implementação intencional.

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

## 2026-06-24 — Fase 9: helpers_equipment_required + estimativa de custo de equipa

### Campo helpers_equipment_required em job_proposals
- Nova coluna `helpers_equipment_required boolean NOT NULL DEFAULT false` em
  `job_proposals` (migration 0005).
- Quando `true`, todos os ajudantes devem trazer equipamento → rate cheio (factor 1.0).
- Quando `false`, ajudantes podem ou não trazer equipamento → rate reduzido (factor 0.75).

### Factor de estimativa 0.75 vs pagamento real 0.70
- A estimativa exibida ao cliente usa factor **0.75** (75% do rate do principal).
- O pagamento real acordado com o ajudante sem equipamento é 70% (conforme
  decisions_log 2026-06-19 "Rate do ajudante determinado por equipamento").
- A diferença de 5 p.p. é intencional: serve de buffer para que a estimativa
  que o cliente vê nunca subestime o custo real. `agreed_rate` registado em
  `help_acceptances` é sempre a fonte de verdade do valor acordado.
- Fórmula de estimativa: `hourly_rate × estimated_hours × (1 + (people_needed - 1) × factor)`.
  Exibida como total arredondado ("≈ €120 - €160 (equipa incluída)") no card de
  proposta em `client_job_detail_screen.dart`.

### Overloads obsoletos de create_proposal eliminados (migration 0005)
Dois overloads anteriores ao split de estimated_hours em min/max (2026-06-11)
e à introdução de people_needed (2026-06-08) foram dropados:
- `create_proposal(uuid, uuid, numeric, numeric, integer, text)` — 6 params
- `create_proposal(uuid, uuid, numeric, numeric, numeric, integer, text)` — 7 params
Assinaturas confirmadas na live DB antes do drop.

### accept_proposal auto-cria help_request quando people_needed > 1
- Após confirmar o job, se a proposta aceite tem `people_needed > 1`, a RPC
  cria automaticamente um `help_request` com `slots_needed = people_needed - 1`,
  `equipment_required = helpers_equipment_required`, `created_post_confirmation = false`,
  `status = 'open'`.
- `created_post_confirmation = false` → aprovação implícita (não precisa de
  `approve_help_request`), começa diretamente visível a candidatos.
- Sem alteração ao código Dart de `acceptProposal()` — a criação é transparente
  para o cliente Flutter.

## 2026-06-16 — Polish e fixes pré-8E.4
- workerProposalForJobProvider: guard para userId vazio + watch reactivo via currentUserIdProvider.
- proposalWithdrawn invalida jobsInRadiusProvider (job volta à lista disponível) e workerProposalForJobProvider.
- Mensagens de erro: helper friendlyError centralizado em core/utils/error_utils.dart; substitui todos os 'Erro: $e' raw.
- Preço €0/null: substituído por "Preço a definir" em client_job_detail, worker_my_job_detail, worker_jobs list; perfil e proposta sheet ignoram rate ≤ 0.
- Datas verificadas: formato dd/MM/yyyy em todos os DateFormat; hora explicitamente HH:mm (padLeft) em reschedule_dialog.
- worker_jobs_screen pull-to-refresh invalida também jobsInRadiusProvider.

## 2026-06-24 — Overloads obsoletos descobertos durante deployment de 0002-0007

Descoberto durante a primeira aplicação manual das migrations 0002–0007 à live DB
(nunca tinham sido aplicadas antes desta sessão): o comportamento de
`CREATE OR REPLACE FUNCTION` em PostgreSQL cria um **novo overload** quando a lista
de parâmetros muda — não substitui a assinatura antiga. Dois overloads ficaram vivos:

### cancel_job(uuid)
- Criado interativamente na BD antes do tracking por migrations começar.
- Assinatura: `cancel_job(p_job_id uuid)` — sem razão, sem lógica de reabertura.
- Supersedido por `cancel_job(uuid, text, text DEFAULT NULL)` no `0001_baseline.sql`,
  mas como o baseline usou `CREATE OR REPLACE` com lista diferente, o overload antigo
  sobreviveu.

### create_proposal — versão 10 parâmetros
- Assinatura: `create_proposal(uuid, uuid, numeric, numeric, numeric, integer, text, date, text, boolean)`
- É a versão do `0001_baseline.sql` (com `p_scheduled_time text`).
- Supersedida quando a migration `0005` adicionou `p_helpers_equipment_required boolean`
  como 11.º parâmetro via `CREATE OR REPLACE` — o que criou um novo overload em vez de
  substituir o de 10 parâmetros.
- **Nota:** os overloads de 6 e 7 parâmetros foram corretamente dropados em 0005 com
  `DROP FUNCTION IF EXISTS` explícito — o de 10 parâmetros foi deixado por engano.

**Fix:** `supabase/migrations/0008_drop_obsolete_overloads.sql` dropa ambos com
`DROP FUNCTION IF EXISTS`. Após aplicação, cada função deve ter exactamente um overload.

**Lição aprendida:** ao adicionar um parâmetro a uma função existente via
`CREATE OR REPLACE`, sempre preceder com `DROP FUNCTION IF EXISTS <assinatura-antiga>`
para evitar acumulação silenciosa de overloads. Ver padrão correto em 0005
(drops explícitos dos overloads de 6 e 7 params) e 0006 (drop explícito antes de
mudar o return type).

## 2026-06-24 — Code review da Fase 9 completa + descoberta crítica de deployment

### Code review (22 itens, 7 categorias)

Code review completa de tudo construído na Fase 9 (schema, RPCs, RLS, modelos Dart,
e todos os 5 touchpoints de UI). 10 itens resolvidos imediatamente; 4 deixados em
backlog não bloqueante; restantes são informativos/confirmados corretos.

**Fixes aplicados via migration 0007:**
- **C2.2** — `cancel_job` agora faz cascade: cancela `help_requests` abertos e rejeita
  `help_acceptances` pending quando um job é cancelado. Previne órfãos visíveis no
  ecrã de descoberta e no lobby.
- **C2.3 + C7.4** — `get_help_requests_in_radius` agora exclui jobs com
  `status IN ('cancelled', 'completed')` E exclui help_requests onde o caller é o
  worker principal (`jp.worker_id <> auth.uid()`). Previne que candidatos vejam jobs
  cancelados ou se candidatem ao próprio help_request.
- **C3.1** — Removida política RLS "Worker aceita ajudar" (baseline) em
  `help_acceptances` FOR INSERT. Era mais permissiva que a política de 0004 e, como
  o PostgreSQL faz OR entre políticas permissivas, tornava a restrição de `status =
  'pending'` ineficaz. A política "Worker candidata-se a help_request" (0004) é agora
  a única INSERT policy e funciona como esperado.
- **C3.3** — Política RLS "Worker principal cria help_requests" em `help_requests` FOR
  INSERT restringida a propostas com `status = 'accepted'`. Antes permitia INSERT para
  qualquer proposta do worker independentemente do estado.
- **C3.4** — Política RLS "Worker cancela ajuda" em `help_acceptances` FOR UPDATE
  restringida com `WITH CHECK (status = 'cancelled')`. Antes permitia ao candidato
  atualizar qualquer coluna (incluindo `agreed_rate` e `status`) para qualquer valor.
- **C5.2 (BD)** — Adicionado `CHECK (status <> 'accepted' OR agreed_rate > 0)` em
  `help_acceptances`. Constraint condicional (não `> 0` incondicional) porque
  `applyToHelpRequest` insere `agreed_rate = 0` como placeholder para candidaturas
  pending — o valor real é definido pelo principal via `accept_help_candidate`. Pre-flight
  na migration aborta se existirem linhas accepted com rate ≤ 0.

**Fixes aplicados no Dart:**
- **C7.1** — `client_job_detail_screen.dart`: `onPressed: accepting ? () {} : onAccept`
  corrigido para `onPressed: accepting ? null : onAccept`. O `() {}` impedia o
  `FilledButton` de mostrar o estilo desativado durante a chamada de aceitação.
- **C5.2 (cliente)** — `worker_help_requests_lobby_screen.dart`: validação adicionada
  antes de chamar `acceptCandidate`. Se o campo de taxa é apagado ou inválido →
  fallback para o valor sugerido (comportamento anterior preservado). Se o utilizador
  escrever explicitamente um valor ≤ 0 → SnackBar "A taxa deve ser maior que zero.",
  sem chamar o RPC, sem fechar o sheet.

**Backlog (não bloqueante — nenhum ecrã de UI precisa deles ainda):**
- C3.2 — Sem política SELECT para o cliente ver `help_requests` em estado `open`/`filled`.
- C7.2 — Estado de erro no lobby substitui ecrã inteiro em vez de mostrar erro inline.
- C7.5 — `_iconForType` em `notifications_screen.dart` não é exaustivo para 9 tipos
  de notificação pré-Fase-9 (mostram ícone genérico de sino).
- C7.7 — `helpAccepted` navega para `/worker/jobs` mas os `help_acceptances` não
  aparecem nesse ecrã — gap de UX até ser criado um ecrã dedicado de "helper jobs".

### CRÍTICO: migrations 0002-0007 nunca tinham sido aplicadas à BD viva

Descoberto durante a verificação manual em 2026-06-24: **as migrations 0002 a 0007
nunca tinham sido aplicadas à base de dados de produção**, apesar de estarem marcadas
como "feitas" em sessões anteriores.

**Causa raiz:** o Claude Code consegue *ler* a BD via REST API do Supabase mas
**não consegue executar alterações de schema diretamente** — apenas cria ficheiros
`.sql` localmente. Em sessões anteriores, após criar os ficheiros de migration, o
assistente reportou o trabalho como "concluído" sem confirmar se tinham sido aplicados.

**Descoberto quando:** queries de verificação manual falharam a encontrar colunas e
constraints esperados (ex: `helpers_equipment_required`, `equipment_required`,
`created_post_confirmation`, políticas RLS da Fase 9).

**Resolução:** todas as migrations 0001 a 0007 foram aplicadas manualmente via o SQL
Editor do Supabase em 2026-06-24. Durante este processo, dois overloads obsoletos
adicionais foram encontrados (`cancel_job(uuid)` e `create_proposal` de 10 parâmetros)
e removidos via migration 0008 (ver entrada anterior neste log).

### Lição aprendida: confirmação de deployment obrigatória

> **Regra a seguir em todas as sessões futuras:** após qualquer prompt que crie um
> ficheiro de migration, confirmar explicitamente com o Claude Code se a migration foi
> aplicada à BD viva ou apenas escrita como ficheiro. Nunca assumir que "criado" =
> "aplicado". Em caso de dúvida, verificar diretamente via SQL Editor antes de
> considerar uma migration "feita".

O Claude Code deve terminar qualquer resposta que crie um ficheiro `.sql` com a frase
explícita: *"Este ficheiro foi criado mas NÃO aplicado à base de dados. Tens de o
aplicar manualmente."*

## 2026-06-24 — Fase 9: três gaps de cancelamento fechados (migration 0009)

### Problema

Após o code review da Fase 9, identificaram-se três situações não cobertas:

1. **Ajudantes aceites não eram notificados quando o job era cancelado.** O `cancel_job`
   (0007) fazia cascade de `help_requests` e rejeitava `help_acceptances` pending, mas
   não notificava os ajudantes com `status = 'accepted'`.

2. **Um ajudante aceite não tinha forma de se retirar.** Não existia nenhum RPC ou
   endpoint para cancelar a própria candidatura aceite.

3. **Quando um ajudante se retirava de um `help_request` preenchido, o slot ficava
   perdido.** Nenhuma lógica repunha o `help_request` a `open` nem notificava os
   candidatos rejeitados da nova vaga.

### Solução (migration 0009)

**cancel_job (atualização):**
- Após os cascade UPDATEs existentes (0007), insere notificações `help_job_cancelled`
  para todos os `help_acceptances` com `status = 'accepted'` no job cancelado.
- O filtro `ha.status = 'accepted'` é seguro após o cascade porque o cascade apenas
  rejeita `pending` — os `accepted` ficam inalterados até esta INSERT.
- `related_id = p_job_id`, `related_type = 'job_request'`.

**withdraw_help_acceptance (novo RPC SECURITY DEFINER):**
- Pré-condições: chamador = `worker_id` da candidatura; `status = 'accepted'`.
- Efeito 1: `help_acceptances.status → 'cancelled'`.
- Efeito 2: se `help_request.status = 'filled'`, reverte para `'open'` (slot libertado).
- Efeito 3: se houve reabertura, notifica todos os candidatos `rejected` com
  `help_request_reopened` (podem re-candidatar-se).
- Efeito 4 (sempre): notifica o worker principal com `help_withdrew`.
- `related_id = help_request_id` para ambas as notificações.
- Nota de race condition: dois ajudantes a retirar-se simultaneamente podem enviar
  notificações duplicadas de reabertura. Idempotente nos dados; aceitável para MVP.

**Três novos tipos de notificação (notification_types.dart):**
- `help_job_cancelled` — ajudante notificado de que o job que aceitou foi cancelado.
  Handler: `context.go('/worker/help-requests', extra: {'initialTabIndex': 1})`
  (tab "As minhas candidaturas"). Sync: invalida `helpRequestSummariesInRadiusProvider`
  + `helpRequestsInRadiusProvider` + `myHelpAcceptancesProvider`.
- `help_request_reopened` — candidato rejeitado notificado de vaga disponível.
  Handler: `context.push('/worker/help-requests')` (discovery screen). Sync: invalida
  `helpRequestSummariesInRadiusProvider` + `helpRequestsInRadiusProvider`.
- `help_withdrew` — principal notificado de que um ajudante desistiu.
  Handler: fetch help_request → job → proposal → `context.push` lobby (mesmo padrão
  que `helpRequestApproved`). Sync: invalida `helpRequestsForJobProvider`.
- `help_rejected` (pré-existente) — deixou de ser puramente informacional: sync passa
  a invalidar `myHelpAcceptancesProvider` para actualizar a tab "Histórico" do ajudante.
- `help_accepted` (pré-existente) — handler alterado de `context.go('/worker/jobs')`
  para `context.go('/worker/help-requests', extra: {'initialTabIndex': 1})`; sync passa
  a invalidar também `myHelpAcceptancesProvider`.

**Dart — HelpRequestRepository:**
- Adicionado `withdrawHelpAcceptance(String helpAcceptanceId)` que chama o novo RPC.

**Gap de UI resolvido (C7.7):**
- `withdrawHelpAcceptance` tem agora ponto de entrada na UI através da tab "As minhas
  candidaturas" em `WorkerHelpRequestsScreen` (ver entrada de 2026-06-24 abaixo).
  O gap C7.7 do code review está fechado.

**RLS:** ambas as funções são SECURITY DEFINER — contornam RLS. A política
"Worker cancela ajuda" (`WITH CHECK status = 'cancelled'`) é compatível com o que
`withdraw_help_acceptance` escreve, mas é irrelevante porque o SECURITY DEFINER
não a aplica.

**Estado:** migration 0009 aplicada à BD viva (confirmado via probe REST API
2026-06-24: `withdraw_help_acceptance` devolve HTTP 400 — função existe).

## 2026-06-24 — Fase 9: get_my_help_acceptances RPC (migration 0010)

### Problema

Para popular a tab "As minhas candidaturas" (ver entrada abaixo), é necessário
carregar todas as candidaturas do ajudante autenticado com contexto suficiente para
display (nome do serviço, nome do worker principal, estado do job pai). Um SELECT
direto via PostgREST em `help_acceptances` não consegue resolver o JOIN necessário.

### Decisão: SECURITY DEFINER RPC em vez de PostgREST embedded join

O join necessário é um two-hop FK:
`job_proposals.worker_id → worker_profiles.profile_id → profiles.id`

O PostgREST resolve JOINs simples (um salto de FK direta), mas esta cadeia
`worker_profiles.profile_id` como intermediário não tem uma FK direta de
`help_acceptances` para `profiles` — a linha do ajudante passa por
`help_requests → job_requests → service_types` E por
`help_requests → job_proposals → profiles`. O PostgREST embedded join falha
neste cenário de FK indireta.

Solução: `get_my_help_acceptances()` — função SECURITY DEFINER STABLE que:
- Filtra por `ha.worker_id = auth.uid()` (sem expor dados de outros workers)
- Faz os JOINs em SQL (sem limitações PostgREST)
- Devolve: `id`, `help_request_id`, `status`, `agreed_rate`, `brought_equipment`,
  `created_at`, `service_type_name`, `principal_name`, `job_status`
- Ordenado por `ha.created_at DESC`

**Padrão reutilizado:** idêntico à decisão da migration 0006 (`get_help_requests_in_radius`
com join de contexto), onde o mesmo problema de FK indireta levou à mesma solução.

**Dart:**
- `fetchMyHelpAcceptances()` em `HelpRequestRepository` (chama o RPC)
- `myHelpAcceptancesProvider` — `FutureProvider<List<HelpAcceptanceSummary>>`
- `HelpAcceptanceSummary` — classe de modelo distinta de `HelpAcceptance` (que é
  usada no lobby do principal e tem campos diferentes)

**Estado:** migration 0010 aplicada à BD viva (confirmado via probe REST API
2026-06-24: `get_my_help_acceptances` devolve HTTP 200 — função existe).

## 2026-06-24 — Fase 9: tab "As minhas candidaturas" em WorkerHelpRequestsScreen

### Problema

Após fechar os gaps de cancelamento (0009 + `withdrawHelpAcceptance`), o RPC existia
mas não havia nenhum ponto de entrada na UI para o ajudante ver ou gerir as suas
candidaturas — o gap C7.7 do code review.

### Solução

`WorkerHelpRequestsScreen` convertida de ecrã único para ecrã com 2 tabs:

**Estrutura:**
- `DefaultTabController(length: 2, initialIndex: widget.initialTabIndex)` com:
  - Tab 0 "Descobrir" — conteúdo original (`_buildDiscoverTab()`, inalterado)
  - Tab 1 "As minhas candidaturas" — novo `_MyApplicationsTab`
- `initialTabIndex` passado como parâmetro de construtor (default 0)

**`_MyApplicationsTab` (ConsumerStatefulWidget):**
- Consome `myHelpAcceptancesProvider`
- Três secções: Pendentes / Aceites / Histórico (rejected + cancelled)
- Pull-to-refresh: `ref.invalidate(myHelpAcceptancesProvider)`
- Botão "Desistir" nas candidaturas aceites: AlertDialog de confirmação →
  `withdrawHelpAcceptance()` → `ref.invalidate(myHelpAcceptancesProvider)`
- Estado vazio único quando todas as secções estão vazias

### Deep-linking via go_router state.extra

Para que notificações possam navegar diretamente para a tab correcta, a rota
`/worker/help-requests` foi actualizada para ler `initialTabIndex` de `state.extra`:

```dart
GoRoute(
  path: '/worker/help-requests',
  builder: (_, state) {
    final extra = state.extra as Map<String, dynamic>?;
    return WorkerHelpRequestsScreen(
      initialTabIndex: extra?['initialTabIndex'] as int? ?? 0,
    );
  },
)
```

Chamadores sem `extra` recebem tab 0 (Descobrir) por omissão — sem regressão.
`DefaultTabController` suporta `initialIndex` nativamente; sem necessidade de
`TickerProviderStateMixin` ou estado externo.

## 2026-06-24 — Fase 9: TODO comments em notification_handler.dart fechados

### Contexto

Dois casos no switch de `NotificationHandler.handle()` tinham TODOs a marcar
que a navegação era um fallback incorreto enquanto não existisse um ecrã dedicado
de "helper jobs":

- `helpAccepted` — navegava para `context.go('/worker/jobs')` com TODO
- `helpJobCancelled` — navegava para `context.go('/worker/jobs')` com TODO

`/worker/jobs` é o ecrã "Os meus jobs" do worker **principal** (propostas aceites),
que não mostra candidaturas de ajudante — o utilizador ficava no ecrã errado.

### Resolução

Com a tab "As minhas candidaturas" disponível em `/worker/help-requests`, ambos os
casos foram actualizados para:

```dart
context.go('/worker/help-requests', extra: {'initialTabIndex': 1});
```

Os comentários TODO foram removidos. O switch em `NotificationHandler` é agora
exaustivo para todos os 19 tipos em `NotificationType` sem comentários de débito.

## 2026-06-25 — Crosscheck BD viva vs docs vs Dart + migrations 0011–0012

### Crosscheck três vias (snapshot DB 2026-06-25)

Comparação sistemática entre o snapshot da BD viva (`docs/_db_snapshot_2026-06-25/`,
4 CSV files) e todos os ficheiros de docs + código Dart (repositórios, modelos, enums).

**Achado 1 — `get_jobs_in_radius` overload obsoleto ainda vivo (migration 0011)**
O overload sem `p_worker_id` (`get_jobs_in_radius(numeric, numeric, integer)`) nunca
foi dropado em 0008. Confirmado em `02_functions.csv`. O Dart sempre passa `p_worker_id`
via named params, pelo que o overload obsoleto nunca é chamado pelo código da app —
mas era invocável diretamente via SQL, retornando todos os jobs no raio sem filtrar o
próprio worker. Corrigido em `0011_drop_obsolete_get_jobs_in_radius.sql`.

**Achado 2 — CRITICAL 2 era falso alarme (get_help_requests_in_radius)**
O relatório do crosscheck assinalou como CRÍTICO que a função em `0003_help_requests_team.sql`
retornava `SETOF help_requests` (apenas colunas da própria tabela), mas `HelpRequestSummary`
necessita de `location_lat`, `location_lng`, `service_type_id`, `principal_name`.
Verificação via `pg_get_functiondef` na BD viva mostrou que a migration 0006 já tinha
atualizado a função com `RETURNS TABLE(...)` e todos os JOINs necessários — incluindo
a exclusão de jobs `cancelled`/`completed` e de help_requests onde o caller é o principal
(fixes C2.3 + C7.4 do code review de 2026-06-24). O ficheiro `0003_help_requests_team.sql`
tem o corpo desatualizado, mas é inofensivo: a BD viva tem a definição correcta de 0006.
Sem SQL fix necessário.

**Nota técnica:** `get_jobs_in_radius` usa `numeric` para lat/lng; `get_help_requests_in_radius`
usa `double precision`. Inconsistência cosmética entre as duas variantes da fórmula de
Haversine — ambas correctas. Uniformizar para `numeric` na próxima vez que uma das
funções for alterada.

**Achado 3 — Sem política SELECT para candidatos em `help_requests` (migration 0012, HIGH)**
Workers candidatos não tinham nenhuma política SELECT em `help_requests`. A descoberta
via RPC SECURITY DEFINER funcionava, mas qualquer fetch direto por um candidato
(`fetchHelpRequestById`, `fetchHelpRequestsForJob`) retornava null/vazio silenciosamente.
Adicionada política "Worker candidato vê help requests onde se candidatou" em 0012.

**Achado 4 — Políticas duplicadas em `job_proposals` (migration 0012, MEDIUM)**
Dois pares de políticas funcionalmente idênticas encontrados em `03_policies.csv`:
- INSERT: "Worker envia proposta" e "Worker cria propostas"
- SELECT: "Worker vê as suas propostas" (com acento) e "Worker ve as suas propostas" (sem acento)
Criados por migrations separadas que não verificaram políticas pre-existentes.
Duplicados dropados em 0012; variantes com nomes correctos mantidas.

**Outros achados não bloqueantes (nenhuma alteração ao código):**
- `help_acceptances.status` tem default `'accepted'` na BD mas a RLS de INSERT força
  `status = 'pending'` — default nunca é usado via app. Cosmético.
- `job_proposals.estimated_hours` (coluna legacy nullable) existe na BD mas não é mapeada
  no `JobProposal.fromJson` — ignorada silenciosamente, sem risco.
- `job_requests.confirmed_flexible`: nullable na BD; Dart usa `bool? ?? false`. Cosmético.
- Todos os enums Dart estão em perfeito alinhamento com os CHECK constraints da BD.
- Todas as assinaturas de RPC correspondem exactamente aos chamadores no Dart.

### Docs actualizados

- `database_schema.md`: corrigido `size_estimate` (sem CHECK na BD, só enum Dart);
  corrigida secção RLS de `notifications` (sem política INSERT; inserts via SECURITY
  DEFINER); adicionada nota sobre política de candidatos em `help_requests`.

### Estado das migrations

**0011** — escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor.
**0012** — escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor após 0011.

---

## 2026-06-25 — Bug de loading infinito no arranque a frio — causa raiz e correção

### Contexto

Em arranques a frio sem sessão cacheada (utilizador desligado / primeira instalação),
a app ficava indefinidamente no ecrã `/loading` sem crash, sem exceção, sem redirect.
Utilizadores com sessão cacheada (fast path em `SessionNotifier.build()`) não eram
afectados — o bug nunca foi capturado em testes manuais durante o desenvolvimento
porque os developers têm sempre sessão persistida.

### Diagnóstico

Adicionados `debugPrint` temporários a `SessionNotifier` e `RouterNotifier` para
rastrear o fluxo de estado. Os logs confirmaram:

1. `SessionNotifier.build()` resolvia correctamente e depressa: `currentSession=NULL`
   → slow path → stream emitiu `session=NULL` → retornou `SessionStatus.unauthenticated`.
2. `ref.listen(sessionStatusProvider, ...)` disparava (Riverpod 3.x notifica na
   transição `AsyncLoading → AsyncData`, incluindo a primeira resolução do `build()`).
3. `notifyListeners()` era chamado → GoRouter re-avaliava `redirect()`.
4. `redirect()` era chamado com `loc=/loading`, `isAuthenticated=false` →
   entrava no branch `!isAuthenticated` → `publicRoutes.contains('/loading') == true`
   → **retornava `null` (ficar)**.

### Causa raiz

`'/loading'` estava incorrectamente incluído em `publicRoutes` no branch
`!isAuthenticated` de `RouterNotifier.redirect()`:

```dart
// ANTES (buggy):
const publicRoutes = ['/', '/login', '/signup', '/loading'];
return publicRoutes.contains(loc) ? null : '/';
```

O branch `isLoading` acima já trata a espera inicial (enquanto `build()` está a correr,
fica em `/loading`). Uma vez que a sessão resolve — mesmo para `unauthenticated` —
`/loading` nunca deve ser um destino válido. Ao incluí-lo em `publicRoutes`, o router
interpretava-o como "ecrã público seguro para não-autenticados" e nunca redirecionava
o utilizador.

### Correção

Removido `'/loading'` de `publicRoutes`:

```dart
// DEPOIS (correcto):
const publicRoutes = ['/', '/login', '/signup'];
return publicRoutes.contains(loc) ? null : '/';
```

Um utilizador não-autenticado em `/loading` (sessão resolvida) é agora redirecionado
para `'/'` (LandingScreen).

### Ficheiros alterados

- `lib/core/router/app_router.dart` — removido `'/loading'` de `publicRoutes`
- `lib/features/auth/application/session_provider.dart` — removidos prints de diagnóstico
- `lib/core/router/app_router.dart` — removidos prints de diagnóstico

## 2026-06-25 — Dois bugs de redirect no RouterNotifier (signup flow)

### Bug 1 — Utilizadores com `role=null` saltavam o ecrã `/choose-role`

**Causa raiz:** o branch `!isAuthenticated` de `redirect()` tratava `/choose-role` como
rota pública (estava na lista de `publicRoutes`). Quando a sessão resolvia para
`isAuthenticated=true, role=null` (utilizador acabou de se registar, ainda sem perfil),
nenhum branch tratava o caso — o código chegava ao bloco:

```dart
if (loc == '/' || loc == '/loading' || ... || loc == '/choose-role') {
  return role?.value == 'worker' ? '/worker/setup' : '/client/home';
}
```

`role == null`, por isso `role?.value == 'worker'` é `false` → redirecionava para
`/client/home` sem o utilizador ter escolhido a sua role ou criado perfil.

**Correção:** adicionado guard explícito antes do bloco de "landing pages":

```dart
// Authenticated but no profile yet (fresh signup, role not chosen)
if (role == null) {
  return loc == '/choose-role' ? null : '/choose-role';
}
```

---

### Bug 2 — A correção do Bug 1 introduziu uma regressão: `fullName`/`phone` chegavam vazios à BD

**Sintoma:** contas criadas depois do Bug 1 ter sido corrigido tinham `full_name = ''`
e `phone = ''` na tabela `profiles` (strings vazias, não null).

**Causa raiz — sequência exata de eventos:**

1. `signup_screen._submit()` chama `context.go('/choose-role', extra: {'fullName': 'João', 'phone': '912...'})`
2. GoRouter constrói `ChooseRoleScreen(fullName: 'João', phone: '912...')` ✓
3. O stream `onAuthStateChange` do Supabase dispara (na próxima iteração do event loop, após `signUp()` regressar)
4. `authStateProvider` atualiza → `sessionStatusProvider.build()` re-executa → estado vai para `AsyncValue.loading()`
5. `RouterNotifier.notifyListeners()` dispara → GoRouter avalia `redirect()`:
   `sessionAsync.isLoading == true` → `loc == '/loading' ? null : '/loading'`
   `loc = '/choose-role'` → **redireciona para `/loading`**, descartando a rota com `state.extra`
6. `_fetchProfile()` resolve → `role == null` (ainda sem perfil na BD) → `sessionStatusProvider` resolve
7. `redirect()` avalia de novo: `role == null`, `loc == '/loading'` → retorna `'/choose-role'`
8. GoRouter navega para `/choose-role` — mas **este é um redirect iniciado pelo router, sem `extra`**
9. Builder chamado com `state.extra = null` → `ChooseRoleScreen(fullName: '', phone: '')` ✗
10. Utilizador escolhe role → `createProfile(fullName: '', phone: '', role: worker)` → strings vazias na BD

O problema é a viagem de ida e volta `/choose-role` → `/loading` → `/choose-role`: na
segunda chegada, o `state.extra` original já não existe porque o redirect é iniciado
pelo router (um path string), não por `context.go` com `extra`.

**Correção:** isentar `/choose-role` do redirect de loading, tal como `/loading` já era isento:

```dart
// ANTES (buggy após Bug 1 fix):
if (sessionAsync.isLoading) {
  return loc == '/loading' ? null : '/loading';
}

// DEPOIS (correcto):
if (sessionAsync.isLoading) {
  // Don't bounce /choose-role through /loading — the auth stream fires
  // immediately after signUp() while the user is transitioning to role
  // selection; the loading state is transient and /choose-role handles it
  // visually fine on its own. Bouncing through /loading would discard the
  // fullName/phone passed via navigation extra.
  const loadingExempt = ['/loading', '/choose-role'];
  return loadingExempt.contains(loc) ? null : '/loading';
}
```

**Porquê é seguro:** `/choose-role` só é acessível a utilizadores autenticados sem
perfil (o guard `role == null` logo abaixo trata qualquer caso onde alguém chegue aqui
sem a sessão resolver para `role == null`). Manter o utilizador em `/choose-role`
durante o estado loading transiente não cria nenhum gap de segurança.

### Estado final dos branches `isLoading` e `role == null` em `redirect()`

```dart
if (sessionAsync.isLoading) {
  const loadingExempt = ['/loading', '/choose-role'];
  return loadingExempt.contains(loc) ? null : '/loading';
}

// ...

if (role == null) {
  return loc == '/choose-role' ? null : '/choose-role';
}
```

**Ficheiro alterado:** `lib/core/router/app_router.dart` — branch `isLoading`

## 2026-06-25 — Fase 10: regra das 24h adicionada ao cancelamento

### Gap encontrado

A regra das 24h existia em `propose_reschedule` (enforcement na BD) desde a Fase 8E.2,
e estava documentada em `state_machine.md` sob "Regras de cancelamento" como especificação.
No entanto, `cancel_job` nunca implementou esta restrição — o RPC e as UIs aceitavam
cancelamentos com qualquer antecedência, mesmo a minutos do serviço.

Descoberto na verificação da Fase 10 (2026-06-25).

### Solução

**Migration 0013 (`0013_cancel_24h_rule.sql`):**
A verificação é inserida em `cancel_job` imediatamente após `v_is_worker` ser definido,
antes de qualquer outra lógica:

```sql
IF v_job.status = 'confirmed'
   AND v_job.confirmed_date IS NOT NULL
   AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
  RAISE EXCEPTION 'O cancelamento requer pelo menos 24h de antecedência.';
END IF;
```

- Aplica-se a cliente e worker simetricamente (antes do branch `IF v_is_worker THEN`)
- Jobs com `confirmed_date IS NULL` (data flexível) estão isentos — igual ao comportamento de `propose_reschedule`
- Jobs `open` nunca têm `confirmed_date`, por isso o check não os afeta

**UI client-side:**
Ambos os ecrãs de detalhe desativam o botão "Cancelar" e mostram uma mensagem
explicativa quando `confirmedDate != null && confirmedDate.difference(DateTime.now()).inHours < 24`:

- `lib/features/jobs/presentation/client_job_detail_screen.dart`
- `lib/features/worker/presentation/worker_my_job_detail_screen.dart`

Mensagem: `'Cancelamento disponível até 24h antes da data confirmada.'`

O UI gate é redundante com o enforcement da BD mas melhora a UX — o utilizador
percebe porque o botão está desativado em vez de receber um erro genérico.

**Estado:** migration 0013 escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor.

## 2026-06-25 — Fase 10: contacto do worker visível em awaiting_confirmation e completed

O contacto do worker (nome + botão WhatsApp) só era mostrado ao cliente no estado
`confirmed`. Nos estados `awaiting_confirmation` e `completed` o card desaparecia,
deixando o cliente sem forma de contactar o prestador exactamente quando mais precisaria
(para questões sobre o trabalho entregue ou para acompanhamento pós-conclusão).

**Causa:** gap de UI — a condição `if (displayJob.status == JobStatus.confirmed)`
limitava o card a um único estado.

**RLS:** já suportava os três estados. A função `client_has_confirmed_job_with_worker`
(usada pela política SELECT de `worker_profiles`) já incluía
`('confirmed', 'awaiting_confirmation', 'completed')` — confirmado via `pg_get_functiondef`
em 2026-06-25. Nenhuma alteração à BD necessária.

**Fix:** `lib/features/jobs/presentation/client_job_detail_screen.dart`
- Extraído `_workerContactCard(workerInfoAsync, theme)` — método privado que envolve
  `workerInfoAsync.when(...)` e devolve o Card de contacto (loading / erro / dados)
- Bloco `confirmed`: refatorado para chamar `_workerContactCard` em vez do Card inline;
  os botões de cancelar/remarcar movidos para fora do `workerInfoAsync.when()` (não
  dependem da info do worker)
- Bloco `awaitingConfirmation`: `_workerContactCard` adicionado no topo da Column,
  acima do card "O prestador marcou como concluído" e botões de confirmação
- Novo bloco `completed`: `_workerContactCard` adicionado como item standalone

**Worker screen (`worker_my_job_detail_screen.dart`):** sem alteração necessária — o
card de contacto do cliente já estava gated em `liveStatus == ProposalStatus.accepted`,
que cobre `confirmed`, `awaiting_confirmation` e `completed` (a proposta mantém-se
`accepted` através de todos estes estados).

## 2026-06-25 — Fase 10: auto-confirmação após 3 dias via pg_cron

A extensão `pg_cron` foi activada manualmente neste projecto em 2026-06-25.

**Nova função `auto_confirm_completed_jobs()`** — SECURITY DEFINER, sem verificação
de `auth.uid()` (actua como o sistema). Segue o padrão estabelecido de "funções batch
internas": a superfície pública `confirm_job_completion` fica intocada; a nova função
é estritamente interna e não deve ser chamada pelo cliente Flutter.

**Cron:** `0 */3 * * *` (cada 3 horas). Registo em `cron.job` via `cron.schedule()`
na migration 0014 — este registo é diferente de DDL normal: só existe após a migration
ser aplicada E o `cron.schedule()` ter corrido com sucesso. Verificar com:
```sql
SELECT * FROM cron.job WHERE jobname = 'auto-confirm-completed-jobs';
```

**Estado:** migration 0014 escrita localmente, **NÃO aplicada** à BD. Aplicar via
SQL Editor. Após aplicar, confirmar via query acima que o job aparece em `cron.job`.