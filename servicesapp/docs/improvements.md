# LocalServices — Improvements & Future Ideas

> Lista viva de ideias, melhorias e features que NÃO entram na fase atual mas
> ficam registadas para não se perderem. Sempre que aparecer uma ideia boa que
> não cabe no momento, adicionar aqui em vez de esquecer.
>
> Cada item: descrição curta, contexto/porquê, e prioridade subjetiva.
>
> **Organização:** Itens por resolver ordenados por severidade (Crítico → Alta → Média → Baixa). Decisões de produto e features futuras a seguir. Resolvidos no final como referência histórica.

---

## 🟠 Alta prioridade — Por resolver

### T6 / P-8-9 ✅ RESOLVIDO 2026-07-01 — Deep-link de notificações

Auditoria completa de `notification_handler.dart` em 2026-07-01. Todos os 19 tipos de notificação navegam agora para o destino correto:
- **Lifecycle com role-split** (`jobCancelled`, `rescheduleProposed/Accepted/Rejected`, `jobCompleted`): cliente → `context.go('/client/job/$id')`; worker → async fetch proposalId → `context.go('/worker/my-job/$pid?jobId=$id')`, fallback home se fetch nulo.
- **Client-only** (`jobMarkedDone`, `jobNoResponse`, `proposalReceived`, `proposalWithdrawn`): `context.go('/client/job/$id')`.
- **Worker discovery** (`newJobInRadius`, `jobReopened`, `proposalRejected`): `context.push('/worker/job/$id')`.
- **Help-request** (`helpRequestApproved`, `helpWithdrew`): fetch help_request → push lobby; fallback home.
- **Candidatures** (`helpAccepted`, `helpRejected`, `helpJobCancelled`): `context.go` → tab 1.
- `context.go` usado (em vez de `context.push`) em todos os lifecycle events — elimina RT1 keyReservation crash por navegação dupla.
- RT4 corrigido: `proposalAccepted` com fetch nulo agora navega para home + SnackBar em vez de break silencioso.
- `helpRejected` agora navega para candidaturas (antes: break silencioso).
- `helpRequestApproved` e `helpWithdrew` têm fallback para home (antes: break silencioso se fetch null).
- Todos os casos com `await` têm `if (!context.mounted) break` imediatamente após.

---

## 🟡 Média prioridade — Por resolver

### P1 / A1 — JobStatus color-label duplicada 4× com inconsistências

A mesma lógica "JobStatus → (label, Color)" implementada independentemente em 4 lugares:
- `client_home_screen.dart:226` — `_statusChip()`, label `open`: **"À espera"**
- `client_jobs_screen.dart:182` — `_statusChip()`, label `open`: **"À espera de proposta"** ← inconsistente
- `client_job_detail_screen.dart:1267` — `_statusInfo()`, label `open`: **"À espera de proposta"**
- `worker_help_requests_screen.dart:359` — `_jobStatusDisplay(String)` opera em strings brutas; `open` e `no_response` caem no wildcard `'Em aberto'`; sem exaustividade de compilador

**Acção:** criar extension `StatusDisplay` em `JobStatus` com switch exaustivo que devolve label e cor. Todos os ecrãs chamam `status.displayInfo(proposalCount)`. Resolve a inconsistência e ~100 linhas de duplicação.

---

### P-8-2 / M1 Fase 8 — N+1 queries de nome de worker em `_ProposalCard`

`client_job_detail_screen.dart` (`_ProposalCard` l.1079 / `workerNameProvider` ref l.1094) — `ref.watch(workerNameProvider(proposal.workerId))` por proposta. Para N propostas de N workers: N round-trips. O lado do worker (`fetchPendingWorkerProposals`, etc.) já usa o padrão de embedded resources PostgREST. O mesmo padrão não foi aplicado ao lado do cliente.

**Acção:** aplicar embedded join em `fetchPendingProposalsForJob`:
```dart
// proposal_repository.dart:38 — ANTES: .select()
// DEPOIS (confirmar nome FK antes de implementar):
.select('*, profiles!job_proposals_worker_id_fkey(full_name, id)')
```
Adicionar `workerName` ao modelo `JobProposal`. Atualizar `_ProposalCard` para usar `proposal.workerName` diretamente. N queries → 1 query. **Esforço: ~45 min.**

---

### M4 Fases 4-5 — CHECK constraints em `people_needed` e `slots_needed`

Sem estes CHECKs, `accept_proposal` pode calcular `slots_needed = people_needed - 1 = -1` se `people_needed = 0` chegar à BD, criando uma help_request com `slots_needed` negativo (imediatamente considerada "filled").

**Acção:**
```sql
ALTER TABLE job_proposals ADD CONSTRAINT check_people_needed CHECK (people_needed >= 1);
ALTER TABLE help_requests ADD CONSTRAINT check_slots_needed CHECK (slots_needed >= 1);
```

---

### M4 Fases 6-7 — `PendingSignupStateProvider` (resolve causa raiz de "dados perdidos em redirect")

`fullName`/`phone` continuam a ser passados como `state.extra` para `/choose-role`. Qualquer futura alteração ao router que crie um novo caminho de redirect volta a perder os dados.

**Acção:**
```dart
// lib/features/auth/application/pending_signup_provider.dart
@immutable
class PendingSignupData {
  final String fullName;
  final String phone;
  const PendingSignupData({required this.fullName, required this.phone});
}
final pendingSignupProvider = StateProvider<PendingSignupData?>((ref) => null);
```
`SignupScreen` escreve para o provider antes de `context.go('/choose-role')`. `ChooseRoleScreen` lê do provider. Após `createProfile` ter sucesso, reset para null. **Esforço: ~1.5h.**

---

### P-10-2 / M2 Fase 10 — Contacto do worker principal não visível ao ajudante

`project_overview.md` especifica: *"Ajudantes veem o contacto do worker principal, não o do client (no MVP)."* `principalPhone` — campo **não existe** em `HelpAcceptanceSummary` nem em `HelpAcceptanceDetails`. Sem botão WhatsApp em qualquer ecrã para o ajudante contactar o principal.

