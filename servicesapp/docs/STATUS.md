# LocalServices (ProJardim) — Project Status

> Snapshot honesto do estado do projeto. Atualizado em 2026-09-08 (revisto a 2026-10-18, ver primeira entrada abaixo).
> Sem spin — o que funciona, o que não funciona, o que é placeholder, o que bloqueia utilizadores reais.
> Esta atualização é o resultado de uma auditoria completa (código + RLS + navegação + cobertura do redesign) pedida em 2026-09-08. Auditoria só de leitura — nenhum ficheiro de código foi alterado; o registo detalhado fica no relatório dessa conversa, não replicado aqui linha a linha.

---

## O que funciona end-to-end hoje

**2026-10-23, Notificações que ajudam a fechar trabalhos (migration 0062 por aplicar; 0061 urgente):**
a 0061 corrige um erro vivo desde a 0057: os jardineiros deixaram de ver os pedidos
normais em "Pedidos disponíveis". Com a 0062, um pedido sem propostas tem três avisos aos
jardineiros: o de pedido novo, um lembrete às 6h (um por jardineiro a cada 20h, vários
pedidos juntos) e, às 24h, o pedido passa a aparecer 10 km mais longe e quem fica nesse
anel é avisado. O cliente recebe "Ainda sem propostas" e o pedido mostra um cartão com
"Alargar a data", "Ajustar a descrição" e "Mostrar a jardineiros mais longe" (até 30 km).
Avisos só das 8h às 21h. Dicas da época por push (outubro e fevereiro, editáveis em
`seasonal_campaigns`), com interruptor em Definições do cliente. Os textos das
notificações passam a ter nomes, valores e distância, sempre por tu. Antes da 0062
aplicada a app funciona como antes (o cartão e o interruptor não aparecem).

**2026-10-22, painel de administração /admin e planos (migration 0060 por aplicar):**
`/admin` no mesmo site da app, só para a conta que estiver em `admin_users`, com palavra-passe
e código de uma app autenticadora (TOTP do Supabase). Fase 1: visão geral (utilizadores,
pedidos do período, % com proposta em 24h, tempo até à 1.ª proposta, avaliações, planos e
alertas), lista de jardineiros com pesquisa e filtro por plano, ficha com números e trabalhos
por mês, e "Mudar plano" (Grátis, Pro, Pro+ com início, fim, documentos verificados e notas).
O Grátis passa a ter um limite de 5 trabalhos aceites por mês (a BD recusa propostas novas
depois disso); a conta do jardineiro mostra o plano e o uso em "Plano". Pagamento e contrato
são fora da app: a app não mostra preços. Falta: mapa, pedidos, moderação, funil e exportar
(fases 2 e 3), e o selo Pro nas propostas e no cartão público. Passos em `SETUP.md` 0.13.

**2026-10-22, Pedido direto pelo cartão do jardineiro (design A7, migration 0059 por aplicar):**
o cartão público `/w/:id` tem "Pedir orçamento a {nome}". Sem sessão, o registo (ou
login) guarda o jardineiro, cria a conta já como cliente e volta ao pedido. O passo 1 só
mostra os serviços desse jardineiro, a faixa "Pedido para {nome}" fica nos 4 passos e o
passo 4 tem o interruptor "Se não puder, mostrar a outros jardineiros". Desligado, uma
recusa ou o fim do prazo deixam o pedido parado até o cliente escolher "Mostrar a todos"
ou "Cancelar pedido". O jardineiro vê o pedido fixo no topo, mesmo fora da área e com
filtros. Cada abertura do cartão fica registada (QR, link ou app) e os clientes novos
ficam ligados ao jardineiro que os trouxe (`worker_card_funnel`, só no SQL Editor). O
selo Pro continua sem dados; as flags do cartão vêm do servidor e hoje estão todas
ligadas. Antes da 0059 aplicada, pedir pelo cartão dá erro; o resto funciona como antes.

