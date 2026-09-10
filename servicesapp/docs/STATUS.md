# LocalServices (ProJardim) — Project Status

> Snapshot honesto do estado do projeto. Atualizado em 2026-09-08.
> Sem spin — o que funciona, o que não funciona, o que é placeholder, o que bloqueia utilizadores reais.
> Esta atualização é o resultado de uma auditoria completa (código + RLS + navegação + cobertura do redesign) pedida em 2026-09-08. Auditoria só de leitura — nenhum ficheiro de código foi alterado; o registo detalhado fica no relatório dessa conversa, não replicado aqui linha a linha.

---

## O que funciona end-to-end hoje

Tudo o que já estava descrito na versão anterior deste ficheiro (2026-07-09) continua válido:
autenticação, perfil de worker, criação de pedido, descoberta de jobs, propostas, ajudantes,
ciclo de vida do job (incl. remarcação — **RC/"Remarcação" está implementada de ponta a ponta**,
RPCs `propose_reschedule`/`accept_reschedule`/`reject_reschedule` + UI em ambos os lados,
`RescheduleDialog` no cliente), avaliações, notificações (19 tipos com deep-link), RLS em
todas as tabelas.

**Desde 2026-07-09, adicionado:**

- **Rebrand completo** para "ProJardim" (nome ainda placeholder de produto, mas já não
  "LocalServices" na UI).
- **Redesign visual** com sistema de design próprio (`AppColors`, `AppTypography`, `AppRadius`,
  `AppSpacing`, `AppStatusColor`/`AppStatusBadge`, motion system em `app_motion.dart`) aplicado
  a auth, onboarding, dashboards, contas e vários sub-fluxos — cobertura detalhada na secção
  seguinte, porque é desigual.
- **Ecrãs de conta** (`WorkerAccountScreen`/`ClientAccountScreen`) — resumo, cartão partilhável
  (QR via `qr_flutter`), menu de definições, "Contacto & suporte", "Sobre a app".
- **Cartão público do worker** (`/w/:workerId`, migration 0033, view `worker_public_card`) —
  perfil mínimo pensado para acesso sem sessão. **Nota:** a rota existe e funciona se
  visitada, mas nada na app gera um link/QR que resolva para ela de facto — ver "Rotas órfãs".
- **Ecrã dedicado de candidatura a ajudante** (`apply_as_helper_screen.dart`) — mostra
  pagamento/hora e data/hora confirmada ANTES de candidatar (migration 0034).
- **RPC única de "Os meus trabalhos"** (`get_worker_job_board`, migration 0035) — substitui a
  fusão client-side de propostas + candidaturas por paginação e ordenação server-side.
- **Recuperação de password** — fluxo completo com bypass de dev (`kDebugMode`), sem SMTP real.
- **Confirmação de email** — UI pronta, mas a funcionalidade **está desativada no dashboard
  Supabase** (decisão deliberada, ver `decisions_log.md` 2026-06-05); migration 0036 prepara o
  terreno (cascade `profiles→auth.users`, backfill de `email_confirmed_at`) para quando for
  ligada, mas não a liga.
- **Cartão Frota (combustível)** — dados 100% fictícios/demo, sem parceria real. OCR local
  (`google_mlkit_text_recognition`), a foto nunca é guardada nem enviada. Ativação de estado
  sempre manual via SQL Editor (migration 0037). Ver `improvements.md`.
- **Média de estrelas no perfil do worker** — item que `improvements.md` ainda lista como
  "falta calcular e mostrar" (Fase 11 deferred) **já está implementado**: `ratingSummaryProvider`
  alimenta tanto o ecrã de conta do próprio worker como o cartão público (`worker_public_card`
  expõe `avg_rating`/`rating_count`). Doc desatualizado, não o código — corrigir em `improvements.md`.

---

## Cobertura do redesign visual — auditoria 2026-09-08