**Acção:**
1. Atualizar `get_my_help_acceptances` RPC para incluir `p.phone AS principal_phone` (JOIN `profiles p ON p.id = jp.worker_id`)
2. Adicionar `principalPhone: String` a `HelpAcceptanceSummary` e `HelpAcceptanceDetails`
3. Adicionar botão WhatsApp nos cards `accepted` em `worker_help_requests_screen.dart`

Verificar se a RLS de `profiles` para worker→worker está coberta (RPC é SECURITY DEFINER — RLS bypassed). **Esforço: ~1.5h.**

---

### P-8-7 / M3 Fase 8 — `fetchScheduledWorkerProposals` busca TODAS as propostas `accepted` e filtra no cliente

`proposal_repository.dart:131` — busca todos os registos `status = 'accepted'` do worker, depois descarta no Dart tudo o que não seja `confirmed | awaiting_confirmation`. Worker com 50 jobs concluídos transfere todos os 50 para mostrar 1 ou 2 na tab "Agendados". Já tinha um TODO comentado no código.

**Acção:** mover filtro para a BD via filtro PostgREST no embedded resource.

---

### `fetchCompletedWorkerProposals` — filtro client-side antes de paginação

A query usa `.range(page * pageSize, ...)` antes de filtrar `job_requests.status == 'completed'` client-side. Páginas podem ter menos items que `pageSize` mesmo quando há mais páginas, levando o utilizador a não carregar mais quando ainda existem dados.

**Acção:** criar RPC `get_completed_worker_proposals(p_worker_id, p_limit, p_offset)` que filtra por `status = 'accepted'` E `job_requests.status = 'completed'` antes de paginar — garantindo que o `LIMIT` se aplica após o filtro.

---

### P-8-8 — Jobs cancelados em `open` invisíveis no histórico do cliente (decisão de produto)

`client_jobs_screen.dart:45`: `(j.status == JobStatus.cancelled && j.acceptedProposalId != null)`. Jobs cancelados antes de qualquer proposta ser aceite (`acceptedProposalId = null`) não aparecem no histórico. Pode ser intencional (menos lixo) ou um descuido. Sem registo explícito da intenção no `decisions_log`.

**Acção:** confirmar intenção e registar em `decisions_log.md`.

---

## 🔵 Baixa prioridade / Limpeza — Por resolver

### P2 / M2 Fases 0-3 — Cores hex hardcoded divergentes do seed do tema

- `app_router.dart:44` — `Color(0xFF2E7D32)` para spinner de loading (duplica `AppTheme._seed` sem ligação)
- `status_timeline.dart:118` — `Color(0xFF43A047)` para círculo "done" (verde diferente do seed)

**Acção:** tornar `_seed` público (`seed`) em `AppTheme` e substituir `Color(0xFF2E7D32)` em `app_router.dart` por `AppTheme.seed`. Uma linha.

---

### P3 / M1 Fases 0-3 — `Colors.orange` sem token semântico partilhado

`Colors.orange.shade700` em chips de urgência, badge de "propostas pendentes", banner de "remarcação pendente" e ícones de notificação — features diferentes, sem token partilhado. O Material 3 já gera `colorScheme.tertiary` (warning/accent) e `colorScheme.error` (destrutivo) a partir do seed.

**Acção:** substituir `Colors.orange.shade700` por `theme.colorScheme.tertiary` e `Colors.red` por `theme.colorScheme.error` nos SnackBars de erro.

---

### P4 / B3 Fases 0-3 — Wildcard em `_HistoryCard._statusLabel` silencia 2 casos válidos

`worker_help_requests_screen.dart:509` — `_ => '—'` silencia `.pending` e `.accepted`. Seguro hoje pelo filtro upstream, mas um novo valor no enum cai silenciosamente no wildcard.

**Acção:** substituir `_ => '—'` por casos explícitos:
```dart
HelpAcceptanceStatus.pending  => 'Pendente',   // não deve aparecer aqui
HelpAcceptanceStatus.accepted => 'Aceite',     // não deve aparecer aqui
```

---

### P7 / M6 Fases 0-3 — `architecture.md` tem diagrama de pastas obsoleto

`ratings/` listado (não existe — Fase 11 por implementar); `notifications/` omitido (totalmente implementado com estrutura própria `data/`, `application/`, `presentation/`).

**Acção:** adicionar `notifications/` e anotar `ratings/` como `# Fase 11 — não implementado`. 2 linhas.

---

### P8 / B4 Fases 0-3 — `worker_setup_screen.dart` chama Supabase direto no widget

`worker_setup_screen.dart:178` — única violação de architecture.md Princípio #2 ("Nunca chamar Supabase diretamente dentro de widgets").

**Acção:** mover o `from('profiles').select('full_name, phone')` para `fetchBasicProfile(userId)` no `WorkerRepository` ou `ClientRepository`.

---

### M4 Fases 0-3 — Constantes de border radius no AppTheme

Três valores aparecem repetidamente: `8` (~8 ocorrências), `12` (~12 ocorrências), `16` (~4 ocorrências).

**Acção:** adicionar `static const double radiusSmall = 8; radiusMedium = 12; radiusLarge = 16;` ao `AppTheme`.

---

### M5 Fases 0-3 — Documentar setup de `--dart-define` para novos contribuidores

O `decisions_log.md` regista a decisão (2026-06-02) mas não dá instruções de setup. Falta: (1) que existe um `.vscode/launch.json` gitignored, (2) esqueleto do ficheiro com `SUPABASE_URL` e `SUPABASE_ANON_KEY`, (3) onde obter os valores.

**Acção:** adicionar secção "Setup de desenvolvimento" em `project_overview.md`.

---

### M6 Fases 4-5 — Coluna "Migration atual" na tabela de RPCs do `database_schema.md`

