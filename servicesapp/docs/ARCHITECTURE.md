# LocalServices (ProJardim) — Architecture Reference

> Referência técnica de como a app funciona, extraída do código real em 2026-10-16 e
> revista contra o `main` a 2026-10-27 (depois do PR #37: Agenda, A11, avisos).
> Router, migrations, providers, widgets e enums lidos diretamente, não de memória de
> sessões anteriores. Complementa `STATUS.md` (o que funciona/não funciona hoje)
> sem repetir o seu conteúdo. Funde também o antigo `architecture.md` (regras de
> organização do projeto), ver os Princípios na secção 4. A secção 7 vem dos
> ficheiros de migration, não de queries à BD viva. **Todas as migrations do repo
> (até à 0065) estão aplicadas na BD viva**, confirmado pelo Henrique a 2026-10-27.

---

## 1. Visão geral

Marketplace de serviços locais (Flutter + Supabase), lançado focado em jardinagem mas
com código e schema genéricos (`client`, `worker`, `job`, `service_type` — nunca
"jardineiro"/"jardim" fora da UI em português). Dois papéis:

- **Cliente**: cria um pedido (serviço, localização, data, descrição, fotos), recebe
  propostas de workers no raio, aceita uma, acompanha o ciclo de vida até à conclusão,
  avalia o worker.
- **Worker** ("jardineiro" na UI): define raio de atuação e serviços, descobre pedidos
  no raio, propõe preço/data, pode pedir ajudantes para trabalhos maiores, marca como
  concluído, avalia o cliente e os ajudantes.

Fluxo principal: `job_requests` nasce `open` → workers propõem (`job_proposals`) →
cliente aceita uma → `confirmed` → worker marca concluído → `awaiting_confirmation` →
cliente confirma → `completed` → avaliações bilaterais. Sem pagamentos nem chat
dentro da app — contacto só por WhatsApp, depois da confirmação.

Por cima deste fluxo (estado a 2026-10-27):

- **Proposta por hora ou valor total** (0058): o jardineiro escolhe em cada proposta;
  validade de 7, 15 ou 30 dias; trabalhos em vários dias.
- **Pedido direto** (0057, 0059): "Pedir de novo" a um jardineiro anterior ou pelo
  cartão público `/w/:id`; 24h só para esse jardineiro, depois abre a todos (ou fica
  parado, se o cliente desligou "mostrar a outros").
- **Início do trabalho** (0052): "Iniciar" com fotos de antes, tempo em curso, fotos de
  depois, confirmação automática em 48h.
- **Planos** (0060): Grátis (5 trabalhos aceites por mês), Pro e Pro+, atribuídos no
  painel `/admin`. Contrato e pagamento fora da app; a app não mostra preços.
- **Agenda do jardineiro** (0064): Hoje, Semana e Mês dentro de Trabalhos, com trabalhos
  da app, propostas pendentes, trabalhos de fora da app e indisponibilidades; avisa
  sobreposições, nunca bloqueia.
- **Avisos que ajudam a fechar** (0062): lembretes aos jardineiros, pedido mostrado mais
  longe às 24h sem propostas, dicas da época.

---

## 2. Stack e versões

| | Versão |
|---|---|
| Flutter | 3.44.1 (stable) |
| Dart SDK | 3.12.1 (`environment.sdk: ^3.12.1` no pubspec) |
| Engine | revisão `39b1f7043775b9578bbb26a1676e79c4e31c8b5e` |

Dependências principais (`pubspec.yaml`):

| Package | Versão | Papel |
|---|---|---|
| `supabase_flutter` | ^2.12.4 | Auth, Postgres (REST), Storage, Realtime |
| `go_router` | ^17.2.3 | Navegação declarativa |
| `flutter_riverpod` | ^3.3.1 | Estado/DI |
| `image_picker` | ^1.2.2 | Seleção de fotos (avatar, job, fleet card) |
| `flutter_image_compress` | ^2.4.0 | Compressão de fotos antes do upload |
| `geolocator` | ^14.0.2 | GPS (raio do worker, distância) |
| `geocoding` | ^4.0.0 | Geocoder nativo em `GeocodingService.searchAddress`; o resto vai por `http` a Photon/Nominatim (secção 12) |
| `flutter_map` + `latlong2` | ^8.3.0 / ^0.9.1 | Mapa (seleção de localização) |
| `http` | ^1.2.2 | Chamadas REST diretas (Nominatim) |
| `intl` | ^0.20.2 | Datas |
| `uuid` | ^4.5.3 | — |
| `google_fonts` | ^6.2.1 | Plus Jakarta Sans |
| `shared_preferences` | ^2.3.3 | Flag local "já viu onboarding" |
| `qr_flutter` | ^4.1.0 | QR do cartão partilhável do worker e do cartão frota |
| `share_plus` | ^11.0.0 | Partilhar o cartão do worker |
| `google_mlkit_text_recognition` | ^0.15.0 | OCR local do cartão frota |
| `url_launcher` | ^6.3.2 | WhatsApp, Google Maps, links legais, `mailto:` do suporte |
| `firebase_core` + `firebase_messaging` | ^5.0.0 / ^17.0.0 | Push FCM (`PushNotificationService`); desliga-se sozinho sem os ficheiros do Firebase e na web |
| `font_awesome_flutter` | ^11.0.0 | Só o logótipo do WhatsApp (`appWhatsAppIcon`) |
| `flutter_localizations` / `flutter_web_plugins` | SDK | Textos do Material em português e hora em 24h / URLs sem `#` na web (`usePathUrlStrategy`) |

Dev: `flutter_lints` ^6.0.0 (`analysis_options.yaml` na raiz do projeto Flutter).

---

## 3. Estrutura de pastas

```
lib/
  app.dart                 # MaterialApp.router + AnnotatedRegion<SystemUiOverlayStyle>
  main.dart                # Supabase.initialize + ProviderScope + runApp
  core/
    config/                 app_links.dart, storage_urls.dart, supabase_config.dart (env via --dart-define)
    constants/              enums.dart, password_policy.dart
    models/                 worker_public_card_feature_access.dart (flags do cartão vindas do servidor)
    router/                 app_router.dart, route_guard.dart, app_page_transitions.dart, app_back_navigation.dart
    services/               geocoding_service.dart
    theme/                  app_colors/spacing/radius/sizes/breakpoints/typography/motion_tokens/status_color/status_presentation/theme.dart
    utils/                  error_utils.dart, app_status_presenters.dart, date_labels.dart, day_greeting.dart,
                            phone_utils.dart, picked_photo.dart, price_labels.dart, provider_cache.dart
    widgets/                46 ficheiros partilhados (secção 10)
  features/
    admin/            application/ data/ presentation/   (painel /admin, 0060)
    agenda/           application/ data/ presentation/   (Agenda do jardineiro, 0064)
    auth/            application/ data/ presentation/
    client/           + presentation/widgets/
    worker/            + presentation/widgets/
    jobs/              + presentation/widgets/        (jobs + propostas do lado cliente)
    proposals/         application/ data/ apenas — presentation/ vazia (ver nota)
    help_requests/     + presentation/widgets/
    ratings/           application/ data/ presentation/
    notifications/     application/ data/ presentation/
    onboarding/        application/ data/ presentation/ + widgets/
    fleet_card/         application/ data/ presentation/
```

**Nota de convenção não documentada:** `features/proposals/presentation/` existe mas
está vazia (só `.gitkeep`). Todos os ecrãs de proposta vivem fisicamente em
`features/jobs/presentation/` (lado cliente: `client_proposals_screen.dart`,
`client_job_detail_screen.dart`) ou `features/worker/presentation/`
(`worker_submit_proposal_screen.dart`) — a camada `presentation` de `proposals/` nunca
chegou a ser usada porque uma proposta nunca se vê fora do contexto de um job. `data/`
e `application/` seguem a convenção normal (`proposal_model.dart`,
`proposal_repository.dart`, `proposal_providers.dart`).

Cada feature com UI própria segue o mesmo padrão de 3 camadas (secção 4). `core/`
é só para o que é partilhado por 2+ features — esta secção reflete a árvore real.

---

## 4. Camadas e padrões

**Princípios** (regras de organização do projeto, válidas desde o início — fundidas
aqui do antigo `architecture.md`):

1. Separação clara: UI ≠ estado ≠ repositories ≠ serviços externos.
2. Nunca chamar Supabase diretamente dentro de widgets — só via repository.
3. Organização por feature; `core/` só para o que é partilhado por 2+ features.
4. Nomes genéricos no domínio (`client`, `worker`, `job`, `proposal`,
   `service_category`, `service_type`, `help_request`) — a base de dados não sabe
   que isto é jardinagem.
5. Simples, legível, evolutivo. Sem overengineering.

**Camadas:**

- **data/**: `*_model.dart` (classes imutáveis, `fromJson`/`toJson`) + `*_repository.dart`
  (única camada que fala com `SupabaseClient` — `.from(...)`, `.rpc(...)`, `.storage`).
- **application/**: providers Riverpod. Tipos usados, por ordem de frequência:
  - `Provider<T>` — repositórios e valores derivados sem I/O (`workerRepositoryProvider`,
    `unreadCountProvider`).
  - `FutureProvider<T>` — leitura simples (`clientProfileProvider`, `serviceTypesProvider`).
  - `FutureProvider.family<T, Arg>` — leitura parametrizada sem cache extra
    (`workerNameProvider`).
  - `FutureProvider.autoDispose.family<T, Arg>` — o padrão mais comum para "info básica
    de outra pessoa" (`workerBasicInfoProvider`, `clientBasicInfoProvider`,
    `openJobClientIdentityProvider`): descarta quando ninguém observa, combinado com
    `cacheFor(ref, ttl)` (`core/utils/provider_cache.dart`) para manter o último valor
    vivo por um TTL fixo mesmo sem observadores — reaproveita entre ecrãs sem refazer o
    fetch, mas sem cache indefinido. TTLs usados: 5 min para dados quase estáticos
    (nome/avatar/bio), 45s para o job em si (`jobByIdProvider`).
  - `StreamProvider<T>` — `authStateProvider`, `notificationsStreamProvider` (Realtime).
  - `NotifierProvider`/`AsyncNotifierProvider` — estado com lógica (`authControllerProvider`,
    `sessionStatusProvider`, `pendingSignupProvider`).
  - Nenhum `StateProvider`/`StateNotifierProvider` em uso.
  - Invalidação por side-effect: `notificationSyncProvider` (`Provider<void>` observado
    uma vez em `app.dart`) ouve `notificationsStreamProvider` e invalida os providers de
    dados certos por tipo de notificação — ver tabela completa na secção 9.
- **presentation/**: screens. Sem lógica de negócio nem Supabase direto — só leem
  providers e chamam métodos do repositório via `ref.read`.

**Padrão wrapper + view:** ecrãs com alguma complexidade visual separam-se em dois
ficheiros — `xxx_screen.dart` (liga Riverpod aos dados reais, "wrapper") e
`presentation/widgets/xxx_view.dart` (`ConsumerWidget`/`StatefulWidget` apresentacional,
recebe um objeto `XxxViewData` imutável + callbacks `VoidCallback`/`Function`, nunca lê
providers diretamente). Visto em `worker_job_detail_screen.dart`/`worker_job_detail_view.dart`,
`worker_my_job_detail_screen.dart`/`worker_my_job_detail_view.dart`,
`client_edit_profile_screen.dart`/`client_edit_profile_view.dart`, etc. Exemplo real
resumido (`worker_job_detail_screen.dart`):

```dart
class WorkerJobDetailScreen extends ConsumerWidget {
  const WorkerJobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobByIdProvider(jobId));
    return jobAsync.when(
      loading: () => const Scaffold(body: AppScreenLoadingSkeleton()),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e)))),
      data: (job) => _buildDetail(context, ref, job), // monta WorkerJobDetailViewData
    );
  }
}
// _buildDetail monta `view.WorkerJobDetailViewData(...)` e devolve
// `view.WorkerJobDetailScreen(data: data, onBack: () => goBackOrToRoleHome(context), ...)`
// — o ficheiro `_view.dart` nunca importa Riverpod nem Supabase.
```

Ecrãs simples (sem este grau de complexidade) ficam num único ficheiro
`ConsumerWidget`/`ConsumerStatefulWidget`.

---

## 5. Navegação

`go_router` único (`appRouterProvider`), `initialLocation: '/loading'`,
`refreshListenable: RouterNotifier` (ouve `sessionStatusProvider` +
`hasSeenOnboardingProvider`).

### `RouterNotifier.redirect` — ordem exata dos guards

1. Sessão a carregar → `null` (fica onde está; nunca força `/loading` num tick
   transitório — comentário no código explica que isso já causou perda de dados
   silenciosa a meio de um `ImagePicker`/request).
2. Não autenticado e ainda não viu onboarding → `/onboarding` (exceto `/w/:workerId`).
3. Não autenticado → só rotas públicas passam: `/`, `/login`, `/signup`, `/onboarding`,
   `/forgot-password/request`, `/forgot-password/reset`, `/verify-email`,
   `/w/:workerId`. Resto → `/`.
4. Autenticado sem `role` ainda → só `/choose-role`.
5. **Cross-role guard**: `role == client` e rota começa por `/worker/` → `/client/home`
   (e vice-versa).
6. Em `/`, `/loading`, `/login`, `/signup`, `/choose-role` → redireciona para o
   dashboard do papel (`worker` incompleto → `/worker/setup`).
7. `role == worker` e perfil incompleto → força `/worker/setup`. (Até 2026-10-17 havia
   isenções para `/verify-email` e `/email-confirmed`; deixaram de ser precisas porque a
   confirmação acontece antes de haver papel.)

### Transições (`app_page_transitions.dart`)

3 builders, todos a `AppMotionDuration.screen` (300ms) + `AppMotionCurve.emphasized`,
com fallback a cross-fade de 100ms sob `disableAnimations`:
`buildSharedAxisPage` (passos de um fluxo), `buildContainerTransformPage` (lista→detalhe),
`buildFadeThroughPage` (sem relação direta, ex. troca de tab/sino de notificações).
Rotas com mais de uma origem possível (`/client/job/:id`, `/worker/job/:id`,
`/worker/my-job/:id`, `/worker/help-requests`) leem `extra['entryTransition']` —
`notification_handler.dart` passa `'sharedAxis'` para forçar essa transição quando a
origem é uma notificação, mesmo que o default da rota seja outro.

Os 3 builders também envolvem a página num `PopScope` interno (`_wrapWithBackFallback`)
que cobre o botão/gesto de voltar do sistema para TODAS as rotas de uma vez — ver
secção 13 e o relatório da sessão 2026-10-16 em `decisions_log.md`.

### Tabela de rotas (50 no total: 42 fora dos shells + 4 + 4, contagem de `app_router.dart` a 2026-10-27)

| Path | Ecrã | Shell | Transição |
|---|---|---|---|
| `/loading` | spinner | fora | — |
| `/onboarding` | `ProJardimOnboardingScreen` | fora | fade-through |
| `/` | `LandingScreen` | fora | default (push) |
| `/login` | `LoginScreen` | fora | default |
| `/signup` | `SignupScreen` | fora | shared-axis |
| `/choose-role` | `ChooseRoleScreen` | fora | shared-axis |
| `/forgot-password/request` | `RequestPasswordResetScreen` | fora | shared-axis |
| `/admin` | `AdminGateScreen` (login, segundo fator, depois `AdminHomeScreen`) | fora, sem regras de papel | default |
| `/admin/workers/:workerId` | `AdminWorkerDetailScreen` | fora | shared-axis |
| `/forgot-password/reset` | `PasswordResetScreen` | fora | shared-axis |
| `/verify-email` | `VerifyEmailScreen` (código de confirmação) | fora | shared-axis |
| `/client/job/:id/edit` | `ClientEditJobScreen` (editar pedido aberto, RPC `update_job_request`, 0049) | fora | shared-axis |
| `/worker/help/:acceptanceId` | `WorkerHelperJobScreen` (trabalho visto pelo ajudante) | fora | container-transform / shared-axis |
| `/session-error` | `SessionErrorScreen` (perfil não carregou: tentar de novo ou sair) | fora | shared-axis |
| `/worker/setup` | `WorkerSetupScreen` | fora | default |
| `/worker/profile/edit` | `WorkerEditProfileScreen` | fora | default |
| `/notifications` | `NotificationsScreen` | fora | fade-through |
| `/worker/ratings` | `MyRatingsRoute` | fora | fade-through |
| `/client/ratings` | `MyRatingsRoute` (mesmo widget) | fora | fade-through |
| `/w/:workerId` | `WorkerPublicProfileScreen` | fora, pública | default |
| `/client/profile/edit` | `ClientEditProfileScreen` | fora | default |
| `/client/create-job` | `ClientCreateJobServiceScreen` | fora | shared-axis |
| `/client/create-job/schedule` | `ClientCreateJobScheduleScreen` | fora | shared-axis |
| `/client/create-job/description` | `ClientCreateJobDescriptionScreen` | fora | shared-axis |
| `/client/create-job/review` | `ClientCreateJobReviewScreen` | fora | shared-axis |
| `/client/job/:id` | `ClientJobDetailScreen` | fora | container-transform (default) / shared-axis se `entryTransition` |
| `/client/job/:id/proposals` | `ClientProposalsScreen` | fora | shared-axis |
| `/client/job/:id/proposals/:proposalId` (A6) | `ClientProposalDetailScreen` (detalhe e "Aceitar por X") | fora | shared-axis |
| `/client/job/:id/confirmed` | `ClientJobConfirmedScreen` | fora | shared-axis |
| `/client/job/:id/rate-worker` | `ClientRateWorkerScreen` | fora | shared-axis |
| `/worker/job/:id/propose` | `WorkerSubmitProposalScreen` | fora | shared-axis |
| `/worker/job/:id/help-requests` | `WorkerHelpRequestsLobbyScreen` | fora | shared-axis |
| `/worker/job/:id` | `WorkerJobDetailScreen` | fora | container-transform / shared-axis |
| `/worker/my-job/:id` | `WorkerMyJobDetailScreen` | fora | container-transform / shared-axis |
| `/worker/help-requests` | `WorkerHelpRequestsScreen` | fora | fade-through / shared-axis |
| `/worker/help-requests/:id/apply` | `ApplyAsHelperScreen` | fora | container-transform |
| `/worker/agenda/new` | `AgendaEntryEditorScreen` ("Adicionar à agenda": trabalho fora da app ou indisponível; `?date=` dia, `?type=block`; volta com `AgendaEditorResult`) | fora | slide de baixo |
| `/worker/agenda/:id` | `AgendaEntryDetailScreen` (detalhe de um trabalho de fora da app ou indisponibilidade: feito, cancelar, repor, apagar; `?date=` ocorrência tocada; volta com `AgendaEditorResult` ao apagar, editar ou "Ver o dia") | fora | shared-axis |
| `/worker/agenda/:id/edit` | `AgendaEntryEditorScreen` (editar `worker_calendar_entries`; `?date=` ocorrência tocada) | fora | slide de baixo |
| `/worker/fleet-card` | `FleetCardScreen` | fora | shared-axis |
| `/worker/fleet-card/scan` | `FleetCardScanScreen` | fora | shared-axis |
| `/worker/fleet-card/confirm` | `FleetCardConfirmDataScreen` | fora | shared-axis |
| `/client/home` | `ClientHomeScreen` | **ClientShell** | sem transição própria (IndexedStack do shell) |
| `/client/jobs` | `ClientJobsScreen` | **ClientShell** | idem |
| `/client/alerts` | `NotificationsScreen(inShell: true)` (separador Alertas, A11) | **ClientShell** | idem |
| `/client/profile` | `ClientProfileScreen` | **ClientShell** | idem |
| `/worker/home` | `WorkerDashboardScreen` | **WorkerShell** | idem |
| `/worker/available-jobs` | `WorkerAvailableJobsScreen` | **WorkerShell** | idem |
| `/worker/profile` | `WorkerProfileScreen` | **WorkerShell** | idem |
| `/worker/jobs` | `WorkerJobsScreen` (Trabalhos: tabs Agenda · Propostas · Histórico; a Agenda é `WorkerAgendaTab`, vistas Hoje, Semana e Mês; extra `agendaResult` abre o dia guardado no "+"; `initialTab` "pending" → Propostas, "completed" → Histórico, o resto → Agenda) | **WorkerShell** | idem |

Todos os ecrãs de sub-fluxo (42 fora do shell) usam `SafeArea` próprio e não mostram a
`AppBottomNavigation`; só os 8 dentro dos 2 `ShellRoute` a mostram (cliente: Início,
Pedidos, Alertas, Perfil; jardineiro: Início, Pedidos, Trabalhos, Perfil). O jardineiro
não tem separador de Alertas: tem o sino com número (`HomeNotificationButton`) nos
cabeçalhos de Início, Pedidos e Trabalhos, que abre `/notifications`.

### Botão de voltar

Ver secção 13 (`goBackOrToRoleHome`/`AppBackButton`/`PopScope`) — mecanismo central
para desfazer o efeito de `context.go()` em deep-links de notificação.

---

## 6. Auth e sessão

- **Registo**: `AuthRepository.signUp` (`auth.signUp` com `data: {full_name, phone}`)
  → `createProfile` (`profiles.upsert`, não uma RPC; a antiga `create_user_profile` foi apagada na 0042) → `/choose-role`
  escreve `role` → `/worker/setup` ou `/client/home`.
- **Login com Google/Facebook (2026-10-18)**: `AuthRepository.signInWithSocial` →
  `signInWithOAuth` do Supabase. Web: redirect para `<origem>/` (com `?from=`). Apps: deep
  link `pt.projardim.app://login-callback` (intent-filter Android, `CFBundleURLTypes` iOS);
  o `supabase_flutter` troca o código pela sessão e `resolveRedirect` manda
  `/login-callback` para `/`. Conta nova cai em `/choose-role` (sem perfil), que pede nome e
  telemóvel quando os metadados não trazem telemóvel (`RegistrationIdentity`) e copia a foto
  da conta (`avatar_url`/`picture`) para `avatars/<id>.jpg` (`importSocialAvatar`, melhor
  esforço). Configuração: `SETUP.md` passo 7.
- **Login**: `signInWithPassword`. Conta com email por confirmar (`email_not_confirmed`)
  → `AuthEmailNotConfirmed`: reenvia o código e vai para `/verify-email`.
- **Confirmação de email por código (2026-10-17)**: funciona com "Confirm email" ligado
  ou desligado no Supabase. Desligado: `signUp` abre sessão e o fluxo segue para
  `/choose-role` como sempre. Ligado: `signUp` não abre sessão (`AuthSuccess.
  needsEmailConfirmation`), o registo vai para `/verify-email` (código de 6 dígitos do
  template "Confirm signup" com `{{ .Token }}`), `verifySignupCode` (`verifyOTP` tipo
  `signup`) abre a sessão e segue para `/choose-role`. Sem deep links. Se a app fechar a
  meio, o nome e o telefone vêm de `user.userMetadata` (gravados no `signUp`).
- **Escolha de papel**: `/choose-role`, grava `role` em `profiles`.
- **Setup do worker**: `/worker/setup` — raio, base (GPS + `GeocodingService`), serviços,
  ferramentas; `RouterNotifier` força esta rota enquanto `workerProfileComplete == false`.
- **Sessão**: `SessionNotifier` (`AsyncNotifier<SessionStatus>`) — fast path lê
  `Supabase.instance.client.auth.currentSession` (restaurado do storage local,
  disponível no arranque sem esperar pelo stream); slow path observa `authStateProvider`
  (`StreamProvider<AuthState>` sobre `onAuthStateChange`). `SessionStatus` carrega
  `isAuthenticated`, `role`, `workerProfileComplete`.
- **Recuperação de password**: fluxo real por OTP — `resetPasswordForEmail` →
  `verifyOTP(type: OtpType.recovery)` → `updateUser`. **Bypass de `kDebugMode`**: em
  `verifyPasswordResetOtp`, se o código real (6 dígitos) falhar E `kDebugMode` for
  `true`, simula sucesso sem abrir sessão de recuperação real — `updatePassword`
  depois não teria efeito nenhum nesse caminho; serve só para testar o ecrã visualmente
  sem ir ao email. Nunca ativo em release (`kDebugMode` é sempre `false` aí).
- **Erros classificados**: `AuthRepository._throwClassified` relança sempre um
  `AuthException` com uma de 3 tags (`PasswordResetErrorCode.network/invalidCode/unexpected`)
  para o `PasswordResetController` decidir entre erro inline e `AppSystemStateScreen`
  — ver secção 11.

---

## 7. Backend Supabase

**Fonte:** `supabase/migrations/0001_consolidated_baseline.sql` (schema completo até
2026-07-09, reconstruído de um snapshot da BD viva) + migrations numeradas 0033–0065
aplicadas por cima (a 0050 não existe). **Todas aplicadas na BD viva, confirmado pelo
Henrique a 2026-10-27.** `archive/` tem as 32 migrations incrementais originais — não
aplicar, só para git blame. **Verificado em 2026-10-16 contra um dump real da BD
viva** (`supabase db dump`, projeto `twpflvcoyeiysnychkom`): as 37 funções, 14
tabelas e 3 views da BD viva coincidiam exatamente com a soma das migrations
0001+0033–0040, incluindo as 4 RPCs de 0040. Da 0041 em diante a confirmação é a
palavra do Henrique, sem dump novo. Único drift encontrado: o trigger
em `job_requests` chama-se `on_job_created` na BD viva, não
`trigger_notify_workers_new_job` como no ficheiro da migration (mesma função,
provavelmente renomeado manualmente no Studio — ver secção 16).

### Tabelas principais

| Tabela | Propósito | Colunas-chave |
|---|---|---|
| `profiles` | 1:1 com `auth.users` | `id` (FK→auth.users, `ON DELETE CASCADE` desde 0036), `role`, `full_name`, `phone`, `avatar_url` (texto livre; a app só mostra URLs do Storage do projeto, `StorageUrls`), `deleted_at` (0049: conta eliminada, anonimizada e sem login) |
| `worker_profiles` | dados de quem presta serviço | `profile_id` PK, `base_lat/lng`, `radius_km`, `tools[]`, `location_name` (0030), `highlights[]` e `social_links` jsonb (0051, com CHECK: até 5 destaques de 80 caracteres, até 4 links só `https://`) |
| `service_categories`/`service_types` | catálogo | `slug`, `name`, `icon`, `sort_order`; desde 0045: Jardinagem, Agricultura e Floresta, 33 tipos (ícone traduzido em `core/widgets/service_icon.dart`) |
| `worker_service_types` | N:N worker↔serviço | PK composta |
| `job_requests` | pedidos | `status`, `accepted_proposal_id`, `confirmed_*`, `reschedule_*`, `excluded_worker_ids[]`, `expires_at`, `location_area` (0043), `completion_photo_path`/`marked_done_at` + controlo de lembretes (0046), `started_at`/`before_photo_paths`/`after_photo_paths` (0052), `search_extra_km`/`visible_to_all_at`/`followup_stage`/`no_proposals_nudged_at` (0062, só o servidor muda), pedido direto `direct_worker_id`/`direct_source_job_id`/`direct_until`/`direct_status` (0057); desde a 0059 `direct_card_worker_id` (pedido pelo cartão), `direct_auto_release` (interruptor do passo 4), `direct_origin` (`public_card`/`repeat_hire`/`your_gardeners`), `direct_hold_reason` e `card_visit_id`, e `direct_status` aceita `on_hold` |
| `job_photos` | até 2 por job | `storage_path` (bucket `job-photos`) |
| `job_proposals` | propostas de workers | `status`, `people_needed`, `estimated_hours_min/max`, `helpers_equipment_required`; desde a 0058 `pricing_mode` (`hourly`/`fixed_total`), `total_price`, `includes[]`, `estimated_days_min/max`, `valid_until`. No valor total, `hourly_rate` é uma taxa de referência calculada no servidor (só para o pagamento dos ajudantes) |
| `proposal_include_options` (0058) | opções do "O que inclui" | `slug`, `label`, `sort_order`, `active`; leitura por autenticados |
| `job_work_days` (0058) | dias de um trabalho em vários dias | `job_id`, `day_number`, `started_at`, `ended_at` (no máximo um aberto); só por RPC |
| `worker_card_visits` (0059) | aberturas do cartão público `/w/:id` | `worker_id`, `source` (`qr`/`link`/`app`), `device_key` (id aleatório do aparelho), `visitor_id`; RLS sem políticas, só por RPC e SQL Editor |
| `client_referrals` (0059) | clientes novos trazidos por um cartão | `client_id` PK, `worker_id`, `visit_id`, `source`; RLS sem políticas, só por RPC e SQL Editor |
| `notifications` | 38 tipos (secção 9) | `type`, `related_id`, `read`, `cleared_at` (0065: "Limpar tudo"; escondidas na app e apagadas de vez 1 dia depois) |
| `seasonal_campaigns` / `seasonal_campaign_sends` (0062) | dicas da época (outubro e fevereiro) e registo de envio por ano | `slug`, `month`, `day`, `audience`, `title`, `body`, `active`; só SQL Editor e cron |
| `notification_preferences` (0062) | interruptor "Dicas da época" | `user_id` PK, `seasonal_tips` (ligado por omissão); só por RPC |
| `device_tokens` (0041) | tokens FCM | `token` PK, `user_id`, `platform`; escrita só por RPC |
| `help_requests` | pedido de ajudantes | `status` incl. `pending_approval` |
| `help_acceptances` | candidaturas de ajudantes | `agreed_rate`, `brought_equipment`, `message` (0034 — ver secção 16) |
| `ratings` | avaliações | `UNIQUE(job_id, rater_id, ratee_id)`, `CHECK(rater_id <> ratee_id)` |
| `job_reports` | reports pós-trabalho | moderação manual, sem RLS de leitura cruzada |
| `worker_fleet_cards` (0037) | cartão frota fictício | `status` pending/active/rejected, sem policy UPDATE para `authenticated` |
| `admin_users` (0060) | quem é administrador | `user_id` (FK `auth.users`); só se escreve por SQL Editor; RLS sem policies |
| `admin_actions` (0060) | registo das mudanças feitas no painel | `admin_id`, `action`, `target_id`, `details` jsonb; RLS sem policies |
| `worker_calendar_entries` (0064) | Agenda: trabalhos fora da app (`kind = job`) e indisponibilidades (`block`) | `worker_id` DEFAULT `auth.uid()`, `starts_on`, `start_time`, `duration_minutes`, `ends_on`, `recurrence` none/weekly/biweekly/monthly, `recurrence_until`, `person_name`/`person_phone` (só para WhatsApp), `amount`, `status` scheduled/done/cancelled (cancelado continua na agenda), `status_at` (trigger); RLS só do dono, INSERT só com papel worker |
| `worker_calendar_exceptions` (0064) | "Só este dia" numa série | `entry_id`, `occurrence_date`, `action` skipped (sai da agenda)/moved/changed/status, `new_*`, `status` done/cancelled só nesse dia, `status_at`; RLS só do dono |
| `worker_plans` (0060) | plano do jardineiro | `tier` free/pro/pro_plus, `starts_at`, `ends_at`, `verified_at`, `notes`; RLS sem policies (o jardineiro lê por `get_my_plan`, sem as notas). O `role` não muda |

### RLS — resumo por tabela (ver os ficheiros de migration para o texto exato das policies)

- `profiles`: próprio vê/edita o seu; **sem policy pública** desde o hardening de 0032
  — worker só vê cliente com proposta `accepted`; cliente só vê worker com job
  confirmado (via `client_has_confirmed_job_with_worker`).
- `worker_profiles`: owner-only SELECT (0030) — descoberta pública passa pela view
  `worker_profiles_public`.
- `job_requests`: cliente vê os seus; worker vê `open` (qualquer autenticado, sem
  filtro de raio ao nível da RLS — o raio é só um filtro de RPC/UI) + jobs onde tem
  proposta (`worker_has_proposal_for_job`).
  **Desde a 0043 (aplicada a 2026-10-16):** o worker deixa de ler `job_requests` por RLS, exceto
  o worker aceite (`can_see_exact_job_location`). Os outros leem pelas RPCs
  (`get_job_by_id`, `get_jobs_in_radius`, `get_worker_job_board`), que devolvem
  `location_area` e coordenadas arredondadas em vez da morada exata até a proposta
  ser aceite.
- `job_proposals`: worker vê as suas; cliente vê as dos seus jobs.
- `notifications`: cada um só vê as suas; sem policy INSERT (só RPCs `SECURITY DEFINER`
  escrevem).
- `help_requests`/`help_acceptances`: principal (via `is_principal_worker_for_help_request`)
  e o próprio candidato; cliente vê help_requests dos seus jobs.
- `ratings`: leitura pública (`USING(true)`); escrita só com participação verificada
  inline na própria policy.
- `job_reports`: cada um só vê os seus; INSERT exige ser cliente ou worker aceite do job.
- `worker_fleet_cards`: owner-only SELECT/INSERT; mudança de `status` só via service role.

### RPCs (`SECURITY DEFINER`, `SET search_path`, identidade sempre por `auth.uid()` — nunca um `p_worker_id`/`p_client_id` vindo do cliente desde 0032)

| Função | Parâmetros | Devolve | Chamada por |
|---|---|---|---|
| `worker_has_proposal_for_job` | `job_id` | `boolean` | só RLS |
| `is_principal_worker_for_help_request` | `p_help_request_id` | `boolean` | RLS + reaproveitada em `get_candidates_for_help_request` (0040) |
| `client_has_confirmed_job_with_worker` | `worker_id` | `boolean` | só RLS |
| `accept_proposal` | `p_proposal_id, p_job_id` | `void` | `ProposalRepository.acceptProposal` |
| `create_proposal` | `p_job_id, p_hourly_rate, ...7 opcionais` (sem `p_worker_id` desde 0044) | `uuid` | `ProposalRepository.createProposal` |
| `sync_worker_service_types` | `p_service_type_ids[]` (sem `p_worker_id` desde 0044) | `void` | `WorkerRepository` |
| `reject_proposal` | `p_proposal_id, p_job_id` | `void` | `ProposalRepository.rejectProposal` |
| `withdraw_proposal` | `p_proposal_id, p_job_id` | `void` | `ProposalRepository.withdrawProposal` |
| `confirm_job_completion` | `p_job_id` | `void` | `ProposalRepository.confirmJobCompletion` |
| `accept_help_candidate` | `p_help_acceptance_id, p_agreed_rate` | `void` | `HelpRequestRepository` |
| `accept_reschedule` | `p_job_id` | `void` | `JobRepository.acceptReschedule` |
| `approve_help_request` | `p_help_request_id` | `void` | `HelpRequestRepository.approveHelpRequest` |
| `auto_confirm_completed_jobs` | — | `void` | **pg_cron só** (`0 */3 * * *`; `15 * * * *` desde a 0052: lembrete às 24h e confirmação às 48h), sem caller Dart |
| `auto_expire_jobs` | — | `void` | **pg_cron só** (`0 */3 * * *`), sem caller Dart |
| `cancel_job` | `p_job_id, p_reason, p_reason_detail?, p_client_wants_reopen?` | `uuid` (novo job se reaberto) | `JobRepository.cancelJob` |
| `get_accepted_helpers_for_job` | `p_job_id` | `TABLE(worker_id, full_name, avatar_url)` (foto desde a 0054; desde a 0055 responde também ao cliente do trabalho) | `RatingRepository` (avaliações, cartão "Equipa" do responsável e do cliente) |
| `get_help_requests_in_radius` | `worker_lat, worker_lng, radius_km` | `TABLE(... principal_name, principal_avatar_url, payment_per_helper, confirmed_date/time)` — shape atual é a soma de 0034+0039, ver nota | `HelpRequestRepository` |
| `get_job_by_id` (0043) | `p_job_id` | `SETOF job_requests` (mascarado se a proposta não foi aceite) | `JobRepository.fetchJobById` |
| `get_jobs_in_radius` | `worker_lat, worker_lng, radius_km` (sem `p_worker_id` desde 0044) | `SETOF job_requests`; desde a 0062 também os pedidos até `radius_km + search_extra_km` | `JobRepository.fetchJobsInRadius` |
| `widen_job_search` (0062) | `p_job_id` | `integer` (novo `search_extra_km`): +10 km, máximo 30, só o dono de um pedido aberto e não reservado | `JobRepository.widenJobSearch` |
| `get_my_notification_preferences` / `set_seasonal_tips` (0062) | — / `p_enabled` | `seasonal_tips` / `void` | `NotificationRepository` ("Dicas da época" em Definições do cliente) |
| `get_my_help_acceptances` | — | `TABLE(... principal_name, principal_phone, job_status, ...)` | `HelpRequestRepository.fetchMyHelpAcceptances` |
| `mark_job_done` | `p_job_id, p_photo_path?` (0046; só a partir do dia do trabalho). Desde a 0052: `p_job_id, p_photo_paths text[]` (até 3 fotos de depois) e exige `started_at` | `void` | `ProposalRepository.markJobCompleted` |
| `start_job` (0052) | `p_job_id, p_photo_paths text[]` (até 3 fotos de antes; a partir de 1h antes da hora) | `void` | `JobRepository.startJob` |
| `propose_reschedule` | `p_job_id, p_new_date, p_new_time?, p_new_flexible?` | `void` | `JobRepository.proposeReschedule` |
| `reject_help_candidate` | `p_help_acceptance_id` | `void` | `HelpRequestRepository.rejectHelpCandidate` |
| `reject_reschedule` | `p_job_id` | `void` | `JobRepository.rejectReschedule` |
| `submit_client_rating` | `p_job_id, p_stars, p_comment?` | `void` | `RatingRepository` |
| `submit_helper_rating` | `p_job_id, p_stars, p_comment?` | `void` | `RatingRepository` |
| `submit_principal_rating` | `p_job_id, p_ratee_id, p_stars, p_comment?` | `void` | `RatingRepository` |
| `withdraw_help_acceptance` | `p_help_acceptance_id` | `void` (aceite só até à véspera, 0055) | `HelpRequestRepository.withdrawHelpAcceptance` |
| `apply_to_help_request` (0048) | `p_help_request_id, p_brought_equipment, p_message?` | `uuid` (permite voltar a candidatar depois de desistir) | `HelpRequestRepository` |
| `cancel_help_request` / `update_help_request_slots` / `remove_help_helper` (0049; `remove_help_helper` revista na 0055) | `p_help_request_id` / `p_help_request_id, p_slots` / `p_help_acceptance_id` | `void` (só o jardineiro responsável: cancelar o pedido de ajuda, mudar vagas, retirar um ajudante) | `HelpRequestRepository` |
| `update_job_request` (0049) | `p_job_id, p_description, p_date_mode, p_preferred_date, p_availability_text, p_address_text, p_location_lat/lng, p_location_area` | `void` (só o dono, pedido `open`; avisa quem já propôs com `job_updated`) | `JobRepository` ("Editar pedido") |
| `delete_my_account` (0049) | — | `void` (anonimiza o perfil, marca `deleted_at` e bloqueia o login) | `AuthRepository` |
| `clear_my_notifications` / `restore_my_notifications` (0065) | — / `p_ids uuid[]` | `uuid[]` limpos / `integer` repostos | `NotificationRepository.clearAll` / `restore` ("Limpar tudo" e "Desfazer" de 6 s) |
| `get_my_profile_stats` (0065) | — | `TABLE(completed_jobs, member_since)` | `WorkerRepository` (números do Perfil do jardineiro) |
| `get_worker_agenda` (0064) | `p_from, p_to` (máx. 62 dias) | `TABLE(entry_kind, source_id, job_id, occurrence_date, series_date, start_time, end_time, day_index, day_count, title, service_type_id, location_label, person_name, person_phone, status, is_tentative, amount_min, amount_max, recurrence, is_exception, notes, proposal_id, location_lat, location_lng)`, uma linha por dia; `entry_kind` app_job/helper_job/proposal/reschedule/external/block | `AgendaRepository` (Agenda do jardineiro; sobreposições em `agenda_conflicts.dart`) |
| `split_calendar_series` (0064) | `p_entry_id, p_from_date` | `uuid` da série nova | `AgendaRepository.splitSeries` ("Este e os seguintes") |
| `free_calendar_day` (0064) | `p_entry_id, p_series_date, p_day` | `void` | `AgendaRepository.freeDay` ("Já estou livre": só esse dia de uma indisponibilidade) |
| `get_worker_job_board` (0035, última 0058: `pricing_mode`, `total_price` no fim) | `p_tab, p_page?, p_page_size?` | `TABLE(... person_name, total_count, ..., people_needed, helpers_equipment_required)` | `WorkerJobBoardRepository` — unifica "Os meus trabalhos" (responsável+ajudante) |
| `get_my_ratings_received`/`get_my_ratings_given` (0038) | — | `TABLE(... party_name, party_avatar_url, service_type_name)` | `RatingRepository` — alimenta `my_ratings_screen.dart` |
| `get_open_job_client_identity` (0040) | `p_job_id` | `TABLE(client_name, client_avatar_url)` | `JobRepository.fetchOpenJobClientIdentity` |
| `get_pending_proposals_for_job` (0040) | `p_job_id` | colunas de `job_proposals` + `worker_name/avatar_url` | `ProposalRepository.fetchPendingProposalsForJob` |
| `get_candidates_for_help_request` (0040; a 0047 junta `message`) | `p_help_request_id` | colunas de `help_acceptances` + `worker_name/avatar_url` + `message` (0047) | `HelpRequestRepository.fetchCandidatesForHelpRequest` |
| `get_ratings_with_rater_identity` (0040) | `p_ratee_id` | colunas de `ratings` + `rater_name/avatar_url` | `RatingRepository.fetchRatingsWithRaterNames` |
| `register_device_token` / `unregister_device_token` (0041) | `p_token, p_platform` / `p_token` | `void` | `PushNotificationService` |
| `send_job_reminders` (0046) | — | `void` | **pg_cron só** (`job-reminders`), só `service_role` |
| `cleanup_old_notifications` (0042) | — | `void` | **pg_cron só** (`cleanup-old-notifications`) |
| `close_help_requests_on_job_day` (0054) | — | `void` | **pg_cron só** (`close-help-requests-on-job-day`, `5 * * * *`) |
| `process_help_request_deadlines` (0055) | — | `void` | **pg_cron só** (`process-help-request-deadlines`, `10 * * * *`) |
| `release_direct_job_request` (0057) | `p_job_id` | `void` (cliente abre já a todos o pedido reservado) | `JobRepository.releaseDirectJobRequest` |
| `decline_direct_job_request` (0057) | `p_job_id` | `void` (jardineiro escolhido diz "Não posso desta vez"; recusa se já tem proposta pendente) | `JobRepository.declineDirectJobRequest` |
| `get_repeat_hire_for_job` (0057) | `p_job_id` (trabalho concluído do cliente) | `TABLE(worker_id, worker_name, worker_avatar_url, service_type_id, job_date, can_request, my_stars)` | `JobRepository.fetchRepeatHireForJob` |
| `get_my_previous_workers` (0057) | — | `TABLE(worker_id, worker_name, worker_avatar_url, last_job_id, service_type_id, job_date)` (último trabalho concluído por jardineiro, sem os avaliados abaixo de 4, até 10) | `JobRepository.fetchMyPreviousWorkers` |
| `get_direct_request_context` (0057, última 0063) | `p_job_id` (só o jardineiro escolhido) | `TABLE(client_name, job_date, service_type_id, hourly_rate, pricing_mode, total_price)` ("Já trabalhaste com..." mostra o valor fechado quando foi a valor total) | `JobRepository.fetchDirectRequestContext` |
| `expire_direct_job_requests` (0057, última 0059) | — | `void` | **pg_cron só** (`expire-direct-job-requests`, `*/5 * * * *`); desde a 0059 respeita o interruptor (abre a todos ou deixa parado, `on_hold`) |
| `log_worker_card_visit` (0059) | `p_worker_id` (o cartão aberto, não a identidade), `p_source`, `p_device_key?` | `uuid` da visita, ou `null` (o próprio, cartão desligado); o mesmo aparelho no mesmo cartão em 30 min conta uma vez. `anon` e `authenticated` | `WorkerRepository.logCardVisit` |
| `claim_worker_card_visit` (0059) | `p_visit_id` | `void`: liga a visita a `auth.uid()` e, se a conta de cliente nasceu até 7 dias depois, cria `client_referrals` | `WorkerRepository.claimCardVisit` |
| `create_proposal` (última 0058) | os de 0044 e, no fim, todos com omissão: `p_pricing_mode`, `p_total_price`, `p_includes`, `p_estimated_days_min/max`, `p_valid_until` (`p_hourly_rate` passa a opcional) | `uuid` | `ProposalRepository.createProposal` |
| `get_pending_proposals_for_job` (última 0058) | `p_job_id` | colunas de 0040 + `pricing_mode`, `total_price`, `includes`, `estimated_days_min/max`, `valid_until`, `is_expired` | `ProposalRepository.fetchPendingProposalsForJob` |
| `finish_work_day` / `start_work_day` (0058) | `p_job_id` (jardineiro responsável, trabalho iniciado) | `void` (fecha o dia aberto / abre o seguinte) | `ProposalRepository.finishWorkDay` / `startWorkDay` |
| `get_job_work_days` (0058) | `p_job_id` (cliente, responsável ou ajudante aceite) | `TABLE(day_number, started_at, ended_at)`; sem linhas usa `started_at`/`marked_done_at` | `ProposalRepository.fetchWorkDays` |
| `get_my_plan` (0060) | — | `TABLE(tier, ends_at, verified, jobs_this_month, monthly_job_limit)` | `WorkerRepository.fetchMyPlan` (linha "Plano" da conta) |
| `admin_whoami` (0060) | — | `TABLE(is_admin, has_mfa)` (aal2) | `AdminRepository.fetchAccess` |
| `admin_overview` (0060) | `p_days?` (NULL = sempre) | `jsonb` (utilizadores, coorte de pedidos do período, avaliações, planos, alertas) | `AdminRepository.fetchOverview` |
| `admin_list_workers` (0060) | `p_search?, p_tier?, p_limit, p_offset` | `TABLE(... tier, plan_ends_at, last_sign_in_at, jobs_completed, avg_rating, total_count)` | `AdminRepository.fetchWorkers` |
| `admin_get_worker` (0060) | `p_worker_id` (alvo, não identidade) | `jsonb` (ficha, números, 6 meses, plano e histórico) | `AdminRepository.fetchWorker` |
| `admin_set_worker_plan` (0060) | `p_worker_id, p_tier, p_starts_at?, p_ends_at?, p_verified_at?, p_notes?` | `void` (+ linha em `admin_actions`) | `AdminRepository.setWorkerPlan` |

As RPCs `admin_*` (menos `admin_whoami`) chamam `assert_verified_admin()`: `auth.uid()` em `admin_users` **e** `auth.jwt()->>'aal' = 'aal2'` (segundo fator TOTP do Supabase Auth). Recebem o id do jardineiro **alvo**; a identidade de quem chama continua a ser só `auth.uid()`.

**Nota sobre `get_help_requests_in_radius`:** passou por 3 shapes (baseline → 0034 → 0039),
sempre via `DROP FUNCTION` + `CREATE` explícito porque o `RETURNS TABLE` muda de forma
a cada vez — convenção obrigatória nesta base de código quando o shape de retorno
muda (ver secção 13).

### Views

| View | `security_invoker` | Exposto a | Colunas |
|---|---|---|---|
| `worker_profiles_public` | **não** (definer-style, deliberado) | `authenticated` | `bio, radius_km, tools, location_name, photos` — sem coordenadas |
| `worker_rating_summary` | **sim** (deliberado — ratings já é `USING(true)`) | `authenticated` | `worker_id, avg_rating, rating_count` |
| `worker_public_card` (0033) | não | `anon` + `authenticated` | nome, avatar, bio, zona, serviços, rating e, desde a 0051, `highlights`/`social_links` — sem telefone/coordenadas/raio. Desde a 0059 também `service_type_ids`, `can_use_public_card`, `can_receive_direct_requests` e a última avaliação de 4 ou 5 estrelas com comentário (`latest_review_*`, primeiro nome) |
| `worker_card_funnel` (0059) | não | ninguém (só SQL Editor) | por jardineiro: visitas (QR, link, app), aparelhos, visitantes com sessão, clientes novos, pedidos pelo cartão e quantos foram contratados |

### Triggers

| Trigger | Tabela | Evento | Função |
|---|---|---|---|
| `on_job_created` (ficheiro define-o como `trigger_notify_workers_new_job`, ver secção 16) | `job_requests` | AFTER INSERT | `notify_workers_new_job()` — insere `new_job_in_radius` para cada worker no raio Haversine que faz o serviço (ou sem serviços escolhidos), desde a 0054 |
| `trg_notify_workers_new_help_request` (0054) | `help_requests` | AFTER INSERT / UPDATE OF status | `notify_workers_new_help_request()` — `new_help_request_in_radius` quando o pedido abre (criado aberto ou aprovado), mesmo filtro de raio e serviço |
| `trg_help_request_before_update_job_day` / `trg_help_acceptance_before_update_job_day` (0054) | `help_requests` / `help_acceptances` | BEFORE UPDATE OF status | recusam aprovar o pedido e aceitar candidatos a partir do dia do trabalho |
| `trg_job_request_direct_before_insert` (0057) | `job_requests` | BEFORE INSERT | limpa os campos diretos e, com `direct_source_job_id`, valida que o pedido de origem é do cliente e está concluído, tira o jardineiro da proposta aceite e reserva 24h (`direct_status = 'waiting'`). A app nunca manda o id do jardineiro |
| `trg_job_proposal_direct_before_insert` / `trg_job_proposal_direct_after_status` (0057) | `job_proposals` | BEFORE INSERT / AFTER UPDATE OF status | bloqueiam propostas de outros enquanto a reserva está ativa; proposta do escolhido recusada abre a todos (`released`), retirada conta como recusa (`declined`) |
| `trg_set_proposal_accepted_at` / `trg_enforce_free_plan_limit` (0060) | `job_proposals` | BEFORE UPDATE OF status / BEFORE INSERT | grava `accepted_at`; recusa proposta nova de um jardineiro sem Pro/Pro+ em vigor com 5 trabalhos aceites no mês (Lisboa). Limite suave: propostas já pendentes ainda podem ser aceites |
| `trg_job_request_direct_lock_update` (0059) | `job_requests` | BEFORE UPDATE | a app não muda nenhum campo do pedido direto depois de criado (só as RPCs e o cron) |
| `trg_job_proposal_block_expired_accept` (0058) | `job_proposals` | BEFORE UPDATE OF status | recusa aceitar uma proposta com `valid_until` passado ("Este orçamento expirou e já não pode ser aceite."). A app nunca decide a validade pelo relógio do telemóvel |
| `trg_job_requests_sync_work_days` (0058) | `job_requests` | AFTER UPDATE OF started_at, status | cria o dia 1 quando o trabalho começa e fecha o dia aberto ao marcar concluído ou cancelar |
| `tg_prevent_profile_role_change` | `profiles` | BEFORE UPDATE | `prevent_profile_role_change()` — bloqueia mudar `role` por UPDATE direto |

### Storage

2 buckets, ambos `public = true`: `avatars`, `job-photos`. Policies: leitura pública;
upload por autenticado com o path a bater com `auth.uid()` (avatars: nome do ficheiro;
job-photos: primeira pasta do path); update/delete só pelo dono.

### pg_cron

`auto-expire-jobs` e `auto-confirm-completed-jobs`, ambos `0 */3 * * *` (cada 3h); desde 0046 também `job-reminders` (`30 7 * * *`, `send_job_reminders`); desde 0042 `cleanup-old-notifications` (`30 3 * * *`). `auto_expire_jobs` passa a expirar pedidos abertos com data fixa passada e trabalhos confirmados 3 dias depois da data. Desde a 0054, `close-help-requests-on-job-day` (`5 * * * *`) fecha os pedidos de ajuda no dia do trabalho: candidaturas pendentes recusadas e avisadas, equipa fica com os aceites (`filled`) ou o pedido é cancelado, aviso `help_request_closed` ao responsável. A descoberta e as candidaturas já fecham à meia-noite (filtro `confirmed_date > today_pt()`), sem esperar pelo cron. Desde a 0055, `process-help-request-deadlines` (`10 * * * *`) aprova sozinho o pedido de ajudantes que está por aprovar há 24h (se o dia ainda não chegou; avisos `help_request_approved` ao responsável e `help_request_auto_approved` ao cliente) e, na véspera a partir das 18h de Portugal, avisa uma vez (`help_requests.eve_reminder_sent_at`): o responsável com candidatos por decidir ou vagas livres (`help_request_closing_soon`) e o cliente que ainda não aprovou (`help_request_pending_approval`). No dia do trabalho o ajudante aceite já não pode desistir e, se o responsável o retirar, a vaga não reabre (`remove_help_helper`). Desde a 0057, `expire-direct-job-requests` (`*/5 * * * *`) abre a todos os pedidos diretos cuja reserva de 24h passou (`direct_status = 'expired'`, aviso `direct_request_released` ao cliente). A visibilidade já depende da hora (`job_reserved_for_other`), por isso o atraso do cron só atrasa os avisos. Desde a 0062, `open-job-followups` (`15 * * * *`, só das 8h às 21h de Portugal) trata os pedidos abertos sem propostas: às 6h lembra os jardineiros da zona (`job_opportunity_reminder`), às 24h mostra o pedido 10 km mais longe (aviso `new_job_in_radius` "Pedido um pouco mais longe" a quem fica no novo anel, prazo estendido 24h) e avisa o cliente (`job_no_proposals_yet`); e `seasonal-campaigns` (`0 10 * * *`) envia as dicas da época uma vez por ano a cada cliente que não as desligou.

### Estado das migrations

**Todas aplicadas na BD viva** (confirmado pelo Henrique a 2026-10-27): `0001`, `0033` a
`0049` e `0051` a `0065`. A `0050` nunca foi usada. A tabela com o que cada uma faz está
em `supabase/migrations/README.md`.

Próxima migration: `0066`. Rotas `/client/messages` e `/worker/messages` removidas a 2026-10-18 (contacto só por WhatsApp).

---

## 8. Estados de negócio

### `JobStatus` (`job_requests.status`)

`open → confirmed → awaiting_confirmation → completed`, com `no_response` (48h sem
proposta aceite, via `auto_expire_jobs`) e `cancelled` como saídas.

| Transição | RPC | Notificação |
|---|---|---|
| criar pedido | INSERT direto | `new_job_in_radius` (trigger) |
| pedido direto ("Pedir de novo", 0057, ou pelo cartão, 0059; continua `open`, `direct_status` à parte: `waiting → declined/expired/released`, ou `on_hold` com o interruptor desligado até o cliente decidir) | INSERT direto com `direct_source_job_id` ou `direct_card_worker_id`; `decline_direct_job_request`, `release_direct_job_request`, cron | `direct_job_request` só ao escolhido; ao abrir a todos `new_job_in_radius` e, se recusou ou expirou, `direct_request_released` ao cliente |
| aceitar proposta → `confirmed` | `accept_proposal` | `proposal_accepted` / `proposal_rejected` (outras) |
| worker inicia (continua `confirmed`, "Em curso" = `started_at` preenchido, 0052) | `start_job` | `job_started` |
| worker marca concluído → `awaiting_confirmation` | `mark_job_done` | `job_marked_done` |
| cliente confirma → `completed` | `confirm_job_completion` | `job_completed` |
| 3 dias (48h desde a 0052) sem confirmação nem problema reportado → `completed` | `auto_confirm_completed_jobs` (cron) | `job_completed` |
| pedido aberto sem propostas (continua `open`, 0062) | `process_open_job_followups` (cron): às 6h lembra os jardineiros da zona, às 24h mostra o pedido 10 km mais longe e estende o prazo 24h; o cliente pode alargar até 30 km (`widen_job_search`) | `job_opportunity_reminder`, `new_job_in_radius` ao anel novo, `job_no_proposals_yet` ao cliente |
| 48h sem proposta → `no_response` | `auto_expire_jobs` (cron) | `job_no_response` |
| cancelar | `cancel_job` | `job_cancelled` (+ `job_reopened` se reaberto) |

### `ProposalStatus`: `pending → accepted/rejected/superseded` — `create_proposal`,
`accept_proposal` (auto-rejeita as outras), `reject_proposal`, `withdraw_proposal`.

### `RescheduleStatus`: `pending → accepted/rejected` — `propose_reschedule`,
`accept_reschedule`, `reject_reschedule`. Só em jobs `confirmed`; regra das 24h.

### `HelpRequestStatus`: `pending_approval → open → filled`, + `cancelled` (cascade de
`cancel_job`). `approve_help_request` move `pending_approval → open`.

### `HelpAcceptanceStatus`: `pending → accepted/rejected`, + `cancelled` (desistência) —
`accept_help_candidate`, `reject_help_candidate`, `withdraw_help_acceptance`,
`remove_help_helper`.

### Trabalhos em vários dias (0058): `job_work_days`, um dia aberto de cada vez. O trigger
cria o dia 1 em `start_job`; `finish_work_day` fecha o dia, `start_work_day` abre o
seguinte; marcar concluído ou cancelar fecha o que estiver aberto.

### Agenda (0064, `worker_calendar_entries.status`): `scheduled → done/cancelled`, e
volta a `scheduled` ao repor. Numa série, "Só este dia" grava o estado na exceção
(`worker_calendar_exceptions.status`), sem mexer na série. Cancelado continua visível,
riscado; apagar é outra ação. Os trabalhos da app não têm estado próprio na Agenda: vêm
de `job_requests`/`job_proposals`/`help_acceptances` através de `get_worker_agenda`.

---

## 9. Notificações

38 tipos (`notification_types.dart`, contagem a 2026-10-27), todos inseridos por RPCs `SECURITY DEFINER`, pelo cron
ou por triggers — nunca por INSERT direto do Flutter (sem policy
INSERT em `notifications`). Dois consumidores independentes do mesmo stream
(`notificationsStreamProvider`, Realtime sobre `notifications`):

1. **`notification_handler.dart`** — navegação ao tocar numa notificação. A maioria
   usa `context.go()` (substitui a stack — ver secção 13 para o porquê e o fallback de
   voltar); os do lobby e da descoberta de ajudantes (`help_request_approved`,
   `help_candidate_applied`, `help_withdrew`, `help_request_closed`,
   `help_request_closing_soon`, `help_request_reopened`, `new_help_request_in_radius`) e
   a dica da época do cliente usam `context.push()` de propósito, para preservar o
   botão de recuar.
2. **`notification_providers.dart`** (`notificationSyncProvider`) — invalida os
   providers de dados certos para cada tipo novo que chega, sem esperar por
   pull-to-refresh. Tabela completa em `state_machine.md`; o código também invalida
   `workerJobBoardPageProvider` (as 3 tabs, página 0) sempre que invalida os providers
   antigos equivalentes, para o board unificado (0035) ficar em sincronia.

| Tipo | Nasce em | Destino (navegação) | go/push |
|---|---|---|---|
| `new_job_in_radius` | trigger | `/worker/job/:id` | go |
| `proposal_received` | `create_proposal` | `/client/job/:id` | go |
| `proposal_withdrawn` | `withdraw_proposal` | `/client/job/:id` | go |
| `proposal_accepted` | `accept_proposal` | `/worker/my-job/:id` (fetch async) | go |
| `proposal_rejected` | `accept_proposal` (outras propostas) | `/worker/job/:id` | go |
| `job_cancelled` | `cancel_job` | `/client/job/:id` ou `/worker/my-job/:id` | go |
| `job_reopened` | `cancel_job` | `/worker/job/:id` | go |
| `job_started` (0052) | `start_job` | `/client/job/:id` | go |
| `job_marked_done` | `mark_job_done` | `/client/job/:id` | go |
| `job_completed` | `confirm_job_completion`/cron | `/client/job/:id` ou `/worker/my-job/:id` | go |
| `job_no_response` | `auto_expire_jobs` (cron) | `/client/job/:id` | go |
| `job_reminder` (0046) | `send_job_reminders` (cron: manhã do dia, data passada sem conclusão, conclusão à espera do cliente) | `/client/job/:id` ou `/worker/my-job/:id` | go |
| `job_updated` (0049) | `update_job_request` (a quem já propôs) | `/worker/job/:id` | go |
| `reschedule_proposed/accepted/rejected` | `propose/accept/reject_reschedule` | `/client/job/:id` ou `/worker/my-job/:id` | go |
| `help_request_approved` | `approve_help_request` | `/worker/job/:id/help-requests` | **push** |
| `help_accepted`/`help_rejected` | `accept/reject_help_candidate` | `/worker/help/:id` (ou `/worker/help-requests` tab 1 se não encontrar a candidatura) | go |
| `help_job_cancelled` | `cancel_job` (cascade) | idem | go |
| `help_removed` / `help_job_rescheduled` / `help_job_done` / `help_job_completed` (0049) | `remove_help_helper`, trigger `notify_helpers_on_job_change` | idem (ajudante) | go |
| `help_candidate_applied` (0048) | `apply_to_help_request` (ao responsável) | `/worker/job/:id/help-requests` | **push** |
| `help_request_pending_approval` (0048, véspera desde a 0055) | trigger em `help_requests` / `process_help_request_deadlines` (ao cliente) | `/client/job/:id` | go |
| `help_request_reopened` | `withdraw_help_acceptance` | `/worker/help-requests` | **push** |
| `help_withdrew` | `withdraw_help_acceptance` | `/worker/job/:id/help-requests` | **push** |
| `new_help_request_in_radius` (0054) | trigger em `help_requests` | `/worker/help-requests/:id/apply` | **push** |
| `help_request_closed` (0054) | `close_help_requests_on_job_day` (cron) | `/worker/job/:id/help-requests` | **push** |
| `help_request_closing_soon` (0055) | `process_help_request_deadlines` (cron, véspera) | `/worker/job/:id/help-requests` | **push** |
| `help_request_auto_approved` (0055) | `process_help_request_deadlines` (cron, 24h) | `/client/job/:id` | go |
| `help_job_started` (0055) | trigger `trg_notify_helpers_on_job_change` (`started_at`) | `/worker/help/:id` (como os outros avisos do ajudante) | go |
| `direct_job_request` (0057) | trigger `notify_workers_new_job` (pedido direto) | `/worker/job/:id` | go |
| `direct_request_released` (0057) | `open_direct_job_to_all` (recusa, retirada ou cron) | `/client/job/:id` | go |
| `job_opportunity_reminder` (0062) | `process_open_job_followups` (cron, 6h sem propostas, no máximo 1 por jardineiro em 20h; vários pedidos juntos num só com `related_id` null) | `/worker/job/:id` ou `/worker/available-jobs` | go |
| `job_no_proposals_yet` (0062) | `process_open_job_followups` (cron, 24h sem propostas) | `/client/job/:id` (cartão "Ainda sem propostas") | go |
| `seasonal_tip` (0062) | `send_seasonal_campaigns` (cron diário, campanhas em `seasonal_campaigns`) | cliente: `/client/create-job`; jardineiro: `/worker/available-jobs` | push / go |

**Textos (0062):** o trigger BEFORE INSERT `notifications_add_job_context` reescreve os textos genéricos antigos (nome da outra pessoa, valor da proposta, distância, sempre por tu) antes de juntar " (Serviço, DD/MM)". As funções que criam notificações não mudam; texto novo de um tipo antigo muda-se aí.

Com a app aberta o push do sistema não aparece: `App` ouve `notificationsStreamProvider` e mostra a notificação nova no topo (`AppToast.notification`, ícone e tom de `notificationLook`); tocar abre o mesmo destino e marca como lida. Não aparece no primeiro carregamento nem no ecrã `/notifications`. Desde o PR #37 (2026-10-27) `AppToast.maybeOf` usa o Overlay do próprio Navigator quando recebe o contexto do Navigator raiz (antes devolvia `null` e este aviso nunca aparecia), e o `OverlayEntry` guarda a sua chave fora do builder, para o aviso não reentrar nem recomeçar os 4 s a cada rebuild do Overlay.

**Onde se veem (A11, 2026-10-27):** o cliente tem o separador Alertas na shell
(`/client/alerts`, `NotificationsScreen(inShell: true)`); o jardineiro tem o sino com o
número de não lidas (`HomeNotificationButton`) e abre `/notifications` fora da shell. Os
dois têm "Limpar tudo" (`clear_my_notifications`, 0065) com "Desfazer" durante 6 s; as
limpas ficam marcadas como lidas, a app filtra-as no Dart e o servidor apaga-as de vez 1
dia depois.

---

## 10. Design system e motion

**Tokens** (`core/theme/`): `AppColors` (paleta fixa — primary `#2E7D32`, background
`#F6F8F6`, surface `#FFFFFF`, textPrimary/Secondary, divider), `AppSizes` (caixas de ícone, alturas de botão e larguras dos componentes base, U1), `AppSpacing` (escala do design 19/10: 4·6·8·10·12·14·16·18·20·22·24·26·28·32; xxs4/s6/xs8/s10/sm12/s14/md16/s18/s20/s22/lg24/s26/s28/xl32),
`AppRadius` (input12/card16/pill999), `AppTypography` (Plus Jakarta Sans, display/title/subtitle/body/caption),
`AppStatusColor` (waiting/info/success/cancelled/neutral, cada um com `background`+`foreground`),
`AppMotionDuration`/`AppMotionCurve` (ver abaixo), `AppTheme.light()` (Material 3,
`ColorScheme.fromSeed`, `scaffoldBackgroundColor: AppColors.background`) +
`AppTheme.systemUiOverlayStyle` (barra de navegação do Android).