39 rotas ao todo. O redesign (tokens oficiais + motion system) cobre a maior parte dos ecrãs de
maior tráfego, mas **não é uniforme**. Critério usado: um ecrã conta como "reskinned" só se usa
`AppColors`/`AppTypography`/`AppRadius`/`AppSpacing` de forma consistente (não apenas
`AppStatusBadge` herdado da unificação de estados de 2026-07-12).

**Totalmente reskinned (tokens +, na maioria, motion system):** landing, login, signup,
choose-role, onboarding (ver nota sobre `fontSize: 23` abaixo), verify-email,
email-confirmed, todo o fluxo de recuperação de password (5 ecrãs), worker/client dashboards
e contas (`worker_account_view`/`client_account_view`), `worker_jobs_view`,
`worker_available_jobs_view`, `worker_my_job_detail_view`, `client_home_view`,
apply-as-helper, notifications, worker_public_profile, client_create_job (3 passos),
client_job_detail/confirmed/rate-worker, fleet card (scan/confirm/status).

**NUNCA redesenhados — ainda Material 3 puro ou vintage Fase 8/9 (funcionalmente corretos,
visualmente destoantes):**

| Ecrã | Rota | Nota |
|---|---|---|
| `client_edit_profile_screen.dart` | `/client/profile/edit` | Ficheiro **novo** (extraído do antigo `ClientProfileScreen`, doc comment próprio confirma), mas escrito em Material puro — sem `AppColors`/`AppRadius`/`PrimaryActionButton`/`AppTextField`. |
| `worker_edit_profile_screen.dart` | `/worker/profile/edit` | Mesmo caso — nenhum import de tokens do design system. |
| `client_jobs_screen.dart` | `/client/jobs` | Fase 8, só tocado pela unificação de `AppStatusBadge` (2026-07-12). `BorderRadius.circular(12)` hardcoded em vez de `AppRadius.input`. |
| `worker_job_detail_screen.dart` (+ `worker_job_detail_view.dart`) | `/worker/job/:id` | Idem — só passou pela unificação de status badges. |
| `worker_submit_proposal_screen.dart` (+ view) | `/worker/job/:id/propose` | Criado antes do motion system (commit `88286ae`), nunca revisitado. |
| `worker_help_requests_lobby_screen.dart` | `/worker/job/:id/help-requests` | Fase 9 vintage. `TextStyle(fontSize: 16, fontWeight: bold)` hardcoded (não via `Theme.of(context).textTheme`). |
| `worker_help_requests_screen.dart` | `/worker/help-requests` | Ganhou a funcionalidade das tabs de ajudante (2026-09-05) mas não um reskin visual. |

**Parcialmente reskinned (mistura de código novo e antigo no mesmo ficheiro):**

- `client_job_detail_screen.dart` — ficheiro grande (1750+ linhas), a maior parte usa motion
  system e tokens (integrado em `ccd293e`), mas retém `BorderRadius.circular(12)` hardcoded
  (linha 984) e um `.copyWith(fontWeight: FontWeight.w700)` cru (linha 1755) — resíduo de
  secções mais antigas que sobreviveram à integração.
- `onboarding_screen.dart` — ✅ RESOLVIDO 2026-09-09: as 3 cores `Color(0xFF...)` (`0xFF888878`,
  `0xFF111411`, `0xFF6F746D`) foram trocadas por `AppColors.textSecondary`/`textPrimary`. Fica
  só o `fontSize: 23` literal por cima de `headlineSmall` — deixado de propósito, é uma decisão
  de design já tomada e documentada no próprio código, não uma inconsistência.

**Não é um problema (decorativo, não precisa de token):** raios de 2/4/6/8px em indicadores de
página, splash de `InkWell`, badge circular proporcional (`app_brand_badge.dart`), e o timeline
de estados (`status_timeline.dart`) — este último já está documentado em `improvements.md` como
"será refeito do zero no redesign visual, não vale a pena polir agora".