`cancel_job` tem corpo completo em 4 migrations; `accept_proposal` em 2; `create_proposal` em 3. Não é óbvio qual é a versão autoritativa sem ler todas.

**Acção:** adicionar coluna "Definido/atualizado em" à tabela de RPCs em `database_schema.md`.

---

### B2 Fases 4-5 — Policy "Sistema insere notificações": inconsistência docs-vs-baseline

0001_baseline cria a policy; `database_schema.md` diz que não existe na BD viva. A policy é funcionalmente harmless (SECURITY DEFINER bypassa RLS independentemente) mas confusa para quem audite.

**Acção:** atualizar `database_schema.md` para refletir que a policy existe no 0001 mas é redundante, ou fazer DROP com comentário.

---

### B3 Fases 4-5 — Remover coluna legacy `job_proposals.estimated_hours`

Coluna nullable que predata o split min/max (2026-06-11). Não mapeada em `JobProposal.fromJson`.

**Acção:** aproveitar migration da Fase 11 (ratings): `ALTER TABLE job_proposals DROP COLUMN IF EXISTS estimated_hours;`

---

### B4 Fases 4-5 — CHECK `(hourly_rate >= 0)` em `job_proposals`

`job_proposals.hourly_rate` é NOT NULL mas sem CHECK. Segue o padrão já estabelecido pelo `check_agreed_rate` em `help_acceptances` (migration 0007). Usar `>= 0` (não `> 0`) para permitir "negociar no local" como sinal explícito.

---

### B1 Fases 6-7 — Validação de email com regex mínimo

`signup_screen.dart` e `login_screen.dart` — `!v.contains('@')` aceita `@`, `test@@`, `a@`. O Supabase rejeita emails inválidos ao nível do servidor, mas o feedback chega mais tarde.

**Acção:** `RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())` — sem pacotes adicionais.

---

### B2 Fases 6-7 — Validação de tamanho mínimo no telefone

Número como `"1"` ou `"abc"` passa e fica guardado. Link WhatsApp construído com `wa.me/<número limpo>` — número inválido = link quebrado.

**Acção:** verificar mínimo 9 dígitos após `replaceAll(RegExp(r'[\s\-\+\(\)]'), '')`.

---

### B3 Fases 6-7 — Indicador de loading específico para upload de avatar

Ambos os ecrãs de perfil usam `_saving = true` para todo o ciclo (upload avatar + update BD). Upload pode demorar 1-5s numa ligação móvel fraca.

**Acção:** estado `_uploadingAvatar` separado com texto "A carregar foto..." nos ecrãs de perfil.

---

### B2 Fase 8 — `RescheduleDialog`: confirmar se impede seleção de data passada

A BD bloqueia via regra das 24h em `propose_reschedule`. Validação client-side com `firstDate: DateTime.now().add(Duration(days: 1))` daria feedback imediato.

**Acção:** ler `reschedule_dialog.dart` para confirmar estado atual.

---

### B3 Fase 8 — `state_machine.md` omite `jobsInRadiusProvider` em `proposalRejected`

Código em `notification_providers.dart:84` invalida corretamente `jobsInRadiusProvider` para `proposalRejected`. O documento `state_machine.md` não lista este provider na linha correspondente. Fix de documentação, não de código.

---

### B4 Fase 8 — `workerProposalForJobProvider` não invalidado para cliente após `proposalAccepted`

Edge case sem ecrã atual que dependa diretamente. Acionável se um futuro ecrã de cliente observar este estado.

---

### B1 Fase 9 — Paginação em `get_my_help_acceptances`

`0010_my_help_acceptances_rpc.sql:53` — ORDER BY sem LIMIT/OFFSET. Aceitável a esta escala. Mesmo padrão de `fetchCompletedWorkerProposals` quando volume justificar — Fase 11+.

---

### B2 Fase 9 — Documentar (ou impor via constraint) que um job tem um único `help_request`

Schema permite múltiplos (sem UNIQUE em `(job_id, proposal_id)`). Intenção MVP: one-to-one. Não registado em nenhum dos dois sentidos.

---

### B1 Fase 10 — Mover `reportJobProblem()` para `job_repository.dart`

`proposal_repository.dart:212` — método que insere em `job_reports` sem relação com propostas. **Esforço: ~15 min.**

---

### B2 Fase 10 — Remover fetch de perfil de cliente no bloco `rejected`

`worker_my_job_detail_screen.dart:653` — `clientInfoAsync.when(...)` observado no bloco `ProposalStatus.rejected`, mas RLS sempre bloqueia (job não confirmado). O fetch de rede nunca produz resultado. **Esforço: trivial.**

---

### B3 Fase 10 — Validação de data em `mark_job_done`

Worker pode marcar como concluído antes da data confirmada — a BD não valida `confirmed_date`. Considerar em Fase 11 quando avaliações forem implementadas (avaliação imediata antes da data faz menos sentido).

---

### Paginação nas tabs "Por confirmar" e "Agendados"

Actualmente sem limite. Para workers muito ativos (>50 items por tab). Adiar para quando houver dados reais que justifiquem.

---

### Compressão e thumbnails de fotos

Hoje comprimimos a 800px/60% no upload. Para thumbs em listas podia ser mais agressivo. Gerar thumb 400px no upload (segundo ficheiro) e usar nas listas. Original só no detalhe.

---

### Image transformations do Supabase

Supabase tem CDN com transforms on-the-fly (resize, quality) — mas no Free Plan tem limites. Avaliar quando upgrade fizer sentido.

---

### B1 Fases 0-3 — Boilerplate de enums (decisão: manter)

9 enums × ~6-15 linhas = ~100 linhas total. Code-gen adicionaria build_runner e indireção para ganho mínimo. **Decisão: manter o boilerplate.** Compilador apanha casos em falta nos switches de expressão.

---

### B2 Fases 0-3 — Partilha estrutural `ClientShell`/`WorkerShell` (decisão: manter separados)