**2026-10-22, Propostas com valor total ou por hora (design A6, migration 0058 por aplicar):**
o jardineiro escolhe, em cada proposta, entre preço por hora e valor total, marca o que
inclui (material, remoção de resíduos, deslocação, máquinas), indica a duração em horas
ou dias e a validade (7, 15 ou 30 dias). O cliente vê os dois formatos lado a lado com a
caixa "Total" no mesmo sítio, sem ordenar pelo preço, e abre cada proposta num detalhe
com "Aceitar por X". Propostas expiradas ficam no fim e o servidor recusa aceitá-las.
Trabalhos em vários dias têm "Dia 1 de 3", "Terminar o dia" e "Começar o dia", e o
valor fechado não muda com as horas. "Ver o local primeiro" (visita) fica para a fase 2.
Antes da 0058 aplicada, enviar proposta dá erro; o resto funciona como antes, sem
validade nem dias de trabalho.

**2026-10-22, Pedir de novo ao mesmo jardineiro (design A5, migration 0057 aplicada a 2026-10-22):**
no trabalho concluído o cliente tem "Pedir de novo a {nome}" (cartão só sem avaliação ou
com 4 ou 5 estrelas); o pedido vem preenchido e só pede a data. Durante 24h só esse
jardineiro o vê ("Pedido só para ti · faltam X h", cartão com o histórico, "Não posso
desta vez"); depois, se recusar, não responder ou o cliente tocar em "Mostrar já a todos",
abre a todos na zona. Início do cliente com "Os teus jardineiros". Antes da 0057 aplicada
estas entradas dão erro ou não aparecem. O "Não voltar a mostrar" da explicação fica só
no aparelho.

**2026-10-21, Termos e Política de Privacidade:** publicados no Google Docs e ligados na
app: "Termos" e "Política de Privacidade" têm toque na caixa do registo e na frase do login
social, e a conta dos dois papéis tem as entradas "Termos de utilização" e "Política de
Privacidade" (abrem no browser). Email de suporte por omissão: `projardim26@gmail.com`.
Os textos são um rascunho sem dados da empresa (falta revisão jurídica). Sem migration.

**2026-10-18, login com Google e Facebook:** botões "Continuar com Google/Facebook" no
login e no registo, pelo OAuth do Supabase (`signInWithOAuth`), na web e nas apps (deep
link `pt.projardim.app://login-callback`). Conta nova escolhe o papel e escreve só o
telemóvel; o nome vem da conta e a foto é copiada para o Storage (`avatars/<id>.jpg`).
Falta a configuração no Google Cloud, na Meta e no Supabase (`SETUP.md` passo 7); até lá
os botões dão erro. Sem migration. Desde 21/10 o botão do Facebook está escondido até haver
`--dart-define=FACEBOOK_LOGIN_ENABLED=true` (a app da Meta fica em Development enquanto
não houver verificação de negócio).

**2026-10-18, limpeza de docs e design system:** os itens SA1, SA2, SA3, M4 (CHECKs),
contacto do jardineiro responsável para ajudantes, P-8-8, P1/A1 (labels de `JobStatus`),
reskin de `client_jobs_screen` e shimmer nas listas estavam marcados como abertos mas já
estão resolvidos no código e nas migrations (ver `improvements.md`, secção "Revisão de
2026-10-18"). Erros, estrelas e ícones de notificação passaram a usar os tokens
(`AppStatusColor`, `AppColors.logoAccent`) em vez de `Colors.red`/`amber`/`green`. Todos os
botões só com ícone têm descrição para leitores de ecrã. O ficheiro de arquitetura passou a
`docs/ARCHITECTURE.md` (antes `architecture.md`, que não batia com o CLAUDE.md em sistemas
que distinguem maiúsculas).

**2026-10-17, limpeza sem decisões:** todas as migrations até à 0046 aplicadas
(confirmado pelo Henrique). CI no GitHub Actions (`ci.yml`: `flutter analyze` + `flutter
test` em cada PR); `flutter analyze` a 0 issues. Domínio público e email de suporte por
`--dart-define` (`APP_PUBLIC_URL`, `SUPPORT_EMAIL`). A app só mostra fotos de perfil que
venham do Storage do próprio projeto (fecha o ponto do `avatar_url` do review de 16/10
sem migration). Toda a configuração que só o Henrique pode fazer está em `docs/SETUP.md`.
Telefone validado e WhatsApp sempre com indicativo. Confirmação de email por código de 6
dígitos pronta no código; liga-se no Supabase depois do SMTP (`SETUP.md` 3.3).

**2026-10-17, versão web:** a app compila e corre no browser (Flutter web) e instala-se no
iPhone como PWA. Na web não há OCR do cartão frota (dados à mão) nem push FCM; o resto
funciona igual. Layout com largura máxima centrada em tablet/PC e navegação lateral a
partir de 840 de largura. Falta alojar e configurar Site URL no Supabase (ver `docs/web.md`).

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
  (QR via `qr_flutter`), menu de definições, "Contacto e suporte", "Sobre a app".
- **Cartão público do worker** (`/w/:workerId`, migration 0033, view `worker_public_card`) —
  perfil mínimo pensado para acesso sem sessão. **Nota:** a rota existe e funciona se
  visitada, mas nada na app gera um link/QR que resolva para ela de facto — ver "Rotas órfãs".
- **Iniciar trabalho, temporizador e 48h** (2026-10-19, migration 0052 por aplicar), a
  seguir o design de 19/10 (ecrãs 6, 6b, 7, 7b). O jardineiro inicia a partir de 1h antes
  da hora, com fotos de antes opcionais; o ecrã mostra o tempo em curso e "Reportar
  problema"; concluir pede fotos de depois e mostra o tempo registado. O cliente vê "Em
  curso", o tempo e as fotos. Confirmação automática em 48h com lembrete às 24h. Antes da
  0052 aplicada, "Iniciar trabalho" dá erro (a RPC não existe). A lista "Os meus
  trabalhos" mostra "Em curso" depois da 0053 (`get_worker_job_board` passa a devolver
  `started_at`).
- **Destaques e redes sociais do jardineiro** (2026-10-18, migration 0051 por aplicar) —
  em Editar perfil > "Destaques e redes sociais": até 5 destaques curtos e links para
  Instagram, Facebook, site e um outro (TikTok, YouTube, Google Maps), validados e sempre
  `https://`. O cliente vê-os, com a apresentação, ao tocar no jardineiro numa proposta
  (agora abre sempre, mesmo sem avaliações) e no cartão `/w/:workerId`. Sem selo de
  verificação: diz "Informação partilhada pelo jardineiro". Antes da 0051 a secção diz
  "Em breve" e o resto do perfil grava como antes.
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
- **Média de estrelas no perfil do worker** — já está implementado: `ratingSummaryProvider`
  alimenta tanto o ecrã de conta do próprio worker como o cartão público (`worker_public_card`
  expõe `avg_rating`/`rating_count`). `improvements.md` corrigido em 2026-09-09 para refletir
  isto (já lá dizia "falta calcular e mostrar" por engano).

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

**Adicionados a "totalmente reskinned" desde 2026-09-09:**
- `worker_job_detail_screen.dart` (+ `worker_job_detail_view.dart`) e `worker_submit_proposal_screen.dart`
  (+ `worker_submit_proposal_view.dart`) — **correção de auditoria, não trabalho novo**: já
  estavam corretamente reskinned (`AppColors`/`AppRadius`/`AppSpacing`/`PrimaryActionButton`)
  desde antes de 2026-09-08. O grep original desta auditoria usava um `glob` que excluía
  `presentation/widgets/`, onde os ficheiros `_view.dart` reais vivem — por isso apareciam
  como "nunca redesenhados" por engano. Confirmado por leitura direta em 2026-09-09.
- `client_edit_profile_screen.dart` (`/client/profile/edit`) e `worker_edit_profile_screen.dart`
  (`/worker/profile/edit`) — reskin real feito em sessões dedicadas (2026-09-09/10): split
  screen+`widgets/*_view.dart`, `AppTextField`/`PrimaryActionButton`/`AppSuccessFeedback`. O de
  worker ficou reorganizado em 3 secções navegadas dentro do próprio ecrã (overview, localização
  base, serviços e ferramentas), slider de raio contínuo preservado (1–50 km, sem chips).
- `worker_help_requests_lobby_screen.dart` (`/worker/job/:id/help-requests`) — reskin real
  (2026-09-15): avatares por `AppStatusColor` via `HelpAcceptanceStatus.presentation` (já estava
  correto antes, preservado), bottom sheet de aceitação com taxa sugerida editável + estimativa
  de duração/total quando a proposta tem horas estimadas.
- `worker_help_requests_screen.dart` (`/worker/help-requests`) — os 4 cards internos
  (`_HelpRequestCard`/`_PendingCard`/`_AcceptedCard`/`_HistoryCard`) já estavam reskinned antes
  de 2026-09-08 (a nota anterior estava errada); a "casca" (AppBar/TabBar → header + pills,
  loading → `AppSkeletonShimmer`, vazios reskinned, `AppFadeThroughSwitcher` na troca de tabs)
  foi reskinned em 2026-09-16, completando o ecrã.

**✅ RESOLVIDO (confirmado a 2026-10-18):** `client_jobs_screen.dart` já é um wrapper fino
sobre `widgets/client_jobs_view.dart`, com tokens e shimmer. A tabela abaixo fica como
histórico.

~~**NUNCA redesenhado — ainda Material 3 puro, vintage Fase 8 (funcionalmente correto,
visualmente destoante):**~~

| Ecrã | Rota | Nota |
|---|---|---|
| `client_jobs_screen.dart` | `/client/jobs` | Fase 8, só tocado pela unificação de `AppStatusBadge` (2026-07-12) e por uma correção pontual de `BorderRadius.circular(12)` → `AppRadius.input` (2026-09-09, mesmo valor, sem mudança visual). `Scaffold`/`AppBar`/`TabBar`/`Card` continuam Material puro — sem `AppColors`/`AppSpacing`/`PrimaryActionButton`/motion. **Nota 2026-09-16:** foi mencionado como já integrado junto com outros 4 ecrãs reskinned nesta mesma ronda — confirmado por leitura direta que isso está errado, este ecrã não fez parte de nenhuma sessão de reskin; continua exatamente como estava. |

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
página, splash de `InkWell`, e badge circular proporcional (`app_brand_badge.dart`).

**✅ RESOLVIDO 2026-10-15 — timeline de estados deixou de ser "provisória".** A nota antiga
dizia que `status_timeline.dart` "será refeito do zero no redesign visual" — desde 2026-10-15
é o componente final: `StatusTimelineHorizontal` (único, a vertical foi removida) está no topo
de todos os ecrãs de detalhe de job, com zona de detalhe para subtitle/note e largura adaptativa
para não dar overflow. Ver `decisions_log.md` 2026-10-15.

**✅ RESOLVIDO (confirmado a 2026-10-18):** o shimmer é usado em todos os ecrãs de lista e de
detalhe (`AppSkeletonShimmer`/`AppScreenLoadingSkeleton`); os spinners que restam estão
dentro de botões, no mapa e no visualizador de fotos. Nota antiga:
**Sistema de shimmer (`AppSkeletonShimmer`) usado de forma inconsistente:** só 4 ecrãs o adotam
(`worker_dashboard`, `worker_jobs_view`, `worker_available_jobs_view`, `apply_as_helper`) — outros
ecrãs de lista já reskinned (`client_home_view`, `worker_my_job_detail_view`) continuam a usar
`CircularProgressIndicator` simples para o estado de loading da lista. Não é um bug, é uma
adoção parcial do componente.

---

## Gaps conhecidos (sem spin)

### Agenda do jardineiro: em construção (2026-10-26)

Feito: migration 0064 (criada, não aplicada), `AgendaRepository`, `agendaRangeProvider`,
deteção de sobreposições com testes, os componentes da folha de design (A1 a A9) e as
vistas **Hoje** (H1 a H7), **Semana** (S1 a S3) e **Mês** (M1 a M3). O ecrã Trabalhos passou a ter as tabs Agenda · Propostas ·
Histórico e abre na Agenda; a antiga tab "Agendados" deixou de existir (os trabalhos
marcados estão na Agenda, no dia deles).

**Sem a 0064 aplicada a tab Agenda mostra o erro "Não foi possível carregar a agenda".**
Aplicar a 0064 antes de publicar.

Também feito: o formulário "Adicionar à agenda" / "Editar" (F1 a F8), ligado ao dia
livre, à semana livre, ao "+" das linhas "Livre", ao "Adicionar neste dia" do Mês, ao
"Mudar datas" e ao "+" central.

Também feito: o detalhe de um trabalho de fora da app ou de uma indisponibilidade (D1 a
D6), ao tocar no cartão: marcar como feito (com "Desfazer"), cancelar (fica na agenda
riscado e pode ser reposto), apagar, editar, WhatsApp, mapa e "Ver o dia". Isto mudou a
0064 (ainda não aplicada): estado por dia nas exceções e hora do feito.

Também feito: a folha "Ver o dia" (V1 a V3), aberta a partir do formulário. Mostra o
dia com o que se está a marcar a tracejado, a frase "Choca 1 hora com..." ou "Cabe...",
o tempo livre e as setas para outros dias. É só para ver e não mexe no formulário. Já
aceita a etiqueta "A tua proposta" para o fluxo de enviar proposta (Prompt 10).

Também feito: a tab Propostas (R1 a R3). Cada proposta mostra o dia e a hora propostos
(lidos da Agenda dos próximos 62 dias). As que chocam com a Agenda sobem para o topo,
com contorno âmbar e a nota "Coincide com ...", que abre "Ver o dia". "Retirar proposta"
pede confirmação e não tem "Desfazer". A ordem é feita na app sobre as páginas já lidas.

Falta: a primeira abertura e os avisos nos fluxos existentes
(enviar proposta, detalhe do pedido, remarcar). Um trabalho feito à espera da
confirmação do cliente só se vê no dia dele (antes estava em "Agendados").

### ✅ RESOLVIDO 2026-10-16 — verificação independente contra dump real da BD viva

O utilizador extraiu um dump real da BD viva (`supabase db dump`, projeto
`twpflvcoyeiysnychkom`, plano Free). Confirmado por leitura direta do dump, não pela palavra
do utilizador: as 37 funções, 14 tabelas e 3 views da BD viva coincidem exatamente com
`0001_consolidated_baseline.sql` + migrations 0033–0040 — sem nenhuma em falta nem extra.
As migrations 0038, 0039 e 0040 estavam marcadas como "NÃO aplicada" e na verdade já estavam
aplicadas; `ARCHITECTURE.md` e `supabase/migrations/README.md` foram corrigidos. Único drift
encontrado: o trigger de `job_requests` chama-se `on_job_created` na BD viva, não
`trigger_notify_workers_new_job` como no ficheiro da migration (mesma função, sem impacto
funcional — ver `ARCHITECTURE.md` secção 16, ponto 8). Dump é só schema (sem `--data-only`),
por isso a discrepância do seed de `service_types` (ponto 3 da secção 16) continua sem
confirmação.

### ✅ RESOLVIDO 2026-09-09 — estado de aplicação das migrations 0032–0037

Confirmado pelo utilizador: as migrations 0032 (via `archive/0032_audit_fixes.sql`) a 0037
foram todas aplicadas manualmente via SQL Editor. Cabeçalhos atualizados em cada ficheiro,
em `0001_consolidated_baseline.sql` e em `supabase/migrations/README.md` (secção "Live DB
delta"). Confirmado de forma independente em 2026-10-16 (ver entrada acima) — nesta sessão de
2026-09-09 a confirmação assentava só na palavra do utilizador, sem query executada.

### 🟠 ALTO — antes de mostrar a alguém fora da equipa

**Atualizado 2026-10-18:** dos 4 itens antigos só falta configurar o push (FCM): o código
está na app e a configuração está no `SETUP.md`. SA3 (path do upload) já estava fechado na
baseline 0001 (policies de INSERT por `auth.uid()` em `avatars` e `job-photos`), SA2
(avaliações) foi fechado pela 0042 e o contacto do jardineiro responsável chega aos
ajudantes desde a 0048/0049 (WhatsApp no ecrã do ajudante).

**✅ RESOLVIDO (código) 2026-10-15 — hardening de segurança de 2026-09-09 (migration 0032)
tinha partido silenciosamente 4 pontos de nome/avatar da contraparte.** A policy `USING(true)`
de `profiles` foi corretamente substituída por 3 policies granulares, mas 4 embedded joins do
PostgREST fora dessas relações (`client_proposals_screen.dart` com propostas `pending`,
`WorkerJobDetailScreen` numa oportunidade `open`, o lobby de candidatos a ajudante,
`showRatingsSheet`) passaram a devolver sempre `null` sem erro — ninguém reparou até esta
auditoria. Corrigido com 4 RPCs `SECURITY DEFINER` novas (migration `0040`). Cada uma a expor
só nome+avatar com a mesma condição de autorização que já existia. Detalhe completo (matriz
de pontos de contacto, ficheiros, migration) em `decisions_log.md` 2026-10-15.
**Confirmado aplicada em 2026-10-16** por dump real da BD viva (`supabase db dump`) — as 4
RPCs existem na BD com a assinatura esperada, os 4 fluxos já podem ser testados.

**Rotas órfãs — declaradas, sem nenhum caminho de navegação real**
- ~~`/client/messages` e `/worker/messages`~~ removidas a 2026-10-18 (decisão: sem chat na
  app, contacto só por WhatsApp).
- `/w/:workerId` (cartão público do worker) — a rota e o ecrã funcionam se visitados
  diretamente, mas **nada na app gera internamente um `context.push`/`go` para lá**.
  `AppLinks.publicWorkerProfileUrl()` só produz uma string de texto usada para mostrar num
  QR/partilhar. **Atualizado 2026-10-17:** na web o link aponta para o próprio site e já
  funciona; nas apps nativas usa `APP_PUBLIC_URL` (`--dart-define`) ou, sem ele, o
  placeholder `projardim.pt`. Com o site publicado e `APP_PUBLIC_URL` definido, o QR das
  apps abre o cartão no browser. Abrir diretamente dentro da app instalada (app links)
  continua por fazer e precisa do domínio final (ver `SETUP.md`).

### 🟡 MÉDIO — gaps de UX/segurança antes do lançamento mais amplo

(Os itens já existentes em `improvements.md` — `JobStatus` labels, CHECKs em falta, validação
de telefone, etc. — continuam válidos, sem mudança.)

- ✅ **RESOLVIDO 2026-10-12 — `friendlyError()` vs `AuthController._mapError()` consolidados.**
  `_mapError` removido; os 4 call sites de `auth_controller.dart` passaram a usar
  `friendlyError()`. Encontrado também um 3.º/4.º ponto que a auditoria de 2026-09-08 não
  tinha listado: `AuthRepository._throwClassified` (rede/código inválido/password fraca do
  fluxo de recuperação de senha, que precisa de um `code` estruturado para o
  `PasswordResetController` decidir o ecrã — por isso ficou separado, não foi absorvido por
  `friendlyError`) e `describePasswordResetError` (só lê `.message` de um `AuthException` já
  classificado). Detalhe completo em `decisions_log.md` 2026-10-12.
- **Notificações: 3 de 19 tipos usam `context.push` em vez de `context.go`**
  (`helpRequestApproved`, `helpRequestReopened`, `helpWithdrew`) — os outros 16 usam `go`. Isto
  é uma decisão deliberada e documentada (estes 3 casos preservam o botão de recuar de
  propósito), não um esquecimento — mas vale a pena ter presente que a regra "notificações
  usam go" tem exceções.
- ✅ **Rating sheets renomeados (2026-10-17).** Os dois ficheiros com nomes quase iguais
  passaram a `submit_rating_sheet.dart` (`showSubmitRatingSheet`, submeter uma avaliação
  nova) e `worker_ratings_sheet.dart` (`showWorkerRatingsSheet`, ver as avaliações de outro
  worker a partir de um fluxo). Continuam os dois em uso e são diferentes do ecrã
  "As minhas avaliações" (`my_ratings_screen.dart`).

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
| `help_acceptances.message` (0034) | Coberto pelas policies row-level já existentes | N/A | Coluna nova, sem policy nova necessária (raciocínio documentado na própria migration). Desde a 0047 (por aplicar) chega ao principal via `get_candidates_for_help_request`, que continua a filtrar por `is_principal_worker_for_help_request` (`auth.uid()`). |
| `get_worker_job_board` (0035) | Sim — **sem parâmetro `p_worker_id`**, só `auth.uid()` | N/A | O cabeçalho da migration cita explicitamente a 0032 como razão de desenho. |
| `worker_fleet_cards` (0037) | Sim — SELECT/INSERT só do próprio (`worker_id = auth.uid()`) | **Sim até à 0042** — o INSERT não limitava `status`, dava para inserir já `active`. A 0042 exige `status = 'pending'` no WITH CHECK | Mesmo padrão de moderação manual que `job_reports`. |

**Conclusão da auditoria de RLS:** nenhuma migration desde a 0028 reintroduz a classe de
vulnerabilidade corrigida em 0032 (parâmetro de identidade vindo do cliente em vez de
`auth.uid()`). A 0032 está confirmada como aplicada à BD viva desde 2026-09-09 (ver secção
"Gaps conhecidos" acima) — o código está certo e a correção já chegou à BD viva.

### Review de segurança de 2026-10-16 (migration 0042, aplicada a 2026-10-16)

O review completo de 2026-10-16 encontrou falhas exploráveis com uma conta
normal que as auditorias anteriores não apanharam: `cancel_job` sem
autorização (qualquer conta cancelava qualquer pedido), `create_user_profile`
aberta a anon (reescrevia nome/telefone de qualquer utilizador), propostas
`accepted` forjadas por INSERT direto (telefone/morada do cliente e
`mark_job_done` de trabalhos alheios), avaliações falsas (pedido inserido já
`completed` + rating a qualquer worker), UPDATE livre em `job_requests`,
`reject_proposal` sem autorização e cartão frota auto-ativável. Tudo corrigido
na `0042_security_hardening.sql`, testada num Postgres local com os ataques
simulados (todos bloqueados) e os fluxos normais da app (todos a funcionar).
Relatório completo: `/mnt/project-files/projardim/review/2026-10-16-review-codigo.md`.

**A 0042 foi aplicada na BD viva a 2026-10-16; estas falhas estão fechadas.**

**Catálogo de serviços (0045, aplicada):** Jardinagem, Agricultura e Floresta, 33 tipos com ícone. Aplicar antes da app nova.

**Revisão dos fluxos (18/10, 0048 NÃO aplicada):** ver `decisions_log.md` e `/mnt/project-files/projardim/revisao-fluxos.md`. Sem a 0048 a app funciona como antes nas partes que dependem dela.

**Mensagem do candidato a ajudante (0047, NÃO aplicada):** o jardineiro principal vê no lobby o que o candidato escreveu ao candidatar-se. Sem a 0047 aplicada o cartão aparece como antes, sem a mensagem.

**Regras do dia do trabalho (0046, aplicada):** concluir só a partir do dia, com foto opcional; pedidos com data passada deixam de aparecer e expiram; trabalho confirmado sem conclusão expira 3 dias depois da data; lembretes de manhã no dia e de confirmação. Ver `decisions_log.md`.

**RPCs sem `p_worker_id` e policies mais rápidas (0044, NÃO aplicada):** fecha os pontos baixos que ficaram do review. Aplicar junto com a app nova.

**Morada dos pedidos (0043, aplicada a 2026-10-16):** decisão de 2026-10-16. Até a
proposta ser aceite, o jardineiro vê só a localidade e coordenadas
arredondadas (~1 km). Antes, qualquer conta lia a morada exata de todos os
pedidos abertos.

### Riscos aceites (sem mudança desde 2026-07-09)

~~SA1, SA2, SA3~~ — **todos fechados (confirmado no código a 2026-10-18):** SA1 pela 0042/0046
(`REVOKE EXECUTE` de `auto_confirm_completed_jobs`/`auto_expire_jobs` a `authenticated`),
SA2 pela 0042 (S4), SA3 já na baseline 0001.

---

## O que é preciso antes do primeiro utilizador real fora da equipa

Sem mudanças na lista de bloqueadores desde 2026-07-09 (FCM push continua o nº 1). O item
"confirmar se 0032–0037 estão aplicadas" foi resolvido em 2026-09-09 (ver "Gaps conhecidos").

Ver `improvements.md` para a lista completa (FCM, validação de telefone, verificação de
identidade, nome de marca definitivo, testes com utilizadores externos).