**Sistema de shimmer (`AppSkeletonShimmer`) usado de forma inconsistente:** só 4 ecrãs o adotam
(`worker_dashboard`, `worker_jobs_view`, `worker_available_jobs_view`, `apply_as_helper`) — outros
ecrãs de lista já reskinned (`client_home_view`, `worker_my_job_detail_view`) continuam a usar
`CircularProgressIndicator` simples para o estado de loading da lista. Não é um bug, é uma
adoção parcial do componente.

---

## Gaps conhecidos (sem spin)

### ✅ RESOLVIDO 2026-09-09 — estado de aplicação das migrations 0032–0037

Confirmado pelo utilizador: as migrations 0032 (via `archive/0032_audit_fixes.sql`) a 0037
foram todas aplicadas manualmente via SQL Editor. Cabeçalhos atualizados em cada ficheiro,
em `0001_consolidated_baseline.sql` e em `supabase/migrations/README.md` (secção "Live DB
delta"). Não foi possível confirmar de forma independente por leitura direta da BD viva nesta
sessão (sem acesso a Supabase — nem MCP, nem CLI, nem credenciais no ambiente) — esta
confirmação assenta na palavra do utilizador, não numa query executada. `accept_proposal`
não foi lido diretamente; se surgir dúvida futura, confirmar via SQL Editor
(`SELECT prosrc FROM pg_proc WHERE proname = 'accept_proposal'`).

### 🟠 ALTO — antes de mostrar a alguém fora da equipa

(Os 4 itens já conhecidos continuam válidos e estão detalhados em `improvements.md`: push
notifications/FCM, SA3 Storage path, SA2 ratings participação, contacto do worker principal —
nenhum mudou de estado nesta auditoria.)

**Rotas órfãs — declaradas, sem nenhum caminho de navegação real**
- `/client/messages` e `/worker/messages` — só `_PlaceholderScreen('Mensagens')`. Confirmado
  por leitura direta de `client_shell.dart` e `worker_shell.dart`: a bottom nav tem só 4 itens
  em ambos, "Mensagens" não é um deles. `worker_shell.dart` documenta isto explicitamente no
  seu próprio comentário ("removida da bottom nav, mas a rota continua a existir"). Nenhum
  botão em lado nenhum da app aponta para estas duas rotas.
- `/w/:workerId` (cartão público do worker) — a rota e o ecrã funcionam se visitados
  diretamente, mas **nada na app gera internamente um `context.push`/`go` para lá**.
  `AppLinks.publicWorkerProfileUrl()` só produz uma string de texto (`https://projardim.pt/w/...`)
  usada para mostrar num QR/partilhar — como o domínio é placeholder (ver abaixo) e não há
  universal links/deep link handler configurado, esta rota é hoje inalcançável tanto de dentro
  como de fora da app. Não é um bug de navegação — é infraestrutura de partilha que ainda não
  tem para onde apontar.

### 🟡 MÉDIO — gaps de UX/segurança antes do lançamento mais amplo

(Os itens já existentes em `improvements.md` — `JobStatus` labels, CHECKs em falta, validação
de telefone, etc. — continuam válidos, sem mudança.)

- **Dois ecrãs de edição de perfil sem reskin** — `client_edit_profile_screen.dart` e
  `worker_edit_profile_screen.dart` (ver tabela acima). Funcionalmente corretos (Supabase real,
  upload de avatar real), visualmente Material 3 default — destoam do resto da app já
  reskinned. Provavelmente o próximo alvo natural do redesign.
- **`friendlyError()` vs `AuthController._mapError()` continuam por consolidar** — confirmado
  ainda coexistem (`_mapError` privado, só 4 call sites dentro de `auth_controller.dart`;
  `friendlyError` usado em 26 outros ficheiros). Sem sinal de urgência, mas é duplicação real.
- **Notificações: 3 de 19 tipos usam `context.push` em vez de `context.go`**
  (`helpRequestApproved`, `helpRequestReopened`, `helpWithdrew`) — os outros 16 usam `go`. Isto
  é uma decisão deliberada e documentada (estes 3 casos preservam o botão de recuar de
  propósito), não um esquecimento — mas vale a pena ter presente que a regra "notificações
  usam go" tem exceções.
- **Duas funções de rating sheet com nomes quase idênticos** — `rating_sheet.dart`
  (`showRatingSheet`, singular — submeter uma avaliação nova) e `ratings_sheet.dart`
  (`showRatingsSheet`, plural — ver avaliações já recebidas). Ambos ativamente usados, nenhum
  é código morto, mas o nome quase igual é uma armadilha fácil ao navegar o código.

### 🔵 BAIXO — limpeza conhecida

(Os itens já existentes continuam válidos.) Achados desta auditoria, ambos já corrigidos em
2026-09-09:
- ✅ `_PlaceholderScreen` duplicado em `client_shell.dart` — removido, só sobra a versão
  usada em `app_router.dart`.
- ✅ `BorderRadius.circular(12)` hardcoded em `onboarding_screen.dart`, `client_jobs_screen.dart`
  e `client_job_detail_screen.dart` — trocado por `AppRadius.input` (mesmo valor, 12.0, zero
  mudança visível).

---

## Postura de segurança

### RLS — tabelas/views criadas desde 2026-07-09 (migrations 0033–0037)

| Objeto | Owner-only onde aplicável? | Self-approve possível? | Nota |
|---|---|---|---|
| `worker_public_card` (view, 0033) | N/A — pensada para ser pública (`anon`+`authenticated`) | N/A | Expõe só nome/avatar/bio/zona/serviços/rating agregado. Sem telefone, sem coordenadas, sem raio, sem ferramentas — confirmado por leitura da definição. |
| `get_help_requests_in_radius` (0034) | Sim — filtra por `auth.uid()`, sem parâmetro de identidade vindo do cliente | N/A | `jp.worker_id <> auth.uid()` e `NOT EXISTS (... ha.worker_id = auth.uid())`. |
| `help_acceptances.message` (0034) | Coberto pelas policies row-level já existentes | N/A | Coluna nova, sem policy nova necessária (raciocínio documentado na própria migration). |
| `get_worker_job_board` (0035) | Sim — **sem parâmetro `p_worker_id`**, só `auth.uid()` | N/A | O cabeçalho da migration cita explicitamente a 0032 como razão de desenho. |
| `worker_fleet_cards` (0037) | Sim — SELECT/INSERT só do próprio (`worker_id = auth.uid()`) | **Não** — sem policy de UPDATE/DELETE para `authenticated`; só service role muda `status` | Mesmo padrão de moderação manual que `job_reports`. |

**Conclusão da auditoria de RLS:** nenhuma migration desde a 0028 reintroduz a classe de
vulnerabilidade corrigida em 0032 (parâmetro de identidade vindo do cliente em vez de
`auth.uid()`). A 0032 está confirmada como aplicada à BD viva desde 2026-09-09 (ver secção
"Gaps conhecidos" acima) — o código está certo e a correção já chegou à BD viva.

### Riscos aceites (sem mudança desde 2026-07-09)

SA1, SA2, SA3 — ver tabela completa em `improvements.md`. Nenhum foi corrigido nem piorado
nesta auditoria.

---

## O que é preciso antes do primeiro utilizador real fora da equipa

Sem mudanças na lista de bloqueadores desde 2026-07-09 (FCM push continua o nº 1). O item
"confirmar se 0032–0037 estão aplicadas" foi resolvido em 2026-09-09 (ver "Gaps conhecidos").

Ver `improvements.md` para a lista completa (FCM, validação de telefone, verificação de
identidade, nome de marca definitivo, testes com utilizadores externos).