Os dois shells têm tabs, ícones, FAB logic suficientemente diferentes para que um `GenericShell(tabs: [...])` fique tão complexo quanto a separação atual. **Decisão: manter separados.** O momento certo é quando surgir um terceiro shell ou comportamento partilhado.

---

### P-FA8 — `cancel_job` reproduzido em 4 migrations (comprehension hazard — sem ação agora)

Corpo completo em 0001, 0007, 0009 e 0013. Cada migration é self-contained por design. **Sem ação agora.** Se o número de migrations passar de 20, considerar `supabase/FUNCTION_HISTORY.md` que mapeie cada função → migration mais recente.

---

## 📋 Decisões de produto pendentes

### RC2 — O cliente deve ver a composição da equipa?

Hoje um cliente que contratou um trabalho para 3 pessoas vê o mesmo que um cliente com trabalho solo: nome e contacto do prestador principal. Sem visibilidade sobre nº de vagas, quem são os ajudantes, ou se um desistiu. A infraestrutura está pronta (dados existem, policy SELECT adicionada em migration 0026).

**O que precisa de decidir:** a transparência da equipa para o cliente é uma feature do MVP ou é deliberadamente opaca por design (o cliente contrata o principal, o principal gere a equipa)?

---

### RC4 — O cliente deve ser avisado que a sua avaliação se propaga a todos os ajudantes?

`submit_client_rating` aplica as mesmas estrelas ao prestador principal e a cada ajudante aceite com uma única ação. O utilizador vê "Avaliar o trabalho" — sem menção de que esta avaliação também afeta 2-3 outras pessoas que podem ter tido desempenhos distintos.

**O que precisa de decidir:**
- a) Manter como está (propagação silenciosa, simplicidade máxima)
- b) Acrescentar uma linha explicativa: "Esta avaliação aplica-se ao prestador e à equipa" — sem alterar o fluxo
- c) Mostrar os nomes dos ajudantes no sheet para o cliente ter consciência de quem está a avaliar

---

### RC5 — O cliente deve receber orientação quando um job expira sem propostas?

Quando um job expira para `no_response` após 48h, o cliente recebe notificação e o job fica em estado terminal. Sem indicação sobre porquê (zona sem cobertura? preço abaixo do mercado?) nem sugestão do que fazer a seguir. A app sabe o nº de workers no raio quando o job foi criado — 0 workers notificados significa zona sem cobertura.

**O que precisa de decidir:** simplificação máxima (sem guidance) vs. mensagem contextual mínima no ecrã de job expirado?

---

### RC6 — A janela de 3 dias para auto-confirmação deve ser visível na UI?

Após o worker marcar como concluído (`awaiting_confirmation`), o job é automaticamente confirmado ao fim de 3 dias. Nem worker nem cliente veem este prazo — para o worker parece espera indefinida; para o cliente não há urgência percetível.

**O que precisa de decidir:** mostrar contagem decrescente ("Confirmar nos próximos 2 dias", calculado de `jobs.updated_at + 3 dias`) ou deixar sem indicação explícita?

---

### Notas de registo (sem decisão necessária, sem código para escrever)

- **Notificação de equipa completa ausente:** quando `help_request.status` passa a `filled`, o cliente não recebe notificação. Relevante só se RC2 decidir que o cliente tem visibilidade da equipa.
- **Workers com proposta pending não são notificados quando o cliente cancela um job em `open`:** o job desaparece silenciosamente da lista deles. Não é um bug crítico mas é uma experiência confusa para um worker novo.
- **Horas reais trabalhadas nunca capturadas:** o sistema sabe o estimado e acordado, mas não o efetivamente trabalhado. Bloqueia dashboards de ganhos precisos e lógica de faturação. A janela para adicionar `actual_hours_worked` é agora (junto à conclusão do job), não depois de haver dados acumulados sem ele.
- **`excluded_worker_ids` é opaco para o worker:** worker excluído vê o job desaparecer sem indicação. Sem mecanismo de recurso. Aceitável para MVP.

---

## 💡 Features futuras e ideias

### Muito Alta prioridade

**Push notifications (FCM)**
Realtime in-app funciona, mas não notifica fora da app. Firebase Cloud Messaging + Supabase Edge Function que dispara push quando entra notificação na tabela. **Workers vão perder pedidos sem isto — pós-MVP imediato.**

**Relações persistentes Worker ↔ Cliente + Jobs recorrentes**
Anti-desintermediação mais importante. Visão em camadas (implementar por ordem):

- **Camada 1 — Conversa persistente** (pós mini-chat de proposta): canal de mensagens direto criado automaticamente após o primeiro job completed entre os dois. Mantém-se para trabalhos futuros. Substitui o WhatsApp para comunicação recorrente.
- **Camada 2 — Jobs recorrentes**: dentro da conversa, cliente ativa "repetir trabalho" com frequência (semanal, quinzenal, mensal). Worker confirma. Jobs seguintes criam-se automaticamente com proposta automática (mesmo worker, mesmo preço). Sem marketplace.
- **Camada 3 — Perfil de cliente para o worker**: histórico, morada guardada, notas pessoais ("tem cão", "portão azul"), ganhos totais.

Modelo de dados: `worker_client_relationships`, `relationship_messages`, `recurring_jobs`. Dependência: mini-chat implementado primeiro.

**Pedidos recorrentes**
"Corte de relva quinzenal" — receita previsível para o jardineiro, conveniência para o cliente, uso recorrente. Ao criar pedido, opção "Repetir" com frequência. Cria jobs automaticamente. Dependência: Relações persistentes.

---

### Alta prioridade

**Mini-chat por proposta (modelo Vinted)**
Cada job_proposal tem um chat associado — cliente e worker trocam mensagens dentro dessa proposta específica. Realtime via Supabase Realtime (infraestrutura já existe). Modelo de dados: `proposal_messages(id, proposal_id, sender_id, content, created_at)`. RLS: só client e worker da proposta veem as mensagens. UI: bottom sheet da proposta com tabs "Detalhes" e "Chat". Após proposta rejeitada/retirada, chat fica em modo leitura. **Diferenciador forte vs contacto por WhatsApp.**