**Motion** (`docs/motion_spec.md`, tokens em `app_motion_tokens.dart`): durações
`instant`100ms/`fast`200ms/`screen`300ms/`sheet`450ms/`stagger`120ms; curvas
`standard`/`emphasized`/`enter`/`exit`/`reward`. `prefers-reduced-motion` tratado
localmente em cada widget via `MediaQuery.disableAnimations`.

**Widgets partilhados** (`core/widgets/`, 46 ficheiros a 2026-10-27) — assinatura resumida:

| Widget | Parâmetros principais |
|---|---|
| `AppTextField` | `controller`, `label`; opcionais `hintText`, `keyboardType`, `obscureText`, `validator`, `maxLines` |
| `AppSearchField` | `controller`, `hintText`; `onChanged`, `onClear` |
| `AppOtpInput` | `onCompleted`; `length=6`, `onChanged`, `autofocus=true`, `hasError` (caixas até 48, encolhem em ecrãs estreitos) |
| `AppLaunchScreen` | ecrã de `/loading` com o logo (`assets/branding/`), igual ao splash nativo (`flutter_native_splash`, config no `pubspec.yaml`) |
| `AppToast` | `AppToast.of(context)` / `maybeOf` → `.show(msg)` (verde) ou `.error(msg)` (vermelho); `.notification(title, body, icon, color, onTap)` para as notificações com a app aberta. Aviso no topo, no Overlay raiz, sobrevive a `go`/`pop`. Substitui a SnackBar em toda a app (2026-10-21): não usar `ScaffoldMessenger` |
| `AppWhatsAppButton` | Botão de contacto por WhatsApp em toda a app: fundo branco, logótipo do WhatsApp (`appWhatsAppIcon`, fonte de marcas do `font_awesome_flutter`, cor `AppColors.whatsapp`). `compact: true` ao lado de um nome ("WhatsApp" numa linha) |
| `AppPasswordStrengthMeter` | `password` |
| `AppDatePicker` (`showAppDatePicker`, função) | `context`, `initialDate`, `firstDate`, `lastDate` — wrapper do `showDatePicker` nativo só com tema |
| `PrimaryActionButton` | `label`, `onPressed`; `isLoading=false`, `height=52` |
| `BottomActionsBar` | `children` |
| `AppFilterChip` | `label`, `onPressed`; `selected`, `leadingIcon`, `trailingIcon`, `showCheckmark` |
| `AppStatusBadge` | `label`, `statusColor` (ou `.fromPresentation(presentation:)`); `dense` para linhas de lista |
| `AppConfirmDialog` (U1) | `icon`, `title`, `message`, `confirmLabel`, `destructive`; `AppConfirmDialog.show` devolve `true`/`false`/`null`; `isSubmitting`/`errorText` quando a ação corre dentro do diálogo. Substitui os `AlertDialog` de confirmação; os 4 que têm formulário (cancelar, remarcar, reportar, alterar vagas) continuam `AlertDialog` |
| `AppEmptyState` (U1) | `icon`, `title`, `message`, botão opcional (`actionLabel`+`onAction` ou `action`), `tone` (`null` = verde da marca) |
| `AppSheet` (U1) | pega, título com fechar, conteúdo, ação principal e secundária opcionais; abrir com `AppSheet.show` |
| `NextStepRow` (U1) | linha de pedido no Início do cliente: estado curto ao lado do título; com ação, fundo `primaryTint`, ponto verde e próximo passo |
| `TodoRow` (U1) | linha de "O que falta fazer": `icon`, `tone` (`AppStatusColor`), `title` |
| `AppBarStatusBadge` | igual ao `AppStatusBadge` + `trailingMargin=AppSpacing.md` — versão para `AppBar.actions`, com labels curtos próprios (ver `decisions_log.md` 2026-10-16) |
| `AppBackButton` | `color=AppColors.textPrimary`, `tooltip='Voltar'` — chama `goBackOrToRoleHome` |
| `AppBottomNavigation` | `items` (exatamente 4), `selectedIndex`, `onItemSelected`, `onCentralActionPressed` |
| `AppAccountMenuGroup` | `items: List<AppAccountMenuItem>`, `onItemPressed` |
| `AppStepProgress` | `currentStep`, `totalSteps` (`assert(currentStep >= 1)`) — stepper do wizard de criar pedido, nunca tocado pela conversão para `StatusTimelineHorizontal` |
| `StatusTimelineHorizontal` / `StatusTimelineCard` | `steps: List<StatusTimelineStepData>` (`label`, `statusColor`, `state`, `subtitle?`, `dateLabel?`, `note?`, `noteIsWarning`) — único indicador de progresso desde 2026-10-15, largura adaptativa anti-overflow |
| `UserAvatarWithName` | `name`; `avatarUrl?`, `radius=20`, `fallbackLabel?` (mostrado — e usado para a inicial — quando `name` vem vazio) |
| `AddressMapLink` | `address`, `lat`, `lng` |
| `AppBrandBadge` | tudo opcional (`size=60`, cores com default) |
| `AppSystemStateScreen` | construtor base: `icon/iconBackground/iconForeground/title/message/primaryActionLabel/onPrimaryAction`; factories `.noInternet(onRetry)`/`.genericError(onRetry)` |
| `PhotoViewerScreen` | `photoUrls`, `initialIndex` |
| `RatingStarsInput` | `rating`, `onChanged`; `playEntrance=true` |
| `AppStaggeredEntrance` | `index`, `child` — entrada em cascata (máx. 6 itens animados, ver motion_spec) |
| `AppFadeThroughSwitcher` | `switchKey`, `child` |
| `AppPulseScale` | `child`; `enabled=true`, `color=AppColors.primary` — pulso do nó atual da timeline |
| `AppSuccessFeedback` | `visible`, `message` |
| `AppSkeletonShimmer` | `child` |
| `AppTabHeader` / `AppBackHeader` / `AppTabs` (A11, `app_tab_header.dart`) | cabeçalho comum dos ecrãs de topo (título, sino ou ação) / cabeçalho com voltar dos sub-fluxos / tabs com sublinhado verde que desliza, 48 px, `AppTabItem(label, count?, badge?)`. Usados em Trabalhos, Pedidos do cliente, Pedidos de ajuda, Equipa e Alertas |
| `JobFlowStepper` (A12, `job_flow_stepper.dart`) | stepper do fluxo do pedido, 5 fases de `JobFlowStage` (`core/models/job_flow_stage.dart`); a fase vem do presenter (`client_job_flow.dart` cliente, `worker_job_flow.dart` responsável, `helperJobFlowStage` ajudante); `showTeam: false` sem ajudantes. No detalhe `confirmed` da cliente, com os separadores Resumo · Equipa quando há ajudantes |
| `AppProfileCard` (A11) | cartão do topo do Perfil nos dois papéis: avatar com iniciais, nome, linha de contexto, 3 `AppProfileMetric` e, no jardineiro, `actions` do cartão partilhável |
| `HomeNotificationButton` (A11) | sino dos cabeçalhos do jardineiro com o número de não lidas |
| `AppNotificationsView` | vista pura de Notificações (secções, itens, "Limpar tudo"), igual nos dois papéis |
| `AppInitialsAvatar` | avatar sem nome ao lado (foto ou inicial); com nome usar `UserAvatarWithName` |
| `AppInlineError` | erro pequeno com "Tentar novamente" para uma secção que carrega à parte |
| `AppBarTitle` | título de AppBar com segunda linha opcional |
| `showAppTimePicker` | `showTimePicker` com o tema da app, sempre 24h, `helpText` opcional |
| `AppSupportSheet` | "Contacto e suporte": copiar email ou `mailto:` (canal de suporte da app, não contacto entre utilizadores) |
| `AppAboutDialog` | "Sobre a ProJardim": logo, versão, Termos, Privacidade, licenças |
| `AppLegalConsentText` (`app_legal_links.dart`) | frase com Termos e Política com toque; `openTermsOfUse`/`openPrivacyPolicy` |
| `AddressSuggestionsList` | sugestões de morada por baixo de um campo (a carregar, sem resultados, lista) |
| `ServiceCategorySection` / `serviceIcon` | categoria de serviços que abre e fecha, com "Selecionar todos" / ícone por nome vindo da BD |
| `AppAdaptiveShell` / `AppContentWidth` | scaffold das 2 shells (bottom nav no telemóvel, `NavigationRail` a partir de `AppBreakpoints.expanded`) / largura máxima centrada |