**Vista de agenda do worker**
Worker com vários jobs agendados precisa de hierarquia temporal. Vista alternativa em calendário (semana/mês) com slots ocupados. Divisores "Hoje" / "Esta semana" / "Mais tarde" na lista. **Essencial assim que workers tiverem 5+ jobs simultâneos.**

**Perfil de worker visitável (em camadas)**

- **Camada 1:** ecrã `worker_profile_screen` com dois modos — "próprio" (mostra botão editar) vs "visitante" (read-only), decidido por `profile_id == auth.uid()`. RLS: cliente vê worker_profiles desde proposta `pending`. Conteúdo: foto, área de atuação, ferramentas, tipos de trabalho, avaliações. **Risco:** query pública não deve expor `base_lat`/`base_lng` — filtrar ao nível da query/DTO, não confiar só na RLS.
- **Camada 2 — Portfólio de trabalhos:** worker publica fotos de trabalhos feitos (campo `photos` já existe em `worker_profiles`). Depende da Camada 1.
- **Camada 3 — Feed na home:** workers próximos/recomendados na página inicial do cliente. Depende de 1 e 2 testadas com utilizadores.

Camada 1 pode avançar a qualquer momento sem bloqueios externos.

**Perfil público partilhável**
URL público `/p/<worker-slug>` com perfil, fotos, avaliações, serviços, zona. Cada partilha é aquisição grátis. Complementa o perfil visitável (este item é partilha FORA da app; Camada 1 acima é visibilidade DENTRO). A estrutura de dados pode ser partilhada entre os dois.

**Dashboard do jardineiro**
"Quanto fiz este mês? Quantos km? Quantos trabalhos?" Ecrã com estatísticas mensais — ganhos, km, jobs feitos, % avaliação. Alimenta sentido de "isto é o meu negócio".

**Trabalhos externos (agenda)**
Worker adiciona trabalhos que não vieram pela app à sua agenda. Permite organizar rotas e ter visão completa do dia. Botão `+` do worker já está reservado para isto.

**Verificação de identidade Nível 2**
Upload de documento de identidade, verificação manual no início, selo visível no perfil. **Pós-MVP imediato** — para serviços em casa de pessoas, confiança é tudo.

**Nome próprio em português**
"LocalServices" é genérico e mau para SEO. Considerar nome memorável antes do lançamento público. Mudar agora é barato, depois é caro.

**Logo e identidade visual**
Trabalhar com designer no UI Playground em paralelo à app principal.

---

### Média prioridade

**Comparação lado-a-lado de propostas**
Para 3+ propostas, vista em tabela (worker, preço, horas, data). Toggle entre vista de cards e tabela. Só faz sentido após validação com utilizadores reais.

**Badge de "novas propostas" na tab Propostas**
Badge colorido se houver propostas não vistas desde a última visualização.

**Orçamento por projeto**
Novo tipo de pedido "Orçamento", worker envia proposta com valor total + descrição. Abre mercado de trabalhos maiores.

**Otimização de rotas**
Worker com 5 jobs num dia em sítios diferentes. Algoritmo nearest-neighbor ou integração Google Maps.

**Faturação simplificada**
Parceria com InvoiceXpress ou similar, ou guias práticos dentro da app.

**Chat in-app (genérico)**
Chat simples (Supabase Realtime, tabela `messages`) para negociar antes/durante o trabalho sem sair da app.

**Lembretes sazonais**
Notificações por categoria/serviço em datas específicas. Ex: outubro → "Está na altura de preparar o jardim para o inverno."

**Contador de cancelamentos tardios**
"Cumpre compromissos: 95%" no perfil público. Depende das avaliações estarem prontas.

**Restrição de "marcar concluído" antes da data**
Bloquear ou avisar "Tens a certeza? O trabalho está marcado para o dia X."

**Idade visual das propostas pendentes**
Cor por idade — <24h normal, 24-48h amarelo, >48h cinzento (a expirar). "Há 6h", "Há 2 dias".

---

### Baixa prioridade

**Aceitar 1ª proposta sem ver mais**
Mensagem orientativa "Recomendamos aguardar até 24h para ver mais opções" — orienta sem bloquear.

**Agrupamento visual de jobs reabertos**
"Cancelado → Reaberto como #..." numa linha no histórico. Só relevante quando o histórico ficar denso.

**Categorias além de jardinagem**
Limpeza, pequenas reparações, manutenção. Só depois de jardinagem ter tração numa zona — não expandir antes de validar.

**Resumo diário do worker**
Notificação ao fim do dia: "Hoje recebeste 2 propostas, ganhaste €X."

---

### Pós-MVP / Dependência de parceria externa

**Carteira digital de cartões (combustível/seguro)**
Bloqueado por decisão de NEGÓCIO — precisa de pelo menos uma parceria de benefícios fechada (business_strategy.md secção 2, todas "Estado: Ideia" atualmente). Versão viável: foto do cartão + campos de texto livre, mostrado em full-screen para leitura manual. Sem integração NFC nem emissão de pagamento.
Modelo de dados (rascunho, não implementar): `worker_benefit_cards(id, worker_id, card_type, label, photo_front_url, photo_back_url nullable, card_number nullable, created_at)`.

---

### Avaliações — Pós-Fase 11 (Fase 12+)

As 4 relações de avaliação, 3 RPCs SECURITY DEFINER e UI inline estão implementadas (migration 0021 — aplicar manualmente se ainda não aplicado). Ver `decisions_log.md` 2026-06-26.

**Exibir média de estrelas no perfil do worker:** `fetchRatingsForProfile` já existe em `RatingRepository`. Falta calcular a média e exibi-la em `worker_profile_screen.dart` e nos cards de propostas.

**Resposta a avaliações:** worker responde publicamente a uma avaliação. Requer nova coluna `reply_text` na tabela `ratings` e UI dedicada.

---

### Nota: Timeline de estados — implementação temporária

`lib/core/widgets/status_timeline.dart` — primeira versão funcional, será refeita do zero no redesign visual. Não investir em polish visual — só correção de bugs funcionais reais. A lógica de derivação (`job_timeline.dart`) provavelmente sobrevive ao redesign.

---

## Sessão de testes — Run 1, 2026-07-01

> Achados do primeiro run do dashboard de testes manuais executado por Henrique.
> Cada item cross-referenciado contra `improvements.md` e `decisions_log.md` antes de registar.
> Nenhum item corrigido ainda — documentação para não se perder.

### RT1 ✅ RESOLVIDO 2026-07-01 — CRASH: keyReservation.contains(key) is not true

Eliminado pela auditoria completa de `notification_handler.dart`: todos os lifecycle event cases (`proposalReceived`, `proposalWithdrawn`, `jobCancelled`, `rescheduleProposed/Accepted/Rejected`, `jobMarkedDone`, `jobCompleted`, `jobNoResponse`) agora usam `context.go` em vez de `context.push`. `context.go` substitui o stack de navegação em vez de empilhar — sem possibilidade de push duplicado para a mesma rota, sem colisão de key.

---

### RT2 ✅ RESOLVIDO 2026-07-01 — `proposalReceived` não invalida `jobByIdProvider` (gap em fix existente)

`notification_providers.dart` — adicionado `if (notification.relatedId != null) ref.invalidate(jobByIdProvider(notification.relatedId!))` ao handler de `proposalReceived`. `relatedId` confirmado como `p_job_id` via migration 0001_baseline.sql:613. Se o cliente estiver no ecrã de detalhe quando a notificação chega, o `jobByIdProvider` é agora invalidado imediatamente.

---

### RT3 ✅ RESOLVIDO 2026-07-01 — Avatar do worker ausente no card de contacto

`fetchWorkerBasicInfo` agora seleciona `full_name, phone, avatar_url`. `_workerContactCard` em `client_job_detail_screen.dart` usa o novo widget `UserAvatarWithName` — CircleAvatar com NetworkImage se `avatar_url` preenchido, inicial do nome caso contrário. Widget criado em `lib/core/widgets/user_avatar_with_name.dart`.

---

### RT4 ✅ RESOLVIDO 2026-07-01 — `proposalAccepted`: fetch nulo quebra navegação silenciosamente

`notification_handler.dart` — `proposalAccepted` agora: `if (!context.mounted) break` após await; se fetch nulo → `context.go('/worker/home')` + SnackBar "Não foi possível abrir o job. Verifica a lista de jobs." em vez de break silencioso. Mesmo padrão aplicado a `helpRequestApproved` e `helpWithdrew` (também tinham break silencioso se fetch nulo).

---

### RT5 ✅ RESOLVIDO 2026-07-01 — Cliente não vê preço/horas/data da proposta aceite

`client_job_detail_screen.dart`, bloco `confirmed`: adicionado card "Proposta aceite" com taxa/hora, horas estimadas, total estimado e número de pessoas. `acceptedProposalForJobProvider` já era watchado — apenas necessário inserir o card no bloco correto. Método `_acceptedProposalCard` adicionado.

---

### RT6 ✅ JÁ ESTAVA RESOLVIDO (confirmado 2026-07-01) — Worker aceita remarcação: UI só atualiza após restart

Confirmado por leitura directa de `worker_my_job_detail_screen.dart`: todos os três handlers (`_proposeReschedule` l.96, `_acceptReschedule` l.116, `_rejectReschedule` l.136) já tinham `ref.invalidate(jobByIdProvider(widget.jobId))` após `router.pop()`, seguindo o padrão T4. Fix estava presente antes desta sessão — provavelmente adicionado na sessão anterior do mesmo dia. Nenhuma alteração de código necessária.

---

### RT7 — "Marcar como concluído" funciona instantaneamente (NÃO É BUG)

Confirma que o padrão T4 (navegar depois invalidar) funciona quando aplicado corretamente. Referência de comportamento correto — sem ação necessária.

---

### RT8 ✅ RESOLVIDO 2026-07-01 — `jobCompleted` não invalida providers de rating (NOVO sub-achado dentro de T6)

`notification_providers.dart` — adicionados ao case `jobCompleted`: `if (notification.relatedId != null) ref.invalidate(myRatingForJobProvider(notification.relatedId!))` e `ref.invalidate(myRatingForJobAndRateeProvider)` (família completa, sem chave — aceitável por `jobCompleted` ser evento raro). Import `../../ratings/application/rating_providers.dart` adicionado. Ecrã de avaliação reflecte agora o estado correto sem precisar de restart. T6 (navegação do `jobCompleted`) permanece em aberto.

---

### RT9 ✅ RESOLVIDO 2026-07-01 — Estrela de avaliação ausente em jobs históricos

`_buildCompletedSection` em `worker_my_job_detail_screen.dart` confirmado correto — gated em `liveJobStatus == JobStatus.completed` dentro de `liveStatus == ProposalStatus.accepted`. O gap real era na lista: `_JobCard` em `worker_jobs_screen.dart` não mostrava nenhum indicador de avaliação para jobs concluídos. Adicionado widget `_RatingChip` (ConsumerWidget) que observa `myRatingForJobProvider(jobId)` — mostra chip "★ N/5" se já avaliado, nada se ainda não avaliado.

---

## ✅ Resolvidos

> Referência histórica. Detalhes técnicos em `decisions_log.md`.

### Bugs de produção — Sessão de testes manuais 2026-06-29

**T1 ✅ RESOLVIDO 2026-06-29** — Desync de estado de propostas: badge "1 proposta" na home vs "À espera de proposta" no detalhe. `ClientJobDetailScreen` reescrito com `jobId: String` + `jobByIdProvider`. Desync impossível por design.