---

## 11. Erros e estados de ecrã

- **`friendlyError(Object e)`** (`core/utils/error_utils.dart`) — ponto único de
  mapeamento de exceções para mensagens em português. Cobre rede (via `isNetworkError`),
  autenticação (login inválido, email duplicado, rate limit, password fraca — reusa
  `weakPasswordMessage` de `password_policy.dart`), e casos genéricos da app (24h,
  duplicado/unique, permission denied, estado inválido). Fallback: "Ocorreu um erro
  inesperado. Tenta novamente."
- **`isNetworkError(Object e)`** — `AuthRetryableFetchException` com `statusCode == null`
  (sinal fiável do gotrue) OU correspondência de texto (`network`/`socket`/`failed host
  lookup`/`connection refused`/`timeout`) para as restantes exceções.
- **Padrão de ecrã**: todo `AsyncValue` tratado com `.when(loading:, error:, data:)`;
  loading usa `AppScreenLoadingSkeleton` ou `AppSkeletonShimmer` conforme o ecrã (adoção
  parcial — só 4 ecrãs usam o shimmer, ver `STATUS.md`); vazio é um `Column` próprio por
  ecrã (sem widget partilhado de "empty state"); erro é `Text(friendlyError(e))` inline
  ou `AppSystemStateScreen.genericError`/`.noInternet` para falhas de ecrã inteiro.