**T2 ✅ RESOLVIDO 2026-06-29** — Overflow "OVERFLOWED BY 52 PIXELS" em `_workerContactCard()`: Row do nome e Row da data/hora envolvidos em `Expanded + TextOverflow.ellipsis`. Fix preventivo aplicado em `worker_my_job_detail_screen.dart`.

**T3 ✅ RESOLVIDO 2026-06-29** — Red screen `Null check operator used on a null value`: todas as 4 rotas removidas de `state.extra`. Navegação direta por deep link funciona sem crash.

**T4 ✅ RESOLVIDO 2026-06-29** — Red screen `'_dependents.isEmpty': is not true`: reordenação para `pop → go → snackBar → invalidate` + guard `navigatedAway` no `finally`. Fix preventivo aplicado a 3 locais em `client_job_detail_screen.dart`.

**T5 ✅ RESOLVIDO 2026-06-29 (migration 0025)** — Lógica de cancelamento invertida: cliente cancelava um job `confirmed` e a app recriava automaticamente sem consentimento. Novo parâmetro `p_client_wants_reopen boolean DEFAULT NULL`. Worker path completamente inalterado. Client path com dialog "Voltar a publicar?".

**T7 ✅ RESOLVIDO 2026-06-29** — Nome/avatar do candidato no lobby mostrava "—" e placeholder genérico. Causa: terceiro waterfall assíncrono (`helpRequestsForJobProvider → candidatesForHelpRequestProvider → profileSummaryProvider` por candidato), erros mascarados por `?? {}`. Resolução: join direto via PostgREST embedded resources (dois saltos: `worker_profiles(profiles(full_name, avatar_url))`). `HelpAcceptance` adicionou `fullName` e `avatarUrl`. Bloco `profileSummaries` e funções `nameOf`/`avatarOf` removidos do lobby screen.

---

### Routing e navegação

**P6 ✅ RESOLVIDO 2026-06-29** — Navigation-extra substituído por ID-based routing em 4 rotas: `/client/job/:id`, `/worker/job/:id`, `/worker/my-job/:id`, `/worker/job/:id/help-requests`. T6 desbloqueado estruturalmente. T1 e T3 eram sintomas diretos deste bug.

**P5 ✅ RESOLVIDO 2026-06-26** — Guard cross-role adicionado ao router em `app_router.dart` após o bloco `role == null`.

---

### Auth e sessão

**P-67-1 ✅ RESOLVIDO 2026-06-26/2026-06-28** — `/worker/setup`, `/worker/profile`, `/client/profile`, `/client/create-job` adicionados a `loadingExempt`. Elimina perda silenciosa de formulários após token refresh do Supabase (ImagePicker/Geolocator disparam o mesmo redirect).

**P-67-3 ✅** — SnackBar de erro de `client_profile_screen.dart` substituído por `friendlyError(e)`.

**P-67-4 ✅** — Widget `error:` de service types em `worker_setup_screen.dart` e `worker_profile_screen.dart` substituído por `${friendlyError(e)}`.

**P-67-5 ✅** — `worker_setup_screen.dart:178` `.single()` substituído por `.maybeSingle()` com null check e mensagem acionável.

**P-67-6 ✅** — `auth_controller.dart` — handlers para `email_not_confirmed` e `rate_limit` adicionados antes do fallback genérico.

---

### Schema e migrations

**P-FA2 ✅ RESOLVIDO (migration 0019)** — Storage DELETE policy para `job-photos` criada. Path alterado para `$clientId/$jobId/<ts>.jpg`. Fotos anteriores (path antigo) continuam não-apagáveis — sem impacto, não existe UI de apagamento.

**P-FA3 ✅ RESOLVIDO (migration 0018)** — Policy de UPDATE de avatars corrigida (`regexp_replace` em vez de `storage.foldername` que devolvia NULL para paths root-level). DELETE policy adicionada. Severidade elevada: bug real em produção — qualquer re-upload de avatar silenciosamente falhava.

**P-FA4 ✅ RESOLVIDO (migration 0016)** — `job_proposals` UPDATE policy sem `WITH CHECK`: corrigida com `WITH CHECK (auth.uid() = worker_id AND status = 'superseded')`.

**P-FA7 ✅ RESOLVIDO (migration 0019)** — DELETE policy para `job_photos` criada com EXISTS subquery em `job_requests` para verificar ownership.

**P-8-1 ✅ RESOLVIDO (migration 0020)** — Transição `open → no_response` implementada com `auto_expire_jobs()`, `FOR UPDATE SKIP LOCKED`, notificação `job_no_response` ao cliente. Cron `'auto-expire-jobs'` a `0 */3 * * *`. `notification_handler.dart` invalida `clientJobsProvider` e navega `/client/jobs`.

**P-8-3 ✅ RESOLVIDO 2026-06-26** — Compressão de fotos corrigida para 800px/60% em `job_repository.dart` (estava 1280px/72%).

**P-8-4 ✅ RESOLVIDO (migration 0016)** — Bypass de autorização em `reject_reschedule` corrigido. `propose_reschedule` e `accept_reschedule` já estavam corretas na BD viva (alteradas interativamente numa sessão anterior não registada).

**P-8-5 ✅ RESOLVIDO 2026-06-29** — `_job.copyWith()` eliminado de `client_job_detail_screen.dart`. Provider é sempre a única fonte de verdade.

**P-8-6 ✅ RESOLVIDO 2026-06-26** — `create_job_screen.dart:281` exceção em bruto substituída por `${friendlyError(e)}`.

**P-9-1 ✅ RESOLVIDO (migration 0017)** — `accept_help_candidate` auto-rejeita candidatos pending restantes quando `help_request` fica `filled`. Loop FOR adicionado — rejeita e notifica todos os outros pending imediatamente.

**P-9-2 / P-9-4 ✅ RESOLVIDO** — Candidatos overflow não acionáveis: modelo de grelha com `isOverflow` eliminado. Lobby mostra todos os candidatos pending como lista plana, cada um acionável. Label "Preenchida" ambígua: fechado pela mesma mudança estrutural.