- **`AppSystemStateScreen`** — ver assinatura na secção 10.
- Toda lista deve ter 3 estados explícitos: loading, vazio e erro — nenhum ecrã de
  lista deve ficar sem um dos três.

---

## 12. Integrações externas

| Integração | Onde | Como |
|---|---|---|
| Geocoding (OpenStreetMap) | `core/services/geocoding_service.dart` | Sugestões ao escrever (`suggestAddresses`): Photon (`photon.komoot.io`) e, se falhar, Nominatim `/search` (PR #28, 2026-10-23; Google Places só se continuarem a faltar moradas). Pesquisa de uma morada (`searchAddress`): geocoder nativo do telemóvel (`package:geocoding`) com Nominatim como alternativa. Morada a partir do GPS (`reverseGeocode`): Nominatim `/reverse` com `addressdetails=1` e `User-Agent` identificável. Usado em criar/editar pedido e nos ecrãs de perfil/setup do worker |
| Link de mapa | `AddressMapLink` → `url_launcher` para `google.com/maps/search/?api=1&query=lat,lng`, `LaunchMode.externalApplication` |
| WhatsApp | `url_launcher` para `https://wa.me/<telefone sem espaços/hífens>`, com `canLaunchUrl` antes — em `client_job_detail_screen.dart`, `client_job_confirmed_screen.dart`, `client_scheduled_job_detail_screen.dart`, `worker_my_job_detail_screen.dart`, `worker_help_requests_screen.dart`. Único canal de contacto da app |
| OCR (ML Kit) | `fleet_card_text_extractor.dart` | `google_mlkit_text_recognition`, local, a foto é apagada logo depois de extrair os 3 campos — nunca vai a Storage |
| QR | `qr_flutter` | cartão partilhável do worker (`worker_profile_screen.dart`) e estado ativo do cartão frota (`fleet_card_screen.dart`) |
| Partilhar | `share_plus` | partilhar o link do cartão do worker |
| Domínio e suporte | `core/config/app_links.dart` | `APP_PUBLIC_URL`, `SUPPORT_EMAIL` (por omissão `projardim26@gmail.com`), `TERMS_URL` e `PRIVACY_POLICY_URL` (por omissão os Google Docs publicados) por `--dart-define`, todos opcionais; sem domínio: na web o próprio site, nas apps `projardim.pt`. Usados no link `/w/:id`, no `User-Agent` do Nominatim, em "Contacto e suporte" e nos links legais (`core/widgets/app_legal_links.dart`: frase do registo, do login social e duas entradas na conta) |
| Fotos | `image_picker` (seleção) + `flutter_image_compress` (`job_repository.dart`: `minWidth/minHeight: 800`, `quality: 60`, JPEG) antes do upload para Storage |

---

## 13. Convenções e armadilhas conhecidas

- **Ficheiros `snake_case.dart`; classes `PascalCase`.**
- **Um widget grande deve ser partido em widgets pequenos e reutilizáveis.**
- **Estados de negócio são sempre enums** (secção 8), nunca strings soltas a
  circular pela app — só os `*_repository.dart` convertem de/para o `text` da BD.
- **Correr `flutter analyze` depois de cada alteração relevante.**
- **Regra T4** — ordem obrigatória numa ação com navegação: **navegar (go/pop) →
  aviso (`AppToast`, guardado antes de navegar) → `ref.invalidate(...)`**. Invalidar antes de navegar pode fazer um provider
  que o ecrã atual observa disparar um rebuild a meio da navegação/dispose — crash
  `'_dependents.isEmpty': is not true` já visto em produção (ver `decisions_log.md`,
  T4/2026-06-29). 6 anti-patterns de ordem errada ficaram documentados como "Low" porque
  nenhum ecrã atual observa o provider invalidado — tornam-se bugs reais só se isso
  mudar.
- **Identidade sempre por `auth.uid()`** — nenhuma RPC aceita `worker_id`/`client_id`
  vindo do cliente desde o hardening de 0032 (3 vulnerabilidades reais corrigidas:
  `accept_proposal`, `create_proposal`, `sync_worker_service_types` aceitavam um
  `p_worker_id` espofável). Qualquer RPC nova deve seguir o mesmo padrão.
- **`DROP FUNCTION` explícito ao mudar o shape de retorno** — `CREATE OR REPLACE`
  falha (ou, em alguns casos, fica num estado inconsistente) quando o `RETURNS TABLE`
  muda de forma. Padrão usado em 0034/0039 (`get_help_requests_in_radius`) e 0022/0021
  (`get_my_help_acceptances`): `DROP FUNCTION IF EXISTS nome(tipos exatos dos
  parâmetros antigos);` antes do `CREATE FUNCTION` novo.
- **`RETURNING` está sujeito à RLS de SELECT, não só à de INSERT** — um
  `.insert().select().single()` pode "funcionar" (o INSERT passa) e devolver 0 linhas
  se não houver policy SELECT que cubra a própria linha inserida. Causou um bug real
  (lobby vazio) documentado em `decisions_log.md`. Verificar sempre a policy SELECT
  correspondente ao escrever um repositório novo que lê de volta o que acabou de inserir.
- **"worker" no código, nunca "provider"** — evita colisão com Riverpod e com
  `package:provider`. Na BD a tabela é `worker_profiles`; na UI é sempre "jardineiro".
- **Contacto só por WhatsApp** — nunca chat/email dentro da app; ver secção 12.
- **Só tokens do design system** — `AppColors`/`AppSpacing`/`AppRadius`/`textTheme`,
  nunca `Color(0xFF...)` nem tamanhos soltos fora desses ficheiros (gaps conhecidos e já
  corrigidos documentados em `STATUS.md`).
- **Botão de voltar depois de notificação** (`core/router/app_back_navigation.dart`,
  2026-10-16): `context.go()` substitui a stack toda — depois, um `pop()` normal não
  tem nada para desfazer. `goBackOrToRoleHome(context)` (pop se `canPop()`, senão
  `go()` para `/worker/home` ou `/client/home` pelo prefixo da rota) é o mecanismo
  único, aplicado via `AppBackButton` (AppBar) e via `PopScope` dentro dos 3 builders
  de `app_page_transitions.dart` (gesto/botão do sistema, cobre todas as rotas de uma
  vez). Ao implementar isto: `GoRouterState.of(context)` dentro do callback do
  `PopScope` lança (o `context` do `pageBuilder` não é descendente da própria rota) —
  usar `state.matchedLocation` capturado no wrap; `context.canPop()` lido nesse mesmo
  `context` fica desatualizado logo após um `push()` — envolver com `Builder` para um
  `context` genuinamente descendente antes de ler `canPop()`.
- **`Container.alignment` com um único filho expande para o espaço disponível** em vez
  de se ajustar ao conteúdo (comportamento documentado do Flutter) — causou o badge de
  estado a ocupar a altura toda da `AppBar` mesmo dentro de um `Center` externo (ver
  `decisions_log.md` 2026-10-16, Ponto 1). Won't-fix genérico: ter cuidado sempre que um
  widget de conteúdo pequeno (badge, chip, etc.) usa `Container(alignment: ...)` dentro
  de um contexto que pode dar constraints LOOSE largas (AppBar actions, Wrap).
  Simetricamente, um `Row` com `mainAxisSize: MainAxisSize.min` só escolhe
  "tamanho do conteúdo" quando a constraint que recebe já é LOOSE — dentro de um
  `Expanded`, a constraint chega TIGHT e o `Row` não tem escolha; precisa de
  `mainAxisAlignment` para centrar o que sobra.
- **Serviços e categorias sempre de `serviceTypesProvider`** — nunca hardcoded na UI;
  o princípio central do projeto é que a BD não sabe que isto é jardinagem.
- **`doc.txt`** (raiz do workspace, fora de `servicesapp/`) — mockup/especificação
  original de referência para adaptar, não para copiar literalmente; não se apaga.

---

## 14. Testes

62 ficheiros e cerca de 560 testes em `test/` (contagem de `test(`/`testWidgets(` a 2026-10-27), todos sem rede nem Supabase:
- lógica: redirects do router (`route_guard_test.dart`, sobre `resolveRedirect` em
  `core/router/route_guard.dart`, para onde saiu a decisão de `RouterNotifier.redirect`),
  política de password, `friendlyError`, preços, datas, enums da BD, telefone/WhatsApp,
  `StorageUrls`, catálogo de serviços e `HelpAcceptance.fromJson`;
- widgets: shell adaptativo e bottom nav, largura de conteúdo, secção de categorias e
  cartões do lobby de ajudantes (`help_lobby_view_test.dart`);
- desde 2026-10-18: regras do pedido e do trabalho (cliente e jardineiro), início do
  trabalho, propostas por hora e valor total, pedido direto e pelo cartão, avisos de
  pedidos sem propostas, equipa e estimativas, destaques do jardineiro, planos e admin,
  notificações, `AppToast`, e a Agenda inteira (`agenda_*_test.dart`: sobreposições,
  Hoje, Semana, Mês, formulário, detalhe, "Ver o dia", avisos nos ecrãs existentes).
Ecrãs ligados ao Supabase não têm teste (precisavam de mocks dos repositórios); as vistas
puras (`*_view.dart`) e os presenters sim. `flutter analyze` mantém-se a **0 issues** (o CI
falha com qualquer aviso, também `info`).

Para correr: `flutter analyze` (raiz de `servicesapp/`), `flutter test`. **CI**:
`.github/workflows/ci.yml` corre os dois em cada PR e em cada push para `main` que mexa
em `servicesapp/` (falha também com avisos `info`, para manter o analyze a zero).
`.github/workflows/deploy-web.yml` publica a versão web no Netlify (ver `SETUP.md`).

---

## 15. TODOs e FIXMEs encontrados

Varrimento completo de `lib/` e `supabase/` por `TODO`/`FIXME`/`XXX` — poucos, todos
já com contexto registado:

- ~~Confirmação de email / deep link real~~ — resolvido a 2026-10-17 com confirmação por
  código (sem deep links); os TODOs e `email_confirmed_screen.dart` foram removidos.
- **Mapa estilizado revertido** (`client_create_job_schedule_screen.dart:437`) —
  `TODO(mapa-estilizado)`, decisão de reverter já tomada, comentário descreve o porquê.
- `supabase/migrations/archive/0001_baseline.sql:446` — `TODO: add SELECT policy for
  admin review UI`, num ficheiro **arquivado** (não aplicar); o baseline consolidado
  atual não repete este TODO.

(`worker_edit_profile_screen.dart:290` apareceu na busca por conter a palavra "TODOS"
em português — não é um marcador TODO.)

---

## 16. Discrepâncias encontradas (listadas para decisão; as resolvidas estão riscadas)

1. ~~`database_schema.md` descreve uma policy pública de `profiles` que já não existe.~~
   **Resolvido em 2026-10-17**: `database_schema.md` foi alinhado com a BD (policies de
   `profiles`, colunas das 0041 a 0046, crons, triggers, storage). Contexto original:
   Diz "SELECT público limitado a `full_name`/`avatar_url`" — essa era a policy
   `USING(true)` original, substituída em 0032 por 3 policies granulares (dono; worker↔
   cliente só com job confirmado/proposta aceite). **Confirmado em 2026-10-16 por dump
   real da BD viva**: as 5 policies de `profiles` na BD viva são exatamente as 3
   granulares + próprio-insere + próprio-atualiza, sem nenhuma policy pública.
   `database_schema.md` continua desatualizado e não foi corrigido (fora do âmbito
   desta verificação, que se focou em `ARCHITECTURE.md`/migrations).
2. ~~`create_user_profile` (RPC, `SECURITY DEFINER`) não tem nenhum caller em `lib/`.~~
   **Resolvido**: apagada na 0042 (S2 do review de segurança). Contexto original:
   A criação de perfil acontece via `AuthRepository.createProfile` →
   `_client.from('profiles').upsert(...)` direto. A função fica na BD sem uso — manter,
   remover ou documentar como legado é uma decisão a tomar.
3. **Seed de `service_types` não bate com `implementation_plan.md`.** O ficheiro
   `0001_consolidated_baseline.sql` semeia `('lawn_mowing','Corte de relva')`,
   `('pruning','Poda')`, `('garden_setup','Montagem de jardim')`; `implementation_plan.md`
   (Fase 5) diz "Corte de relva, Poda, Limpeza de jardim — confirmados via query live
   2026-06-25". **Ainda não resolvido em 2026-10-16**: o dump real obtido (`supabase db
   dump`, sem `--data-only`) só traz schema, não linhas de dados — não confirma qual das
   duas versões de "garden_setup" está semeada na BD viva. Precisa de um
   `supabase db dump --data-only` (ou query direta) para fechar.
4. ~~**`help_acceptances.message` (migration 0034) é escrito mas nunca lido.**~~
   Resolvido a 2026-10-17: a migration 0047 (aplicada) acrescenta `message` ao
   `RETURNS TABLE` de `get_candidates_for_help_request`; `HelpAcceptance.message` lê-a e o
   cartão do candidato no lobby (`worker_help_requests_lobby_view.dart`) mostra-a.
5. **`features/proposals/presentation/` está vazia.** Todos os ecrãs de proposta vivem
   em `features/jobs/presentation/` ou `features/worker/presentation/` — convenção real,
   nunca documentada antes deste ficheiro.
6. ~~Contagem de rotas em `STATUS.md` ("39 rotas ao todo") desatualizada.~~ **Resolvido a
   2026-10-27**: `STATUS.md` foi reescrito e já não conta rotas; a contagem certa (50) está
   na secção 5 deste ficheiro.
7. ~~Nenhum dos dois documentos de estado (`STATUS.md`, `supabase/migrations/README.md`)
   foi verificado contra a BD viva.~~ **Resolvido em 2026-10-16**: o utilizador extraiu
   um dump real da BD viva via `supabase db dump` (projeto `twpflvcoyeiysnychkom`, plano
   Free). As 37 funções, 14 tabelas, 3 views e 5 policies de `profiles` coincidem
   exatamente com `0001_consolidated_baseline.sql` + 0033–0040 — incluindo 0038/0039/0040,
   que estavam marcadas "não aplicada" e na verdade já estavam aplicadas. `STATUS.md` e
   `supabase/migrations/README.md` foram atualizados para refletir isto.
8. **Trigger `job_requests` tem nome diferente na BD viva vs. no ficheiro da migration.**
   `0001_consolidated_baseline.sql` define `trigger_notify_workers_new_job`; a BD viva
   (dump 2026-10-16) tem-no como `on_job_created` — mesma função (`notify_workers_new_job`),
   mesmo evento (`AFTER INSERT`). Provavelmente renomeado manualmente no Supabase Studio em
   algum momento, sem passar por migration. Sem impacto funcional, só cosmético/histórico.
9. **Código de compatibilidade com migrations por aplicar ainda existe** (2026-10-27).
   Como todas as migrations estão aplicadas, os caminhos "antes da 00xx" já não correm:
   `PGRST202` em `help_request_repository.dart` (0048) e `helper_job_state.dart`,
   `WorkerPlan.unavailable` (0060), leitura de `cleared_at` no Dart em vez de na query
   (0065), comentários em `job_repository.dart` (0059), `proposal_repository.dart` (0058),
   `worker_profile_model.dart` (0051), `worker_jobs_screen.dart` (0064). Não fazem mal, mas
   podem ser removidos numa limpeza (registado em `improvements.md`). O
   `isMissingRpcError` de `error_utils.dart` fica: protege qualquer migration futura.