**P-9-3 / A2 Fase 9 ✅ RESOLVIDO (migration 0026)** — `NOT EXISTS` clause adicionada ao WHERE de `get_help_requests_in_radius`. Exclui help_requests onde o worker já tem candidatura ativa. `_appliedIds` deixou de ser necessário.

**P-9-5 ✅ RESOLVIDO 2026-06-28** — `pending_approval` UI: botão "Adicionar ajudante" em `worker_my_job_detail_screen.dart` e card "Aprovar equipa" em `client_job_detail_screen.dart`. Fluxo completo de ponta a ponta.

**P-10-3 ✅ RESOLVIDO (migration 0020)** — `auto_confirm_completed_jobs()` passa a notificar o cliente. `clientJobsProvider` adicionado ao caso `jobCompleted` em `notification_providers.dart`.

**P-10-5 ✅** (falso alarme) — Estado das migrations 0013-0014 confirmado via snapshot — corpo de `cancel_job` com regra 24h e `auto_confirm_completed_jobs` presentes na BD viva.

**P-10-1 ✅** (falso alarme quanto ao conteúdo) — Corpo de `client_has_confirmed_job_with_worker` confirmado correto via `pg_get_functiondef` — inclui `jr.status IN ('confirmed', 'awaiting_confirmation', 'completed')`. **A ausência da função nas migrations continua aberta — ver P-FA1 em Crítico.**

---

### Revisão conceptual 2026-06-27

**RCB1 ✅** — `withdraw_help_acceptance` não validava estado do job: guarda adicionada em migration 0023.

**RCB2 ✅** — `cancel_job` não movia ajudantes aceites para estado terminal: `UPDATE help_acceptances SET status = 'cancelled' WHERE status = 'accepted'` adicionado em migration 0023.

**RCB3 ✅** — Texto enganoso em `job_reports`: "A nossa equipa vai rever o caso." substituído por "O teu relato fica registado para referência futura."

**RC1 ✅** — Estado de ajudante aceite quando job cancelado: Henrique decidiu reutilizar `'cancelled'` existente. Desbloqueou RCB2.

**RC3 ✅ RESOLVIDO 2026-06-27 (migration 0022)** — Ajudante vê logística do job em `_AcceptedCard`: data/hora confirmada, endereço tappable (Google Maps), botão WhatsApp para o prestador principal.

---

### Performance

**Optimizar `get_jobs_in_radius` para filtrar propostas do worker na BD ✅ implementado** — Parâmetro `p_worker_id` adicionado ao RPC com NOT EXISTS para excluir jobs onde o worker já tem proposta pending.

---

### Auditoria de docs — 2026-06-30

**P-FA1 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — `client_has_confirmed_job_with_worker` e policy `"Cliente ve perfil de worker com job confirmado"` ausentes de todas as migrations 0001–0026. Corrigidos em 0027: `CREATE OR REPLACE FUNCTION` + `DROP POLICY IF EXISTS`/`CREATE POLICY`. PK de `worker_profiles` é `profile_id` — policy usa `profile_id`, não `id`.

**P-67-2 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — `_syncServiceTypes` em `worker_repository.dart` substituído por chamada única ao RPC `sync_worker_service_types` (novo em 0027). DELETE + INSERT não atómicos eliminados; janela de ZERO serviços por falha de rede entre as duas chamadas fechada.

**P-FA5 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — Três índices criados: `idx_help_requests_job_id`, `idx_help_requests_proposal_id`, `idx_help_acceptances_worker_id`. Confirmados ausentes via live query (0 rows em `pg_indexes`). `help_acceptances.worker_id` era o mais urgente (avaliado pelo RLS em todas as queries à tabela).

**M3 Fases 4-5 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — Índice `idx_notifications_user_created ON notifications (user_id, created_at DESC)` criado. Agrupado com P-FA5 em 0027 por ser a mesma classe de fix.

**P-FA6 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — `help_acceptances.status` DEFAULT corrigido de `'accepted'` para `'pending'`. Confirmado via live query (`column_default = 'accepted'::text`). Rows existentes não afectadas.

**M5 Fases 4-5 ✅ RESOLVIDO 2026-06-30 (migration 0027 — APLICADA 2026-07-01)** — Policy SELECT do cliente em `help_requests` alargada a todos os estados dos seus jobs. Policy `"Cliente vê help requests pendentes de aprovação"` (migration 0003, apenas `pending_approval`) substituída por `"Cliente vê help requests dos seus jobs"`.

**`get_jobs_in_radius` overload antigo ✅ JÁ RESOLVIDO (migration 0011)** — Item em `improvements.md` estava STALE. `0011_drop_obsolete_get_jobs_in_radius.sql` já continha `DROP FUNCTION IF EXISTS get_jobs_in_radius(numeric, numeric, integer)`. Nenhuma acção em 0027.

**T6 (parcial) ✅ 2026-06-30** — 5 tipos de notificação com navegação precisa adicionados a `notification_handler.dart`: `newJobInRadius`, `proposalReceived`, `proposalWithdrawn`, `proposalAccepted` (async via `fetchAcceptedProposalForJob`), `proposalRejected`. `helpAccepted`/`helpJobCancelled` mantidos com `extra: {'initialTabIndex': 1}` (primitivo int — seguro). `helpRequestReopened` mantido com push para descoberta. Restam 7 tipos abertos: `jobCancelled`, `jobReopened`, `rescheduleProposed/Accepted/Rejected`, `jobMarkedDone`, `jobCompleted`.

---

## Como manter este ficheiro

- Sempre que aparecer uma ideia boa que **não cabe na fase atual**, adicionar aqui.
- Cada item: descrição curta + porquê + prioridade subjetiva.
- Quando uma ideia for implementada, mover para a secção **Resolvidos** e adicionar entrada em `decisions_log.md`.
