# LocalServices — Improvements & Future Ideas

> Lista viva de ideias, melhorias e features que NÃO entram na fase atual mas
> ficam registadas para não se perderem. Sempre que aparecer uma ideia boa que
> não cabe no momento, adicionar aqui em vez de esquecer.
>
> Cada item: descrição curta, contexto/porquê, e prioridade subjetiva.

---

> **Revalidação 2026-06-26 (atualizado sessão 4):** Esta série de auditorias foi revalidada contra um snapshot direto da BD viva (`schema_snapshot_2026-06-26.csv`, já apagado), migration 0016 (P-8-4 parcial + P-FA4), migration 0017 (P-9-1 + reestruturação lobby) e migration 0018 (P-FA3 — avatar UPDATE/DELETE policies). Itens confirmados stale, parcialmente resolvidos, ou totalmente resolvidos foram removidos ou movidos para o apêndice no final desta série. **Itens abertos: 24** (25 após sessão 3 → −1: P-FA3).

---

## 🔍 Auditoria 2026-06-25 — Fases 0-3 (a atacar em breve)

> Resultado da revisão independente de Fases 0-3 feita em 2026-06-25.
> Itens numerados com códigos estáveis (P1-P8, A1-A3, M1-M6, B1-B4) para
> referência futura sem re-derivar a análise. Nenhum ficheiro .dart foi
> alterado nesta sessão — só documentação.

### Problemas encontrados

**P1 — JobStatus color-label map duplicada 4× com inconsistências**
A mesma lógica "JobStatus → (label, Color)" está implementada independentemente em 4 lugares:
- `lib/features/client/presentation/client_home_screen.dart:227` — `_statusChip()`, label para `open`: **"À espera"**
- `lib/features/jobs/presentation/client_jobs_screen.dart:183` — `_statusChip()`, label para `open`: **"À espera de proposta"** ← inconsistente
- `lib/features/jobs/presentation/client_job_detail_screen.dart:1063` — `_statusInfo()`, label para `open`: **"À espera de proposta"**
- `lib/features/help_requests/presentation/worker_help_requests_screen.dart:353` — `_jobStatusDisplay(String)` — opera em **strings brutas** em vez do enum `JobStatus`; `open` e `no_response` caem no wildcard `'Em aberto'`; não tem exaustividade garantida pelo compilador

Consequências: label inconsistente em dois ecrãs de alta visibilidade; ao adicionar um novo `JobStatus`, as 3 versões enum serão apanhadas pelo compilador mas a versão string não.

**P2 — Cores hex hardcoded divergentes do seed do tema**
- `lib/core/router/app_router.dart:44` — `Color(0xFF2E7D32)` para o spinner de loading. Duplica `AppTheme._seed` mas não está ligado a ele — se a cor da marca mudar, o spinner fica verde.
- `lib/core/widgets/status_timeline.dart:118` — `Color(0xFF43A047)` para o círculo "done". É um verde **diferente** do seed (`0xFF2E7D32`). Os dois hex são suficientemente próximos para passar na revisão visual mas divergirão com qualquer ajuste de tema ou modo escuro.

**P3 — `Colors.orange` usado para semânticas diferentes sem mapeamento no tema**
`Colors.orange.shade700` aparece nos chips de urgência, no badge de "propostas pendentes", no banner de "remarcação pendente", e em ícones de notificação — de features diferentes, sem token semântico partilhado. O Material 3 já gera `colorScheme.tertiary` (warning/accent) e `colorScheme.error` (destrutivo) a partir do seed, mas nenhum ecrã os usa; todos acedem a `Colors.orange` diretamente.

**P4 — Wildcard em `_HistoryCard._statusLabel` silencia 2 casos válidos do enum**
`lib/features/help_requests/presentation/worker_help_requests_screen.dart:509`:
```dart
String get _statusLabel => switch (acceptance.status) {
  HelpAcceptanceStatus.rejected  => 'Não selecionado',
  HelpAcceptanceStatus.cancelled => 'Desististe',
  _ => '—',  // silencia .pending e .accepted
};
```
Hoje está seguro porque o filtro upstream (linha 280-281) só envia `rejected | cancelled` para o separador de histórico. Mas o wildcard significa: (a) se o filtro mudar, `pending`/`accepted` mostram `'—'` sem aviso de compilação; (b) um novo valor no enum também cairia silenciosamente no wildcard.

**⚠️ P6 — 4 rotas crasham em navegação direta por usarem `state.extra!` sem fallback (CRÍTICO — bloqueia deep linking)**
Estas rotas fazem `state.extra!` (null assertion) no builder:

| Rota | Ficheiro:linha | Tipo de extra |
|---|---|---|
| `/client/job/:id` | `app_router.dart:73` | `JobRequest` |
| `/worker/job/:id` | `app_router.dart:92` | `JobRequest` |
| `/worker/my-job/:id` | `app_router.dart:104` | `Map<String, dynamic>` |
| `/worker/job/:id/help-requests` | `app_router.dart:113` | `Map<String, dynamic>` |

Navegação direta (deep link, back/forward do sistema, ou acesso cross-role de P5) lança `Null check operator used on a null value` antes de o ecrã renderizar. Deep links para qualquer job individual são impossíveis enquanto este padrão persistir.

**P7 — `architecture.md` tem diagrama de pastas obsoleto**
O diagrama em `docs/architecture.md` lista `ratings/` (não existe — Fase 11 por implementar) mas omite `notifications/` (totalmente implementado, com estrutura própria `data/`, `application/`, `presentation/`). Um novo developer que leia o diagrama vai à procura de uma pasta inexistente e não encontra a que existe.

**P8 — `worker_setup_screen.dart` chama Supabase direto no widget, viola `architecture.md` Princípio #2**
`lib/features/worker/presentation/worker_setup_screen.dart:178`:
```dart
final profileData = await ref
    .read(supabaseClientProvider)
    .from('profiles')
    .select('full_name, phone')
    .eq('id', currentUser.id)
    .single();
```
Chamada direta ao Supabase dentro de um `ConsumerStatefulWidget`. `architecture.md` Princípio #2 diz explicitamente: *"Nunca chamar Supabase diretamente dentro de widgets."* É a única violação encontrada — mas cria um precedente se não for corrigida antes de a equipa crescer.

---

### Melhorias — Alta prioridade

**A1 — Centralizar `JobStatus` → `(String label, Color color)` numa extension única (resolve P1)**
Criar uma extension `StatusDisplay` em `JobStatus` (em `core/constants/` ou `core/widgets/`) com um único switch exaustivo que devolve label e cor. Todos os ecrãs chamam `status.displayInfo(proposalCount)`. Resolve simultaneamente:
- A inconsistência "À espera" / "À espera de proposta"
- ~100 linhas de duplicação (4 implementações → 1)
- A versão raw-string em `worker_help_requests_screen.dart` que não tem exaustividade

**A2 — Substituir navigation-extra por ID-based routing nos ecrãs de detalhe (resolve causa raiz dos bugs de `/choose-role` de hoje E P6; maior impacto estrutural do relatório)**
O padrão atual passa objetos ricos em `state.extra`. O padrão correto go_router + Riverpod:
```dart
// Route: /client/job/:id — sem extra
builder: (_, state) => ClientJobDetailScreen(jobId: state.pathParameters['id']!),

// Ecrã: faz fetch via provider (já existe jobByIdProvider)
final jobAsync = ref.watch(jobByIdProvider(widget.jobId));
```
Elimina **toda a classe** de bugs "extra perdido durante redirect" (incluindo o bug `/choose-role` que foi corrigido hoje com um workaround no redirect). Habilita deep links para todos os ecrãs de detalhe. Resolve P6. O refactor toca 4 rotas e os ecrãs correspondentes; os providers necessários (`jobByIdProvider`, `proposalByIdProvider`) já existem e são usados em `notification_handler.dart`.

**A3 — `PendingSignupStateProvider` para eliminar definitivamente o risco de perda de dados no `/choose-role` (complementa A2)**
Mesmo com o fix de redirect atual, `fullName`/`phone` continuam a ser passados como `state.extra` para `/choose-role`. Se qualquer futura alteração ao router criar um novo caminho de redirect através de `/choose-role`, os dados voltam a perder-se.

Solução robusta: um `StateProvider<PendingSignupState?>` na camada `auth/application/`. O `SignupScreen` escreve para ele antes de navegar; o `ChooseRoleScreen` lê dele. O extra de navegação deixa de ser load-bearing. Combinado com A2, fecha permanentemente a classe de "state de navegação perdido durante redirect do router".

---

### Melhorias — Média prioridade

**M1 — Tokens de cor semânticos no AppTheme usando o ColorScheme do Material 3 já gerado**
O Material 3 já gera `theme.colorScheme.tertiary` (warning/accent) e `theme.colorScheme.error` (destrutivo) a partir do seed. Os ecrãs devem usar:
- `theme.colorScheme.error` em vez de `Colors.red` nos SnackBars de erro
- `theme.colorScheme.tertiary` em vez de `Colors.orange.shade700` para estados pending/warning
Resolve P3. Nenhuma nova cor precisa de ser definida — o Material 3 já as calcula.

**M2 — Expor `AppTheme.seed` como `static const` e referenciar em `app_router.dart` (resolve P2)**
Mudar `_seed` para `seed` em `AppTheme` (torná-lo público) e substituir `Color(0xFF2E7D32)` em `app_router.dart:44` por `AppTheme.seed`. Um ficheiro, uma linha, elimina a divergência de P2.

**M4 — Constantes de border radius no AppTheme**
Três valores aparecem repetidamente: `8` (~8 ocorrências), `12` (~12 ocorrências), `16` (~4 ocorrências). Adicionar:
```dart
static const double radiusSmall  = 8;
static const double radiusMedium = 12;
static const double radiusLarge  = 16;
```
Uma futura alteração de corner radius passa de ~24 ficheiros para 1 ficheiro.

**M5 — Documentar setup de `--dart-define` para novos contribuidores em `project_overview.md`**
O `decisions_log.md` regista a *decisão* (entrada 2026-06-02) mas não dá instruções de setup. Um novo developer precisa de:
1. Saber que existe um `.vscode/launch.json` gitignored
2. Saber o esqueleto exato do ficheiro com os campos `SUPABASE_URL` e `SUPABASE_ANON_KEY`
3. Saber onde obter os valores (dashboard Supabase)

Nenhum destes passos está documentado em `project_overview.md` ou `architecture.md`. Adicionar uma secção "Setup de desenvolvimento" com o esqueleto do `launch.json` e referência ao dashboard elimina este friction point.

**M6 — Atualizar diagrama de pastas em `architecture.md` (resolve P7)**
- Adicionar `notifications/` à lista de features
- Anotar `ratings/` como `# Fase 11 — não implementado`
Mudança de 2 linhas, diagrama passa a ser fidedigno.

---

### Melhorias — Baixa prioridade

**B1 — Boilerplate de enums: não vale code-gen a esta escala (decisão, não ação)**
9 enums × ~6-15 linhas de `value`/`fromValue` = ~100 linhas de boilerplate total. Code-gen (json_serializable, freezed) adicionaria build_runner e indireção para um ganho mínimo. O Dart built-in `.name` cobre enums com valor igual ao identifier; para os com underscore (`awaitingConfirmation → 'awaiting_confirmation'`) o getter manual é mais legível do que qualquer abstração. **Decisão: manter o boilerplate.** O compilador já apanha casos em falta nos switches de expressão — o principal benefício do code-gen está coberto.

**B2 — Partilha estrutural entre `ClientShell`/`WorkerShell`: não vale ainda (decisão, não ação)**
Os dois shells têm tabs, ícones, FAB logic e contagens de destinos suficientemente diferentes para que um `GenericShell(tabs: [...])` fique tão complexo quanto a separação atual. **Decisão: manter separados.** O momento certo para extrair é quando surgir um terceiro shell (e.g. role admin) ou comportamento partilhado (e.g. banner global). Nenhum está no roadmap.

**B3 — Tornar exaustivo o switch de `_HistoryCard._statusLabel` (resolve P4)**
Substituir `_ => '—'` por casos explícitos para `pending` e `accepted`:
```dart
HelpAcceptanceStatus.pending  => 'Pendente',   // não deve aparecer aqui
HelpAcceptanceStatus.accepted => 'Aceite',     // não deve aparecer aqui
```
Sem comportamento visível hoje (filtro upstream garante que não chegam). O ganho é que um novo valor no enum passa a ser um erro de compilação em vez de um wildcard silencioso.

**B4 — Mover chamada Supabase de `worker_setup_screen.dart` para o repository (resolve P8)**
Mover o `from('profiles').select('full_name, phone')` de `worker_setup_screen.dart:178` para um método `fetchBasicProfile(userId)` no `WorkerRepository` ou `ClientRepository`. Restaura a invariante de architecture.md e remove o único ponto de contacto direto com Supabase dentro de um widget.

---

> **Nota:** Esta auditoria cobre só Fases 0-3. A auditoria de Fases 4-5 foi
> adicionada na secção seguinte (mesma sessão, 2026-06-25). Auditorias para
> Fases 6-7, 8, 9 e 10 podem ser adicionadas como secções próprias.

---

## 🔍 Auditoria 2026-06-25 — Fases 4-5 (a atacar em breve)

> Resultado da revisão independente de Fases 4-5 (Supabase config, schema,
> RLS para todas as 13 tabelas, migrations 0001-0014, storage, índices) feita
> em 2026-06-25. Itens numerados com códigos estáveis (P-FA1–P-FA8, A1–A4,
> M1–M6, B1–B4) para referência futura sem re-derivar a análise.
>
> ⚠️ **MAIS URGENTE DESTA AUDITORIA: P-FA1** — `client_has_confirmed_job_with_worker` e policy associada ausentes de todas as migrations. BD não reproduzível sem ela. (P-FA3 resolvido em migration 0018 — 2026-06-26.)

### Problemas encontrados

**P-FA1 — `client_has_confirmed_job_with_worker` existe na BD viva mas ausente de todas as migrations**

A função existe na BD viva com corpo correto (`jr.status IN ('confirmed', 'awaiting_confirmation', 'completed')`) — confirmado via snapshot 2026-06-26 (`pg_get_functiondef`). A policy `"Cliente ve perfil de worker com job confirmado"` em `worker_profiles` referencia-a — também confirmada presente via snapshot. Nenhuma das migrations 0001–0014 contém a função nem a policy.

**Acção necessária:** criar migration nova com a definição da função + a policy (ver A1 desta auditoria). Sem este fix, uma BD nova a partir das migrations não teria nem a função nem a policy — contactos de worker ficariam sempre invisíveis ao cliente.

---

**P-FA2 — Storage DELETE policy de `job-photos` é não-funcional**

Policy em 0001:
```sql
CREATE POLICY "job-photos: delete pelo dono"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'job-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
```

Path de upload em `job_repository.dart:70`: `'$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg'`

`storage.foldername(name)[1]` extrai o primeiro componente do path, que é o `job_id` (UUID) — não o `auth.uid()` (também UUID mas diferente). `auth.uid()::text = job_id::text` é sempre falso. Ninguém consegue apagar fotos de jobs via esta policy. A app não tem feature de apagamento de fotos → sem impacto runtime, mas é dead code de segurança que documenta uma garantia que não cumpre.

---

**P-FA5 — Índices em falta em `help_requests` e `help_acceptances`**

Nenhum índice existe em:

| Coluna | Usada em | Impacto |
|---|---|---|
| `help_requests.job_id` | `fetchHelpRequestsForJob` WHERE; JOIN em `get_help_requests_in_radius` | Sequential scan de all help_requests por lobby load |
| `help_requests.proposal_id` | JOIN em `get_help_requests_in_radius`; `is_principal_worker_for_help_request` | Sequential scan no JOIN |
| `help_acceptances.worker_id` | `get_my_help_acceptances` WHERE; RLS USING "Worker vê as suas candidaturas" | **Sequential scan por cada query à tabela** (avaliado pelo RLS em todas as queries) |

O UNIQUE constraint `(help_request_id, worker_id)` em `help_acceptances` cobre lookups com `help_request_id` como prefixo esquerdo — `fetchCandidatesForHelpRequest` está coberto. Lookups só por `worker_id` (sem `help_request_id`) não usam este índice.

`help_acceptances.worker_id` é o mais urgente: é avaliado pelo RLS em **todas** as queries à tabela, não só nas queries explícitas da app.

---

**P-FA6 — `help_acceptances.status` tem DEFAULT `'accepted'` na BD, contradiz a RLS de INSERT**

A RLS de INSERT (migration 0004): `WITH CHECK (worker_id = auth.uid() AND status = 'pending')`.

Qualquer INSERT que omita `status` recebe o default `'accepted'`, o que falha imediatamente no `WITH CHECK` — silenciosamente bloqueado (sem erro visível, só count=0). O default correto seria `'pending'`. O default `'accepted'` predata a migration 0004 (que introduziu o conceito de `pending`). Nenhuma migration posterior corrigiu o default.

---

**P-FA7 — `job_photos` (tabela) sem policy de DELETE — dois bloqueios separados para a mesma feature futura**

A tabela `job_photos` tem INSERT e SELECT mas sem DELETE policy. O bucket `storage.objects` tem uma DELETE policy (quebrada — P-FA2). Se a feature de apagamento de fotos for alguma vez implementada, existem dois bloqueios independentes:
1. Storage: DELETE policy não-funcional (job_id em vez de auth.uid() — P-FA2)
2. Tabela: sem DELETE policy — linha da tabela fica órfã mesmo que o ficheiro fosse removido do storage

Não é bug ativo (a app não apaga fotos). Flag para garantir que ambos são resolvidos juntos quando esta feature for implementada.

---

**P-FA8 — `cancel_job` reproduzido por completo em 4 migrations sem a 24h rule nas 3 mais antigas**

O corpo completo de `cancel_job` aparece em 0001, 0007, 0009 e 0013. As versões 0001/0007/0009 não têm a 24h rule (introduzida em 0013) — correto por design (cada migration só reproduz o estado daquele momento). A versão autoritativa é sempre a última (0013). Mas um leitor que leia 0007 antes de 0013 pode perder as mudanças de 0009 (loop de notificações `help_job_cancelled`). É um comprehension hazard crescente, não um bug runtime.

---

### Melhorias — Alta prioridade

**A1 — Adicionar `client_has_confirmed_job_with_worker` a uma migration (resolve P-FA1)**

Confirmado via snapshot 2026-06-26: a policy `"Cliente ve perfil de worker com job confirmado"` em `worker_profiles` referencia a função. Criar migration 0015 com:
1. `CREATE OR REPLACE FUNCTION client_has_confirmed_job_with_worker(p_worker_id uuid) RETURNS boolean...` — corpo completo em `database_schema.md` secção "Funções internas"
2. `DROP POLICY IF EXISTS "Cliente ve perfil de worker com job confirmado" ON worker_profiles; CREATE POLICY...` — texto actual da policy em `database_schema.md` secção RLS

Sem este fix, a BD não é reproduzível a partir das migrations.

**A3 — Corrigir path de storage de `job-photos` e policy de DELETE (resolve P-FA2 + P-FA7)**

Opção A (recomendada — mais simples que alterar a policy):
Alterar o path em `job_repository.dart:70` de:
```dart
final storagePath = '$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg';
```
para:
```dart
final storagePath = '$clientId/$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg';
```
Com este path, `storage.foldername(name)[1]` = `clientId`, e a policy de storage já funciona. Adicionar também uma DELETE policy na tabela `job_photos`:
```sql
CREATE POLICY "Client apaga fotos do seu job"
  ON job_photos FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE id = job_photos.job_id
        AND client_id = auth.uid()
    )
  );
```

Opção B (mudar a policy para usar subquery) requer JOIN entre `storage.objects` e `public.job_requests`, o que não é suportado nativamente em storage policies — descartada.

---

### Melhorias — Média prioridade

**M1 — Índices em `help_requests` e `help_acceptances` (resolve P-FA5)**

```sql
CREATE INDEX IF NOT EXISTS idx_help_requests_job_id
  ON help_requests (job_id);

CREATE INDEX IF NOT EXISTS idx_help_requests_proposal_id
  ON help_requests (proposal_id);

CREATE INDEX IF NOT EXISTS idx_help_acceptances_worker_id
  ON help_acceptances (worker_id);
```

Ordem de prioridade: `help_acceptances.worker_id` (afeta RLS de cada query à tabela) > `help_requests.job_id` (lobby screen + JOIN do RPC) > `help_requests.proposal_id` (só JOIN do RPC, volume menor).

**M2 — Corrigir DEFAULT de `help_acceptances.status` para `'pending'` (resolve P-FA6)**

```sql
ALTER TABLE help_acceptances ALTER COLUMN status SET DEFAULT 'pending';
```

Sem data migration — rows existentes não são afetadas. Torna o schema self-documenting e elimina silenciosa rejeição por RLS em INSERTs sem `status` explícito.

**M3 — Índice composto `notifications(user_id, created_at DESC)` para queries ordenadas**

Todas as queries de notificações em `notification_repository.dart` fazem ORDER BY `created_at DESC`. O índice atual `idx_notifications_user_id` cobre o filtro mas o Postgres ainda precisa de ordenar o resultado. Um índice composto permite um true index scan:
```sql
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_id, created_at DESC);
```
O índice `idx_notifications_user_read` (para contagem de não-lidas) continua útil e não conflitua.

**M4 — CHECK constraints em `people_needed` e `slots_needed` (integridade de dados)**

Sem estes CHECKs, `accept_proposal` pode calcular `slots_needed = people_needed - 1 = -1` se `people_needed = 0` chegar à BD, criando uma help_request com `slots_needed` negativo (imediatamente considerada "filled"):
```sql
ALTER TABLE job_proposals
  ADD CONSTRAINT check_people_needed CHECK (people_needed >= 1);

ALTER TABLE help_requests
  ADD CONSTRAINT check_slots_needed CHECK (slots_needed >= 1);
```

**M5 — Policy SELECT mais ampla para o cliente em `help_requests` (fecha C3.2 do backlog da Fase 9)**

Atualmente só `pending_approval` rows são visíveis ao cliente (policy da migration 0003). Qualquer ecrã futuro "ver equipa" (help_requests em `open`/`filled`) retornaria vazio silenciosamente. Fix proactivo:
```sql
-- Dropar a policy narrow de pending_approval:
DROP POLICY IF EXISTS "Cliente vê help requests pendentes de aprovação" ON help_requests;

-- Substituir por policy que cobre todos os estados para jobs do cliente:
CREATE POLICY "Cliente vê help requests dos seus jobs"
  ON help_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM job_requests
      WHERE id = help_requests.job_id
        AND client_id = auth.uid()
    )
  );
```

O fluxo de aprovação (`approve_help_request` RPC) já valida que o cliente é dono do job — a policy mais ampla não altera o comportamento dos RPCs.

**M6 — Coluna "Migration atual" na tabela de RPCs do `database_schema.md`**

`cancel_job` tem corpo completo em 4 migrations; `accept_proposal` em 2; `create_proposal` em 3. Não é óbvio qual é a versão autoritativa sem ler todas. Adicionar uma coluna "Definido/atualizado em" à tabela de RPCs em `database_schema.md` para navegação direta à versão atual.

---

### Melhorias — Baixa prioridade

**B1 — Reproduções completas de `cancel_job` em 4 migrations: sem ação agora**

Sem ação agora — o padrão de reproduzir o corpo completo em cada migration é correto e self-contained. Se o número de migrations passar de 20, considerar `supabase/FUNCTION_HISTORY.md` que mapeie cada função → migration mais recente que a tocou.

**B2 — Policy "Sistema insere notificações": inconsistência docs-vs-baseline**

O 0001_baseline cria:
```sql
CREATE POLICY "Sistema insere notificações"
  ON notifications FOR INSERT TO service_role
  WITH CHECK (true);
```
Mas `database_schema.md` diz: *"Não existe uma política 'Sistema insere notificações' na BD viva."*

A policy é funcionalmente harmless (funções SECURITY DEFINER bypassam RLS independentemente), mas a inconsistência é confusa para quem audite o fluxo de INSERT de notificações. Resolver: atualizar `database_schema.md` para refletir que a policy é criada pelo 0001 mas redundante, ou fazer DROP explícito numa migration com comentário explicativo.

**B3 — Remover coluna legacy `job_proposals.estimated_hours`**

Coluna nullable que predata o split min/max (2026-06-11). Não mapeada em `JobProposal.fromJson` — ignorada silenciosamente. Aproveitar a migration da Fase 11 (ratings) para o drop:
```sql
ALTER TABLE job_proposals DROP COLUMN IF EXISTS estimated_hours;
```

**B4 — CHECK `(hourly_rate >= 0)` em `job_proposals`**

`job_proposals.hourly_rate` é NOT NULL mas sem CHECK. Seguir o padrão já estabelecido pelo `check_agreed_rate` em `help_acceptances` (migration 0007):
```sql
ALTER TABLE job_proposals
  ADD CONSTRAINT check_hourly_rate CHECK (hourly_rate >= 0);
```
Usar `>= 0` (não `> 0`) para permitir "negociar no local" como sinal explícito, se necessário.

---

> **Nota:** Esta auditoria cobre Fases 4-5. A auditoria de Fases 6-7 foi
> adicionada na secção seguinte (mesma sessão, 2026-06-25).
> ⚠️ Item mais urgente de toda a auditoria até agora: **P-FA3** — policy de
> avatars quebrada desde o dia 1, fix só na BD viva (nunca capturado em migration).

---

## 🔍 Auditoria 2026-06-25 — Fases 6-7 (a atacar em breve)

> Resultado da revisão independente de Fases 6-7 (fluxos de auth, ecrãs de
> perfil de cliente e worker, SessionNotifier, RouterNotifier.redirect())
> feita em 2026-06-25, imediatamente após 2 bugs reais terem sido encontrados
> e corrigidos nestas mesmas áreas. Itens numerados com códigos estáveis
> (P-67-1–P-67-6, A1–A3, M1–M4, B1–B4) para referência futura.
>
> ⚠️ **MAIS URGENTE: P-67-1** — `/worker/setup` ausente de `loadingExempt`,
> mesma classe estrutural do Bug 2 corrigido hoje, com risco real de perda de
> dados em produção (formulário apagado silenciosamente sem erro).

### Problemas encontrados

**P-67-2 — `worker_service_types` sync não é atómico (DELETE + INSERT como 2 chamadas PostgREST separadas, sem transação). Se o INSERT falhar depois do DELETE ter sucesso, o worker fica com ZERO serviços permanentemente até reabrir e regravar manualmente.**

`worker_repository.dart:88`:
```dart
Future<void> _syncServiceTypes(String workerId, List<String> serviceTypeIds) async {
  await _client.from('worker_service_types').delete().eq('worker_id', workerId);
  if (serviceTypeIds.isNotEmpty) {
    await _client.from('worker_service_types').insert(
      serviceTypeIds.map((id) => {'worker_id': workerId, 'service_type_id': id}).toList(),
    );
  }
}
```

Duas chamadas PostgREST sem transação. Se o DELETE suceder e o INSERT falhar (erro de rede, connection reset, rate limit Supabase):

- Para `updateProfile` (worker a editar perfil): worker fica com ZERO serviços. O utilizador vê o SnackBar "Ocorreu um erro inesperado." mas não sabe que os serviços foram apagados. Se navegar sem tentar de novo: invisível na descoberta, sem notificações de jobs, sem erro mostrado. Pode não notar durante dias.
- Para `createProfile` (worker setup pela primeira vez): `hasProfile()` devolve `true` (worker_profiles upsertado com sucesso) → `workerProfileComplete = true` → worker chega a `/worker/home` com ZERO service types. Invisível na descoberta desde o primeiro instante, sem erro nenhum mostrado.

PostgREST REST API não suporta transações multi-statement. O único fix correto é um RPC SECURITY DEFINER que envolve DELETE + INSERT numa transação PL/pgSQL única.

---

**P-67-3 — `client_profile_screen.dart` mostra texto de exceção em bruto no SnackBar de erro — única tela que não usa `friendlyError(e)`, todas as outras usam consistentemente.**

```dart
// client_profile_screen.dart:97 — em bruto:
SnackBar(content: Text('Erro ao guardar: $e'), backgroundColor: Colors.red)

// Todas as outras telas — correto:
SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red)
```

Se `updateProfile` falhar, o utilizador vê texto como `"Erro ao guardar: PostgrestException(message: ERROR: null value in column..., code: 23502, details: ..., hint: ...)"`. `error_utils.dart` já está importado no mesmo ficheiro (via o handler `error:` em baixo).

---

**P-67-4 — Mesmo problema (P-67-3) no widget de erro de service types em `worker_setup_screen.dart` E `worker_profile_screen.dart`.**

```dart
// worker_setup_screen.dart:384
error: (e, _) => Text('Erro ao carregar serviços: $e'),

// worker_profile_screen.dart:452
error: (e, _) => Text('Erro ao carregar serviços: $e'),
```

Texto de exceção em bruto no widget tree, visível inline no formulário se o fetch de `fetchServiceTypes` falhar. Ambos os ficheiros já importam `error_utils.dart`.

---

**P-67-5 — `worker_setup_screen.dart` usa `.single()` em vez de `.maybeSingle()` ao buscar o perfil — lança `PGRST116` se a linha `profiles` estiver ausente (signup parcialmente falhado). Também é o mesmo local do P8 da auditoria de Fases 0-3 (chamada Supabase direta no widget).**

```dart
// worker_setup_screen.dart:178
final profileData = await ref
    .read(supabaseClientProvider)
    .from('profiles')
    .select('full_name, phone')
    .eq('id', currentUser.id)
    .single();  // lança PGRST116 se não encontrar linha
```

`.single()` lança `PostgrestException` (PGRST116) se não encontrar linha. No fluxo normal não acontece, mas num signup parcialmente falhado (conta auth criada, INSERT em profiles falhou) o utilizador não consegue completar o setup e vê "Ocorreu um erro inesperado." sem indicação do que fazer. `.maybeSingle()` com null check dá uma mensagem acionável.

---

**P-67-6 — `_mapError` não trata o erro "email não confirmado" — não é bug agora (verificação de email está desativada para o MVP), mas é um bloqueador de pré-lançamento fácil de esquecer quando a verificação for reativada.**

`decisions_log.md 2026-06-05`: *"Confirmação de email Supabase desativada para MVP — reativar antes do launch."*

Quando a verificação for reativada, utilizadores que tentem fazer login antes de confirmar o email recebem um erro do Supabase (`email_not_confirmed`) que `_mapError` em `auth_controller.dart` não reconhece → fallback `"Ocorreu um erro. Tenta novamente."` sem indicar que devem verificar o email. `_mapError` também não trata `rate_limit_exceeded`.

---

### Melhorias — Alta prioridade

**A2 — Corrigir SnackBar de `client_profile_screen.dart` para usar `friendlyError(e)` (resolve P-67-3, 2 min)**

```dart
// Antes (linha 99):
content: Text('Erro ao guardar: $e'),

// Depois:
content: Text(friendlyError(e)),
```

`error_utils.dart` já está importado. Uma linha.

**A3 — Criar RPC `sync_worker_service_types` (SECURITY DEFINER) para tornar o delete-then-insert atómico (resolve P-67-2, ~30 min)**

```sql
CREATE OR REPLACE FUNCTION sync_worker_service_types(
  p_worker_id        uuid,
  p_service_type_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM worker_service_types WHERE worker_id = p_worker_id;
  IF array_length(p_service_type_ids, 1) IS NOT NULL
     AND array_length(p_service_type_ids, 1) > 0 THEN
    INSERT INTO worker_service_types (worker_id, service_type_id)
    SELECT p_worker_id, unnest(p_service_type_ids);
  END IF;
END;
$$;
```

Depois substituir `_syncServiceTypes` no `worker_repository.dart` por uma única chamada RPC. Todo o delete-then-insert passa a ser atómico ao nível da BD. Esforço: nova migration + alteração no repository Dart.

---

### Melhorias — Média prioridade

**M1 — Corrigir texto de erro em bruto nos 2 widgets de service types (resolve P-67-4, 2 linhas no total)**

```dart
// worker_setup_screen.dart:384 e worker_profile_screen.dart:452
// Antes:
error: (e, _) => Text('Erro ao carregar serviços: $e'),

// Depois:
error: (e, _) => Text('Erro ao carregar serviços: ${friendlyError(e)}'),
```

Ambos os ficheiros já importam `error_utils.dart`.

**M2 — Adicionar tratamento de "email não confirmado" e "rate limit" a `_mapError` (resolve P-67-6, bloqueador de pré-lançamento, 5 min)**

Adicionar antes do fallback genérico em `auth_controller.dart`:
```dart
if (msg.contains('email not confirmed') || msg.contains('email_not_confirmed')) {
  return 'Confirma o teu email antes de entrar. Verifica a tua caixa de entrada.';
}
if (msg.contains('too many requests') || msg.contains('rate_limit') ||
    msg.contains('over_request_rate_limit')) {
  return 'Demasiadas tentativas. Aguarda alguns minutos e tenta novamente.';
}
```

Necessário antes de reativar a verificação de email (pré-lançamento).

**M3 — Substituir `.single()` por `.maybeSingle()` em `WorkerSetupScreen._save()` com mensagem de erro acionável (resolve P-67-5 parcialmente; fix completo é mover para o repository, ~30 min)**

```dart
// Antes:
.single();
final existingName = profileData['full_name'] as String;

// Depois:
.maybeSingle();
if (profileData == null) {
  throw Exception('Perfil de utilizador não encontrado. Tenta fazer login novamente.');
}
final existingName = profileData['full_name'] as String;
```

Fix completo: mover este fetch para `WorkerRepository.fetchBasicProfile(userId)` — resolve também P8 da auditoria de Fases 0-3 (chamada Supabase direta no widget).

**M4 — `PendingSignupStateProvider` — `StateProvider<PendingSignupData?>` na camada de auth, substitui o uso de navigation extra para `fullName`/`phone` entre `SignupScreen` e `ChooseRoleScreen`. Resolve a CAUSA RAIZ de toda a classe de bugs "dados perdidos em redirect".**

Os 2 bugs corrigidos hoje são instâncias da mesma classe: dados de aplicação guardados em `state.extra` do router em vez de estado Riverpod. `state.extra` é transitório por design e descartado em qualquer navegação iniciada pelo próprio router — o que acontece sempre em fluxos de auth.

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

`SignupScreen` escreve para o provider antes de `context.go('/choose-role')`. `ChooseRoleScreen` lê do provider em vez de `widget.fullName`/`widget.phone`. Após `createProfile` ter sucesso, o provider é reset para null.

`loadingExempt` fica como otimização de UX (sem flash), não como requisito de correção. Qualquer ecrã de onboarding futuro está protegido automaticamente.

**Esforço: ~1.5h** (novo provider + atualizar SignupScreen + atualizar ChooseRoleScreen + testar fluxo de signup).

---

### Melhorias — Baixa prioridade

**B1 — Validação de email com regex mínimo em vez de só `contains('@')`**

Em `signup_screen.dart` e `login_screen.dart`, `!v.contains('@')` aceita `@`, `test@@`, `a@`. O Supabase rejeita emails inválidos ao nível do servidor, mas o feedback chega mais tarde. Substituir por:
```dart
if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
  return 'Email inválido.';
}
```
Sem pacotes adicionais. O servidor continua a ser a gate real.

**B2 — Validação de tamanho mínimo no telefone (números inválidos quebram o link `wa.me` usado para contacto WhatsApp)**

Todos os ecrãs de signup e perfil validam o telefone como "não vazio". Um valor como `"1"` ou `"abc"` passa e fica guardado. O link WhatsApp é construído com `wa.me/<número limpo>` — número inválido = link quebrado. Adicionar no mínimo:
```dart
final digits = v!.trim().replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
if (digits.length < 9) return 'Número de telefone inválido.';
```

**B3 — Indicador de loading específico para a fase de upload de avatar (separado do `_saving` genérico)**

Ambos os ecrãs de perfil usam `_saving = true` para todo o ciclo save (upload avatar + update BD). O upload pode demorar 1-5s numa ligação móvel fraca. Sem indicação específica, utilizadores podem pensar que a app travou e tentar de novo. Um estado `_uploadingAvatar` separado com texto "A carregar foto..." melhora o feedback sem alterar a lógica de negócio.

**B4 — Mesmo que M2, registado aqui como item de checklist de pré-lançamento**

Antes de reativar a verificação de email Supabase (obrigatório pré-lançamento, ver `decisions_log.md 2026-06-05`): confirmar que M2 está implementado. Sem este item, utilizadores que tentem fazer login antes de confirmar o email veem "Ocorreu um erro. Tenta novamente." sem saber porquê.

---

### Nota da sessão

Pergunta colocada no prompt original: existe uma mudança estrutural que previna esta CLASSE de bug? Resposta: sim — M4 (`PendingSignupStateProvider`).

A causa raiz dos 2 bugs corrigidos hoje é guardar dados de aplicação em `state.extra` do router em vez de estado Riverpod. `state.extra` é transitório por design e descartado em qualquer navegação iniciada pelo próprio router — o que acontece sempre em fluxos de auth. M4 resolve isto de forma permanente para qualquer ecrã de onboarding futuro, não só os 2 já corrigidos.

`loadingExempt` fica como otimização de UX (sem flash visível), não como requisito de correção — a distinção é importante para perceber o que é workaround vs. fix estrutural.

---

## 🔍 Auditoria 2026-06-25 — Fase 8 (a atacar em breve)

> Resultado da revisão independente da Fase 8 (ciclo de vida de jobs e
> propostas, remarcação, conclusão, timeline de estados, fotos, notificações)
> feita em 2026-06-25, após a code review dedicada, o crosscheck BD/docs/código,
> e as adições de cancellation handling já aplicadas. Itens numerados com
> códigos estáveis (P-8-1–P-8-9, A1–A3, M1–M4, B1–B4) para referência futura.

### Problemas encontrados

**P-8-1 — Transição `open → no_response` NUNCA implementada — jobs sem propostas ficam abertos indefinidamente**

`implementation_plan.md:84` tem este item **não marcado**:
```
- [ ] Estado expira_at + job `no_response` após 48h (cron Supabase ou função).
```

A coluna `expires_at` existe na BD. A UI está pronta para este estado (`job_timeline.dart:25` renderiza "Sem resposta em 48h"; `client_jobs_screen.dart:44` inclui `JobStatus.noResponse` no histórico). Mas nenhum cron, trigger ou RPC em nenhuma migration (0001–0014) muda `status = 'no_response'` quando `expires_at` passa. Jobs sem propostas ficam `open` indefinidamente e continuam a aparecer em `get_jobs_in_radius`.

Dois gaps ligados que disparam no momento em que o cron for adicionado, sem mais nenhuma mudança de código:

1. `notification_handler.dart:48`: `case NotificationType.jobNoResponse: break;` — sem invalidação de providers, sem navegação. O cliente recebe a notificação mas a lista não atualiza e o tap não faz nada.
2. `notification_providers.dart`: `case NotificationType.jobNoResponse: break;` — nenhum provider invalidado.

---

**P-8-2 — N+1 queries de nome de worker em `_ProposalCard` — confirmado ainda presente, nunca corrigido**

`client_job_detail_screen.dart:914`:
```dart
class _ProposalCard extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final workerNameAsync = ref.watch(workerNameProvider(proposal.workerId));
```

`workerNameProvider` é `FutureProvider.family<String, String>` — uma chamada `fetchWorkerName(workerId)` separada por proposta. Para N propostas de N workers diferentes: N round-trips. Item já catalogado em improvements.md (secção "Performance técnica"), confirmado ainda presente. As queries do lado do worker (`fetchPendingWorkerProposals`, `fetchScheduledWorkerProposals`, `fetchCompletedWorkerProposals`) já usam corretamente o padrão de embedded resources PostgREST (`.select('*, job_requests!...')`). O mesmo padrão não foi aplicado ao lado do cliente.

---

**P-8-3 — Compressão de fotos diverge da decisão registada (1280px/72% em vez de 800px/60%)**

`decisions_log.md 2026-06-02`:
> "Compressão obrigatória antes do upload: largura máxima **800px**, qualidade **60%**."

`job_repository.dart:58`:
```dart
await FlutterImageCompress.compressWithFile(
  file.absolute.path,
  minWidth: 1280,   // ← decisão diz 800
  minHeight: 1280,  // ← decisão diz 800
  quality: 72,      // ← decisão diz 60
  ...
);
```

A decisão de 800px/60% foi tomada explicitamente por causa do limite de 50MB do Supabase Free Plan. A 1280px/72%, cada foto é ~4–8× maior que a 800px/60% (dependendo da imagem original). Com 2 fotos por job e jobs a acumular, o limite de storage esgota mais rapidamente do que o previsto.

---

**P-8-5 — `_acceptReschedule()` em `client_job_detail_screen.dart` deixa campos de remarcação obsoletos na cópia local `_job`**

`client_job_detail_screen.dart:164`:
```dart
setState(() => _job = _job.copyWith(
  confirmedDate: _job.rescheduleProposedDate,
  confirmedTime: _job.rescheduleProposedTime,
  confirmedFlexible: _job.rescheduleProposedFlexible ?? false,
  rescheduleStatus: RescheduleStatus.accepted,
  // rescheduleProposedDate, rescheduleProposedTime, rescheduleProposedBy
  // NÃO são limpos — BD limpa corretamente (linhas 996-999 da RPC), memória não
));
```

A BD limpa os campos propostos. A cópia local `_job` mantém os valores obsoletos até ao próximo re-fetch via `clientJobsProvider`. Impacto visual menor (campos propostos não são mostrados depois de aceitar), mas é uma inconsistência real. Limitação do Dart `copyWith` com `??` — campos nullable não podem ser limpos para `null` sem sentinelas ou re-fetch explícito.

---

**P-8-6 — `create_job_screen.dart:281` tem o mesmo padrão de exceção em bruto já visto em P-67-4 — 3.º ecrã, não 2.º**

```dart
error: (e, _) => Text('Erro ao carregar serviços: $e'),
```

A auditoria de Fases 6-7 (P-67-4) apanhou `worker_setup_screen.dart` e `worker_profile_screen.dart`. Este ecrã foi omitido. São 3 ecrãs no total com este problema, não 2. `error_utils.dart` já está importado em `create_job_screen.dart`.

---

**P-8-7 — `fetchScheduledWorkerProposals` busca TODAS as propostas `accepted` e filtra no cliente**

`proposal_repository.dart:131`: busca todos os registos `status = 'accepted'` do worker, depois descarta no Dart tudo o que não seja `confirmed | awaiting_confirmation`. Um worker com 50 jobs concluídos transfere todos os 50 para mostrar 1 ou 2 na tab "Agendados". Já tinha um TODO comentado no código. Confirmado ainda presente.

---

**P-8-8 — Jobs cancelados em `open` (nunca confirmados) invisíveis no histórico do cliente — decisão de produto a confirmar**

`client_jobs_screen.dart:45`:
```dart
(j.status == JobStatus.cancelled && j.acceptedProposalId != null)
```

Jobs cancelados antes de qualquer proposta ser aceite (`acceptedProposalId = null`) não aparecem no histórico. Pode ser intencional (menos lixo no histórico) ou um descuido. Sem registo explícito da intenção no `decisions_log`.

---

**P-8-9 — Notificações de `job_cancelled`/`job_reopened`/reschedule/conclusão navegam para a lista de jobs, não para o job específico**

`notification_handler.dart:28`: navega para `/client/jobs` ou `/worker/home` em vez do job concreto. O `related_id` está disponível mas não é usado para navegação. Ligado ao P6 da auditoria de Fases 0-3 (`state.extra!` impede deep-link às rotas de detalhe). Torna-se acionável após a implementação de A2 dessa auditoria (routing baseado em ID).

---

### Melhorias — Alta prioridade

**A1 — Implementar o cron `auto_expire_jobs` — último item não marcado da Fase 8 original (resolve P-8-1)**

Mesmo padrão do `auto_confirm_completed_jobs` já existente (migration 0014). Nova migration:

```sql
CREATE OR REPLACE FUNCTION auto_expire_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE job_requests
  SET status = 'no_response',
      updated_at = now()
  WHERE status = 'open'
    AND expires_at < now()
    AND proposal_count = 0;
END;
$$;

SELECT cron.schedule(
  'auto-expire-jobs',
  '0 */3 * * *',
  'SELECT auto_expire_jobs()'
);
```

Após aplicar à BD viva: `SELECT * FROM cron.job WHERE jobname = 'auto-expire-jobs';`

Correção Dart em `notification_handler.dart`:
```dart
// ANTES:
case NotificationType.jobNoResponse:
  break;

// DEPOIS:
case NotificationType.jobNoResponse:
  ref.invalidate(clientJobsProvider);
  context.go('/client/jobs');
```

E em `notification_providers.dart`:
```dart
case NotificationType.jobNoResponse:
  ref.invalidate(clientJobsProvider);
```

**Esforço: ~30 min** (migration + 3 linhas Dart).

**A2 — Corrigir parâmetros de compressão de fotos para 800px/60% (resolve P-8-3)**

```dart
// job_repository.dart:58 — ANTES:
minWidth: 1280,
minHeight: 1280,
quality: 72,

// DEPOIS (matches decisions_log 2026-06-02):
minWidth: 800,
minHeight: 800,
quality: 60,
```

3 linhas. Previne esgotamento prematuro do limite de 50MB do Free Plan. **Esforço: 2 min.**

---

### Melhorias — Média prioridade

**M1 — Resolver N+1 com join de profile em `fetchPendingProposalsForJob` (resolve P-8-2)**

Aplicar o mesmo padrão de embedded resources PostgREST que o lado do worker já usa:

```dart
// proposal_repository.dart:38 — ANTES:
.select()

// DEPOIS (confirmar nome exato da FK antes de implementar):
.select('*, profiles!job_proposals_worker_id_fkey(full_name, id)')
```

Adicionar `workerName` ao modelo `JobProposal`. Atualizar `_ProposalCard` para usar `proposal.workerName` diretamente em vez de `ref.watch(workerNameProvider(proposal.workerId))`. N queries → 1 query. **Esforço: ~45 min** (modelo + repository + widget).

**M2 — Corrigir exceção em bruto em `create_job_screen.dart:281` (resolve P-8-6)**

```dart
// ANTES:
error: (e, _) => Text('Erro ao carregar serviços: $e'),

// DEPOIS:
error: (e, _) => Text('Erro ao carregar serviços: ${friendlyError(e)}'),
```

`error_utils.dart` já importado. 1 linha. Junto com as 2 linhas de P-67-4 (Fases 6-7): fix total de 3 linhas em 3 ficheiros.

**M3 — Mover filtro de `fetchScheduledWorkerProposals` para a BD (resolve P-8-7)**

Substituir o `.where()` client-side por filtro PostgREST no embedded resource. Mesmo racional do TODO já existente no código. Reduz dados transferidos para workers com histórico longo.

**M4 — Timeline de estados (8E.5): decisão de "deixar até ao redesign" RE-CONFIRMADA com olhos frescos**

Lógica em `job_timeline.dart` analisada com atenção: cobre corretamente todos os estados documentados (incluindo reschedule pending/accepted e awaiting_confirmation). O único estado unreachable é `noResponse` (não implementado — P-8-1). Quando P-8-1 for corrigido, a timeline já o trata corretamente — sem mudanças necessárias.

**Decisão re-confirmada: não investir em polish visual agora.** A lógica de derivação de estados (`job_timeline.dart`) provavelmente sobrevive ao redesign visual. O widget (`status_timeline.dart`) é onde o redesign vai acontecer — não tocar até lá.

---

### Melhorias — Baixa prioridade

**B1 — Deep-link de notificações para o job específico (resolve P-8-9, bloqueado por Fases 0-3 A2)**

`related_id` disponível em todas as notificações de job. Navegação para o job concreto torna-se implementável após A2 da auditoria de Fases 0-3 (routing baseado em ID em vez de `state.extra`).

**B2 — `RescheduleDialog`: confirmar se impede seleção de data passada/mesmo dia**

A BD bloqueia via regra das 24h em `propose_reschedule`. Mas validação client-side com `firstDate: DateTime.now().add(Duration(days: 1))` no `showDatePicker` daria feedback imediato. Requer leitura de `reschedule_dialog.dart` para confirmar o estado atual.

**B3 — `state_machine.md` omite `jobsInRadiusProvider` na linha `proposal_rejected`**

O código em `notification_providers.dart:84` invalida corretamente `jobsInRadiusProvider` para `proposalRejected` (worker rejeitado pode ver o job novamente na descoberta). O documento `state_machine.md` não lista este provider na linha correspondente. Código correto; doc incompleto. Fix de documentação, não de código.

**B4 — `workerProposalForJobProvider` não invalidado para o cliente após `proposalAccepted`**

Edge case: nenhum ecrã atual do cliente depende deste provider diretamente após uma aceitação de proposta. Acionável se um futuro ecrã de cliente vier a observar este estado.

---

### Nota cross-cutting — invalidação de notificações

Cross-check completo dos 12 tipos de notificação originais da Fase 8 contra `notification_providers.dart`:

| Tipo | Providers no state_machine.md | Providers no código | Estado |
|---|---|---|---|
| `new_job_in_radius` | `jobsInRadiusProvider` | ✅ igual | ✅ |
| `proposal_received` | 5 providers | ✅ igual | ✅ |
| `proposal_withdrawn` | 4 providers | ✅ igual | ✅ |
| `proposal_accepted` | 7 providers | ✅ igual | ✅ |
| `proposal_rejected` | 4 providers | Código também invalida `jobsInRadiusProvider` (correto) | ✅ código correto, doc incompleto |
| `job_cancelled` / `job_reopened` | 6 providers | ✅ igual | ✅ |
| `reschedule_*` (3 tipos) | 5 providers cada | ✅ igual | ✅ |
| `job_marked_done` | 2 providers | ✅ igual | ✅ |
| `job_completed` | 3 providers | ✅ igual | ✅ |
| `job_no_response` | *(ausente do SM)* | `break` — sem invalidação | ❌ ver P-8-1 |

**Sem gaps de invalidação escondidos além do P-8-1.** Todas as notificações de remarcação, conclusão e propostas estão corretamente ligadas.

---

## 🔍 Auditoria 2026-06-25 — Fase 9, segunda passagem (a atacar em breve)

> Segunda revisão independente da Fase 9 (lobby screen, "As minhas
> candidaturas", factor 0.75, `created_post_confirmation`/`pending_approval`,
> UX de descoberta), feita em 2026-06-25 após a code review dedicada e as
> adições de cancellation handling. Itens numerados com códigos estáveis
> (P-9-1–P-9-6, A1–A2, M1–M3, B1–B2) para referência futura.

### Problemas encontrados


**P-9-3 — `_appliedIds` é estado transiente do widget (reset em rebuild) — "Candidatar-me" reaparece ativo após navegar e voltar**

`worker_help_requests_screen.dart:25`:
```dart
final Set<String> _appliedIds = {};
```

Após candidatura bem-sucedida e navegação/rebuild, `_appliedIds` está vazio. O help_request continua `open` (com 1 candidato pending), portanto regressar à lista mostra o botão "Candidatar-me" ativo. Um segundo toque falha silenciosamente por `UNIQUE (help_request_id, worker_id)` — sem corrupção de dados, mas confuso. O fix estrutural é A2 (excluir no RPC), não gestão de estado no widget.

---

**P-9-5 — `pending_approval` UI: gap intencional RE-CONFIRMADO como correto. Infraestrutura toda verificada — nenhuma ação necessária até ao path de criação manual pelo worker principal existir na UI**

Infraestrutura verificada e correta:
- `approve_help_request` RPC (`0003:151`): valida `status = 'pending_approval'`, verifica `v_job_client_id = auth.uid()`, muda para `open`, notifica principal ✅
- RLS policy "Cliente vê help requests pendentes de aprovação" (`0003:94`) ✅
- `approveHelpRequest` em `help_request_repository.dart:125` ✅
- `createHelpRequest` Dart escolhe `pendingApproval` vs `open` conforme `createdPostConfirmation` ✅

O fluxo `accept_proposal` cria com `created_post_confirmation = false` → gap não afeta MVP principal.

---

**P-9-6 — `get_my_help_acceptances` sem paginação — aceitável a esta escala, anotar para Fase 11+**

`0010_my_help_acceptances_rpc.sql:53`: `ORDER BY ha.created_at DESC` sem `LIMIT`/`OFFSET`. Para MVP scale (primeiros utilizadores, histórico curto) não é urgente. Para Fase 11+ quando o volume crescer: mesmo padrão de `fetchCompletedWorkerProposals` (limit/offset).

---

### Estado verificado como correto (12 itens confirmados nesta passagem)

`UNIQUE (help_request_id, worker_id)` em `help_acceptances` ✅ · exclusão do próprio principal na descoberta (`jp.worker_id <> auth.uid()`) ✅ · filtros de status `open`/`cancelled`/`completed` em `get_help_requests_in_radius` ✅ · factor 0.75/0.70 documentado em `decisions_log.md 2026-06-24` com explicação do buffer intencional ✅ · lógica de `_buildSlots` (accepted → pending → overflow → empty padding) ✅ · validações de status em `accept/reject_help_candidate` ✅ · autorização em `withdraw_help_acceptance` ✅ · cascade de `cancel_job` para `help_requests`/`help_acceptances` ✅ · lógica do botão "Desistir" apenas para `accepted` ✅ · invalidação de providers no lobby após aceitar/rejeitar ✅ · CHECK constraint `agreed_rate > 0` para `status = 'accepted'` ✅ · `pending_approval` help_requests invisíveis na descoberta (filtro `status = 'open'`) ✅

---

### Melhorias — Alta prioridade

**A2 — Excluir da descoberta help_requests onde o worker já tem candidatura ativa (resolve P-9-3, elimina `_appliedIds`)**

Adicionar ao `get_help_requests_in_radius` (CREATE OR REPLACE — nova migration):
```sql
AND NOT EXISTS (
  SELECT 1 FROM help_acceptances ha
  WHERE  ha.help_request_id = hr.id
    AND  ha.worker_id       = auth.uid()
    AND  ha.status IN ('pending', 'accepted')
)
```

Só migration, sem mudanças Dart. O `_appliedIds` torna-se irrelevante (pode ser removido ou mantido como micro-otimização para o instante entre o apply e o refresh da lista). **Esforço: ~15 min. Alto valor por esforço mínimo.**

---

### Melhorias — Média prioridade

**M3 — Implementar UI de `pending_approval` quando a Fase 11+ introduzir criação manual de help_request pelo principal worker — não antes (resolve P-9-5)**

Infraestrutura pronta; UI bloqueada por ausência do path de criação. Quando implementar: secção em `client_job_detail_screen.dart` listando `pending_approval` help_requests com botão "Aprovar" que chama `approveHelpRequest`.

---

### Melhorias — Baixa prioridade

**B1 — Paginação em `get_my_help_acceptances` (resolve P-9-6)**

Mesmo padrão de `fetchCompletedWorkerProposals` (limit/offset). Adiar para quando o volume justificar — Fase 11+.

**B2 — Documentar (ou impor via constraint) que um job deve ter um único `help_request` por design**

O schema permite múltiplos `help_requests` por job (sem UNIQUE em `(job_id, proposal_id)`). A intenção do MVP é one-to-one (um help_request com `slots_needed = N`). Se a intenção é flexível (múltiplos por job para serviços diferentes), documentar. Se é one-to-one, adicionar constraint. Actualmente não está registado em nenhum dos dois sentidos.

---

### Nota da sessão

A2 é a correção mais eficiente por esforço: 15 minutos de SQL eliminam tanto um bug de UX como um workaround inteiro de estado local no Dart.

O factor 0.75/0.70 está corretamente documentado em `decisions_log.md 2026-06-24` — não é um problema. O gap de `pending_approval` está correctamente documentado como intencional em `implementation_plan.md` — não é um problema.

---

## 🔍 Auditoria 2026-06-26 — Fase 10 (Contactos e conclusão)

> Revisão independente da Fase 10 (visibilidade de contactos após confirmação,
> fluxo de conclusão de dois lados, regra das 24h no cancelamento, reports,
> auto-confirmação por cron, ratings, notificações de conclusão) feita em
> 2026-06-26. Itens numerados com códigos estáveis (P-10-1–P-10-7, A1–A2,
> M1–M3, B1–B3) para referência futura.

### Problemas encontrados

**P-10-2 — Contacto do worker principal não visível ao ajudante — gap documentado em `project_overview.md`**

`project_overview.md` especifica: *"Ajudantes veem o contacto do worker principal, não o do client (no MVP)."* A nota imediatamente a seguir regista a implementação parcial: nome do principal já mostrado, contacto ainda não.

Confirmado no código:
- `HelpAcceptanceSummary.principalName` e `HelpAcceptanceDetails.principalName` existem — mostrados em 4 locais em `worker_help_requests_screen.dart` (linhas 386, 467, 539, 638)
- `principalPhone` — campo **não existe** em nenhum dos dois modelos
- Sem botão WhatsApp em qualquer ecrã para o ajudante contactar o principal

Não é uma regressão — está documentado como intencionalmente parcial em `project_overview.md`. Registado aqui para tracking até à implementação completa.

---

**P-10-3 — `auto_confirm_completed_jobs()` não notifica o cliente — só o worker recebe `job_completed`**

Em `0014_auto_confirm_cron.sql:49-58`:
```sql
IF v_worker_id IS NOT NULL THEN
  INSERT INTO notifications (...) VALUES (v_worker_id, 'job_completed', ...);
END IF;
-- Sem INSERT para v_job.client_id
```

Para confirmação manual (`confirm_job_completion`), o cliente não precisa de notificação — foi ele que confirmou. Para auto-confirmação por cron, o cliente não sabe que o estado mudou até reabrir a app e ver a lista. Consequências:
1. Se o cliente estava à espera para tomar uma decisão informada, a app decide por ele sem aviso.
2. `clientJobsProvider` não é invalidado quando `job_completed` chega via `notificationSyncProvider` — para o worker invalida `scheduledWorkerProposalsProvider` + `completedWorkerProposalsProvider(0)` + `jobByIdProvider`; para o cliente, nada. Se o cliente estiver ativo na app quando o cron disparar, a lista não atualiza em tempo real.

Fix: adicionar INSERT para `v_job.client_id` com tipo `job_completed` (e/ou novo tipo `job_auto_confirmed`) + invalidar `clientJobsProvider` no `notificationSyncProvider` para este tipo.

---

**P-10-4 — `job_reports` é efetivamente write-only — infraestrutura de moderação inexistente, mensagem UI prometendo revisão sem suporte**

O fluxo de "Reportar problema":
- UI: formulário com validação mínima (≥10 chars), tratamento de erros correto ✓
- RLS: INSERT (`reporter_id = auth.uid()`) ✓; SELECT para o próprio reporter ✓ (migration 0002) ✓

Mas após o INSERT:
- Sem policy SELECT para admins → invisível fora do Studio com service_role
- Sem trigger, webhook ou notificação para nenhum elemento da equipa
- O worker não sabe que um report foi enviado
- O job mantém-se em `awaiting_confirmation` até o cliente confirmar manualmente ou o auto-confirm disparar (3 dias)
- Sem mecanismo de disputa, escalada ou resolução dentro da app

A mensagem UI *"A nossa equipa vai rever o caso."* é uma garantia sem infraestrutura de suporte. Após o report, o cliente é perguntado se quer confirmar na mesma — a única via de saída prática dentro do prazo de 3 dias é confirmar. O report não altera o estado do job nem notifica ninguém.

Adicionalmente, `reportJobProblem()` está semanticamente mal colocado em `proposal_repository.dart:212` — não tem relação com propostas; deveria estar em `job_repository.dart`.

---

**P-10-6 — `reportJobProblem()` semanticamente mal colocado em `proposal_repository.dart`**

`proposal_repository.dart:212` contém um método que insere em `job_reports` — sem qualquer relação com propostas. Deveria estar em `job_repository.dart` ou num futuro `report_repository.dart`. Sem impacto runtime; código organizacionalmente incorreto.

---

**P-10-7 — Bloco `rejected` no worker screen faz fetch desnecessário de perfil de cliente que RLS sempre bloqueia**

`worker_my_job_detail_screen.dart:653`: no bloco `ProposalStatus.rejected`, `clientInfoAsync.when(...)` é observado. Mas a RLS `"Worker ve perfil de cliente com job confirmado"` exige `jp.status = 'accepted'` — para um worker com proposta rejeitada, `jp.status = 'rejected'`, logo a query retorna sempre vazio. A guarda `if (phone.isEmpty) return const SizedBox.shrink()` (linha 658) evita qualquer renderização incorreta, mas o fetch de rede é desnecessário e nunca produz resultado.

---

### Melhorias — Média prioridade

**M1 — Adicionar notificação ao cliente na auto-confirmação (resolve P-10-3)**

Nova migration que recria o corpo de `auto_confirm_completed_jobs()` com INSERT adicional:
```sql
-- Após o INSERT existente para o worker:
INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
VALUES (
  v_job.client_id,
  'job_completed',
  'Trabalho concluído automaticamente',
  'Passaram 3 dias sem confirmação. O trabalho foi concluído automaticamente.',
  v_job.id,
  'job_request'
);
```

E em `notification_providers.dart`, adicionar `clientJobsProvider` ao caso `jobCompleted`:
```dart
case NotificationType.jobCompleted:
  ref.invalidate(scheduledWorkerProposalsProvider);
  ref.invalidate(completedWorkerProposalsProvider(0));
  ref.invalidate(jobByIdProvider);
  ref.invalidate(clientJobsProvider);  // ← novo
```

Safe: para confirmação manual, o cliente faz `ref.invalidate(clientJobsProvider)` diretamente em `_confirmJobCompletion()` — o double-invalidate é inócuo.

**Esforço: ~20 min** (migration nova com corpo completo + 1 linha Dart).

**M2 — Implementar contacto do worker principal para ajudantes (resolve P-10-2)**

1. Atualizar `get_my_help_acceptances` RPC para incluir `p.phone AS principal_phone` (JOIN `profiles p ON p.id = jp.worker_id`)
2. Adicionar `principalPhone: String` a `HelpAcceptanceSummary` e `HelpAcceptanceDetails`
3. Adicionar botão WhatsApp nos cards de candidatura `accepted` em `worker_help_requests_screen.dart`

Verificar primeiro se a RLS de `profiles` para worker→worker está coberta por alguma policy existente (possivelmente `"Utilizador vê o seu perfil"` não cobre terceiros; pode ser necessária uma nova policy ou mover o campo para o RPC SECURITY DEFINER onde RLS é bypassed).

**Esforço: ~1.5h** (migration de RPC + modelo Dart + UI).

**M3 — Corrigir mensagem UI de `job_reports` para não fazer promessas sem infraestrutura (resolve P-10-4 parcialmente)**

Caminho mínimo (sem infraestrutura de moderação):

```dart
// ANTES — em client_job_detail_screen.dart:263:
'Descreve o que aconteceu. A nossa equipa vai rever o caso.'

// DEPOIS:
'Descreve o que aconteceu. O teu relato fica registado para referência futura.'
```

Remove a garantia falsa. O path completo (notificação real à equipa) requer Edge Function ou trigger com webhook para Slack/email — decidir quando a moderação for prioridade.

**Esforço: 1 linha. Trivial.**

---

### Melhorias — Baixa prioridade

**B1 — Mover `reportJobProblem()` para `job_repository.dart` (resolve P-10-6)**

Mover o método e atualizar o `import` em `client_job_detail_screen.dart`. Sem impacto runtime. **Esforço: ~15 min.**

**B2 — Remover fetch de perfil de cliente no bloco `rejected` do worker screen (resolve P-10-7)**

O `clientInfoAsync` (observado com `ref.watch`) é sempre-vazio para `liveStatus == ProposalStatus.rejected`. Condicionar o `ref.watch` a `liveStatus != ProposalStatus.rejected`, ou remover o bloco de contacto do ecrã de rejected inteiramente (o botão WhatsApp nunca renderiza). **Esforço: trivial.**

**B3 — Cross-reference: validação de data em `mark_job_done` — decisão de produto pendente**

O worker pode marcar como concluído antes da data confirmada — a BD não valida `confirmed_date`. Já documentado na secção "Confiança e segurança" deste ficheiro. Registado aqui como cross-reference para garantir que o item é considerado em Fase 11 quando as avaliações forem implementadas (uma avaliação imediata antes da data faz menos sentido).

---

### Estado verificado como correto

`mark_job_done` auth check (`v_worker_id IS DISTINCT FROM auth.uid()`) ✅ — não partilha o bug P-8-4 das 3 RPCs de remarcação · `confirm_job_completion` auth check (`v_job.client_id IS DISTINCT FROM auth.uid()`) ✅ · `cancel_job` bloqueia `awaiting_confirmation` explicitamente (`status NOT IN ('open', 'confirmed')` → RAISE) ✅ · UI sem botão cancelar em `awaiting_confirmation` (cliente nem worker) ✅ · `auto_confirm_completed_jobs()` localmente: `FOR UPDATE SKIP LOCKED` ✅, `SECURITY DEFINER` sem `auth.uid()` ✅, idempotente ✅, título distinto do confirm manual ✅ · `notification_providers.dart` — `jobMarkedDone`: invalida `clientJobsProvider` + `jobByIdProvider` ✅; `jobCompleted`: invalida `scheduledWorkerProposalsProvider` + `completedWorkerProposalsProvider(0)` + `jobByIdProvider` ✅ · RLS worker→cliente: usa `jp.status = 'accepted'` (não `jr.status`) — cobre todos os estados pós-aceitação sem necessidade de atualização ✅ · Fotos de jobs — policy SELECT: `client_id = auth.uid()` sem restrição de estado → cliente mantém acesso em qualquer estado pós-confirmação ✅ · Ratings: zero referências Dart à tabela `ratings`; único placeholder é `enabled: false` com tooltip em `client_job_detail_screen.dart:671` — Fase 11 genuinamente não iniciada ✅ · `job_reports` RLS INSERT (`reporter_id = auth.uid()`) ✅; SELECT para o próprio reporter ✅ (migration 0002) · `notification_handler.dart`: switch exaustivo sem wildcard; `jobMarkedDone` e `jobCompleted` navegam para a lista — mesma limitação de P-8-9 (deep-link bloqueado por P6 Fases 0-3), não nova nesta fase ✅

---

> **Nota:** Esta é a última auditoria da série Fases 0-10 (revalidada 2026-06-26 — ver apêndice de itens resolvidos/descartados).
> Itens mais urgentes por resolver após revalidação (por criticidade):
> **P-FA1** — `client_has_confirmed_job_with_worker` e policy associada ausentes de migrations (ALTA). (P-FA3 resolvido em migration 0018 — 2026-06-26.)

---

## Auditoria — Itens resolvidos/descartados (revalidação 2026-06-26)

> Revalidados contra `schema_snapshot_2026-06-26.csv` (snapshot direto da BD viva, 2026-06-26, já apagado) e migration 0016 (confirmada aplicada por Henrique via `pg_get_functiondef` e `pg_get_expr`).

### Totalmente resolvidos em código

- **P-67-1** *(Fases 6-7)* — `/worker/setup` ausente de `loadingExempt`: adicionado em `app_router.dart` (2026-06-26). Elimina perda silenciosa do formulário de setup após token refresh do Supabase (60 min).
- **P5** *(Fases 0-3)* — Sem guard cross-role no router: guard adicionado em `app_router.dart` após o bloco `role == null` (2026-06-26). **Mitigação parcial** — actualmente o acesso cross-role já causava crash (P6, `state.extra!`), pelo que o guard intercepta antes do crash. Após P6 ser corrigido (routing baseado em ID), o guard torna-se a protecção primária contra estado vazio silencioso com dados do UID errado. P6 continua aberto.

### Totalmente resolvidos por migration

- **P-FA4** *(Fases 4-5)* — `job_proposals` UPDATE policy sem `WITH CHECK`: corrigida em migration 0016 com `WITH CHECK (auth.uid() = worker_id AND status = 'superseded')`. Confirmada aplicada.
- **P-FA3** *(Fases 4-5, CRÍTICO)* — Policy de UPDATE de avatars usava `storage.foldername(name)[1]`, que devolve NULL para paths root-level `$userId.jpg`. Confirmado via `pg_policy` query 2026-06-26 que a policy viva ainda tinha a lógica quebrada (o fix interativo de 2026-06-15 corrigiu apenas INSERT, não UPDATE). Resultado prático: qualquer re-upload de avatar (2.º upload em diante) falha silenciosamente — `FileOptions(upsert: true)` passa pelo UPDATE policy quando o ficheiro já existe. Adicionada também DELETE policy (confirmada ausente via `pg_policy`). Corrigido em migration 0018 com `regexp_replace(storage.filename(name), '\.[^.]+$', '')`. Severidade confirmada elevada: de "gap teórico nunca capturado em migration" para "bug real em produção" (2026-06-26).

### Parcialmente verdadeiros → totalmente resolvidos

- **P-8-4** *(Fase 8)* — Bypass de autorização nas 3 RPCs de remarcação: **parcialmente verdadeiro**. Snapshot confirmou que `propose_reschedule` e `accept_reschedule` já tinham verificação correta na BD viva (corrigidas interactivamente numa sessão anterior não registada). Só `reject_reschedule` tinha o gap real — corrigido em migration 0016. **Lição:** findings multi-parte podem ser parcialmente verdadeiros; verificar cada componente contra a BD viva independentemente, não apenas contra ficheiros de migration.

### Totalmente resolvidos por migration + reestruturação de UI

- **P-9-1** *(Fase 9)* — `accept_help_candidate` não auto-rejeitava candidatos pending restantes quando `help_request` ficava `filled`: resolvido em migration 0017. Loop FOR adicionado após o UPDATE de fill — rejeita e notifica todos os outros pending imediatamente (2026-06-26).
- **P-9-2** *(Fase 9)* — Candidatos overflow não acionáveis no lobby (sem botão aceitar nem rejeitar): **fechado por mudança estrutural**. O modelo de "grelha de N vagas com isOverflow" foi eliminado — o lobby passa a mostrar todos os candidatos pending como lista plana, cada um acionável. O conceito de overflow não existe no novo modelo.
- **P-9-4** *(Fase 9)* — Label "Preenchida" ambígua no card de candidato overflow: **fechado por mudança estrutural** (igual a P-9-2 — não há cards de overflow no novo modelo de lista).

### Falsos alarmes confirmados por snapshot

- **P-10-1** *(Fase 10)* — `client_has_confirmed_job_with_worker` provavelmente só cobre `confirmed`: **falso alarme**. `pg_get_functiondef` confirmou que o corpo live já inclui `jr.status IN ('confirmed', 'awaiting_confirmation', 'completed')`. **Lição:** leitura de `0001_baseline.sql` (que não reflecte alterações interactivas posteriores) levou à suposição errada sobre o estado live — sempre verificar `pg_get_functiondef` contra funções críticas de RLS antes de reportar um bug.
- **P-10-5** *(Fase 10)* — Estado das migrations 0013–0014 não verificável localmente: **resolvido**. Snapshot confirmou migrations 0001–0014 todas aplicadas (evidência: corpo de `cancel_job` com regra 24h; `auto_confirm_completed_jobs` + cron `auto-confirm-completed-jobs` presentes na BD viva).

---

## UX e fluxo

### Comparação lado-a-lado de propostas
**Contexto:** Quando o cliente tem 3+ propostas, comparar é difícil scrollando entre cards.
**Ideia:** Vista alternativa em tabela com colunas (worker, preço, horas, data). Toggle entre vista de cards e vista de tabela.
**Prioridade:** Média — só faz sentido após validação do uso real com utilizadores.

### Aceitar 1ª proposta antes de receber mais
**Contexto:** Cliente pode aceitar a primeira proposta que chega sem ver outras melhores.
**Ideia:** Mensagem orientativa "Recomendamos aguardar até 24h para ver mais opções" — orienta sem bloquear.
**Prioridade:** Baixa.

### Badge de "novas propostas" na tab Propostas
**Contexto:** Cliente não sabe se há propostas novas desde a última visualização.
**Ideia:** Badge colorido na tab "Propostas (3)" laranja se houver propostas não vistas, neutro depois de abrir.
**Prioridade:** Média.

### Agrupamento visual de jobs reabertos
**Contexto:** Job cancelado + job novo são entradas separadas no histórico — pode ficar confuso.
**Ideia:** Agrupar visualmente "Cancelado → Reaberto como #..." numa linha.
**Prioridade:** Baixa — só relevante quando o histórico ficar denso.

### Vista de agenda do worker
**Contexto:** Worker com vários jobs agendados precisa de hierarquia temporal.
**Ideia:** Vista alternativa em calendário (semana/mês) com slots ocupados. Divisores "Hoje" / "Esta semana" / "Mais tarde" na lista.
**Prioridade:** Alta — vai ser essencial assim que os workers tiverem 5+ jobs simultâneos.

### Idade visual das propostas pendentes
**Contexto:** Worker não sabe se a proposta foi vista ou ignorada.
**Ideia:** Cor por idade — <24h normal, 24-48h amarelo, >48h cinzento (a expirar). "Há 6h", "Há 2 dias".
**Prioridade:** Média.

### Nota: Timeline de estados (8E.5) é implementação temporária
**Contexto:** O StatusTimeline atual (lib/core/widgets/status_timeline.dart)
foi feito como primeira versão funcional, lendo diretamente de JobRequest sem
nova infraestrutura. Está confirmado que esta UI específica será refeita do
zero mais tarde como parte de um redesign visual mais amplo (UI Playground).
**Implicação:** não vale a pena investir tempo extra em polish visual ou
animações nesta versão — só correção de bugs funcionais reais (dados errados
exibidos), não cosmética. A lógica de derivação dos estados (job_timeline.dart)
provavelmente sobrevive ao redesign mesmo que o widget visual mude por completo.
**Prioridade:** Baixa (é só uma nota de contexto, não uma tarefa).

---

## Confiança e segurança

### Verificação de identidade nível 2
**Contexto:** Hoje só temos email confirmado. Para serviços em casa de pessoas, confiança é tudo.
**Ideia:** Upload de documento de identidade, verificação manual no início, selo visível no perfil.
**Prioridade:** Alta — pós-MVP imediato.

### Contador de cancelamentos tardios
**Contexto:** Quando alguém cancela com <24h, é registado mas não bloqueado.
**Ideia:** Mostrar "Cumpre compromissos: 95%" no perfil público como sinal de confiança.
**Prioridade:** Média — depende das avaliações estarem prontas.

### Restrição de "marcar concluído" antes da data
**Contexto:** Hoje o worker pode marcar como concluído mesmo no dia em que enviou a proposta.
**Ideia:** Bloquear ou avisar "Tens a certeza? O trabalho está marcado para o dia X."
**Prioridade:** Média.

---

## Produto

### Pedidos recorrentes
**Contexto:** "Corte de relva quinzenal" é o santo graal — receita previsível para o jardineiro, conveniência para o cliente, uso recorrente da app.
**Ideia:** Ao criar pedido, opção "Repetir" com frequência (semanal, quinzenal, mensal). Cria jobs automaticamente.
**Prioridade:** Muito alta — feature de retenção mais valiosa.

### Perfil público partilhável
**Contexto:** Worker pode usar como cartão de visita fora da app.
**Ideia:** URL público `/p/<worker-slug>` com perfil, fotos, avaliações, serviços, zona. Cada partilha é aquisição grátis.
**Prioridade:** Alta — pós-MVP.

### Perfil de worker visitável (em camadas)
**Contexto:** Hoje o perfil do worker só é visível ao cliente depois de job
confirmado, e não há ecrã read-only — só o ecrã de edição do próprio worker.
Visão de produto: tornar o perfil um "cartão de visita a sério" dentro da
app, com 3 camadas progressivas.

**Camada 1 — Perfil visitável (sem dependências externas, pode iniciar
quando quiser):**
- RLS: cliente vê worker_profiles desde proposta `pending` (não só
  `accepted` como hoje); bidirecional — worker vê profiles do cliente
  desde `pending` também.
- UI: um único ecrã `worker_profile_screen` com dois modos — "próprio"
  (mostra botão editar) vs "visitante" (read-only), decidido por
  `profile_id == auth.uid()`. Evita duplicar estrutura visual em dois ecrãs.
- Conteúdo: foto, área de atuação (raio/zona), ferramentas, tipos de
  trabalho, avaliações (estrelas + comentários).
- Sem selo de "verificado" — só existe Nível 1 (telefone) implementado;
  um selo agora seria enganador. Esperar pelo Nível 2 (documento de
  identidade, já listado como Alta prioridade noutro item deste ficheiro).
- Risco identificado a resolver no design técnico: a query do perfil
  público NÃO deve expor `base_lat`/`base_lng` (localização base exata do
  worker) mesmo que a RLS permita — filtrar isso ao nível da query/DTO,
  não confiar só na RLS.
- Navegação: clicável a partir do card de proposta (cliente) e do card de
  job/cliente associado (worker).

**Camada 2 — Portfólio de trabalhos:** extensão do perfil da Camada 1.
Worker publica fotos de trabalhos feitos, separadas das fotos de jobs
individuais (campo `photos` já existe em worker_profiles — dar-lhe secção
própria com legendas/datas). Depende da Camada 1 estar pronta.

**Camada 3 — Feed na home:** mostrar workers próximos/recomendados na
página inicial do cliente. Depende de 1 e 2 estarem prontas e testadas com
utilizadores reais — decisões de produto novas em aberto (critério de
ordenação: proximidade? categoria? reputação?) ficam para quando lá
chegarmos, não decidir agora.

**Prioridade:** Camada 1 pode avançar a qualquer momento (sem bloqueios
externos). Camadas 2 e 3 são sequenciais a partir daí.
**Relacionado:** sobrepõe-se parcialmente com o item já existente "Perfil
público partilhável" (URL /p/<worker-slug>) — esse item é sobre partilha
FORA da app; esta Camada 1 é sobre visibilidade DENTRO da app. A estrutura
de dados do perfil pode ser partilhada entre os dois quando ambos avançarem.

### Carteira digital de cartões (combustível/seguro)
**Contexto:** Visão de longo prazo do programa de benefícios (ver
business_strategy.md secção 2) — quando uma parceria real for fechada
(Prio/BP/Galp para combustível, MDS/Fidelidade para seguro), o worker deve
poder guardar o cartão na app em vez de andar com o cartão físico.
**Decisão de scope (2026-06-19):** sem integração NFC real nem emissão de
pagamento (exigiria certificação com rede de cartões/Google Wallet — fora
de questão para este produto). Versão viável: "carteira digital" simples —
foto do cartão (frente/verso) + campos de texto livre (nome dado pelo
worker, tipo de cartão, número opcional). Mostrado em full-screen para
leitura manual por um funcionário — sem qualquer leitura eletrónica.
**Dependência real:** bloqueado por decisão de NEGÓCIO, não técnica — precisa
de pelo menos uma parceria de benefícios fechada (business_strategy.md
secção 2, todas "Estado: Ideia" atualmente) antes de desenhar a estrutura
final, porque o formato do cartão real só se sabe depois de negociar com
o parceiro.
**Modelo de dados (rascunho, não implementar):** tabela worker_benefit_cards
(id, worker_id, card_type, label, photo_front_url, photo_back_url nullable,
card_number nullable, created_at).
**Prioridade:** Pós-MVP — não avançar antes de fechar pelo menos uma
parceria real.

### Orçamento por projeto
**Contexto:** Hoje só temos preço/hora. Trabalhos grandes (relvado novo, sistema de rega) precisam de orçamento fechado.
**Ideia:** Novo tipo de pedido "Orçamento", worker envia proposta com valor total + descrição.
**Prioridade:** Média — abre mercado de trabalhos maiores.

### Dashboard do jardineiro
**Contexto:** "Quanto fiz este mês? Quantos km? Quantos trabalhos?"
**Ideia:** Ecrã com estatísticas mensais — ganhos, km, jobs feitos, % avaliação. Alimenta sentido de "isto é o meu negócio".
**Prioridade:** Alta.

### Trabalhos externos (agenda)
**Contexto:** Botão `+` do worker já está reservado para isto.
**Ideia:** Worker adiciona trabalhos que não vieram pela app à sua agenda. Permite organizar rotas e ter visão completa do dia.
**Prioridade:** Alta.

### Otimização de rotas
**Contexto:** Worker com 5 jobs num dia em sítios diferentes — ordem ótima poupa horas.
**Ideia:** A partir da agenda, sugerir ordem ótima de visitas (algoritmo simples nearest-neighbor ou integração Google Maps).
**Prioridade:** Média.

### Faturação simplificada
**Contexto:** Recibos verdes em Portugal são fricção para o jardineiro.
**Ideia:** Parceria com InvoiceXpress ou similar, ou pelo menos guias práticos dentro da app.
**Prioridade:** Média.

### Categorias além de jardinagem
**Contexto:** O código já está preparado (nomes genéricos).
**Ideia:** Expandir para limpeza, pequenas reparações, manutenção. Só depois de jardinagem ter tração numa zona.
**Prioridade:** Baixa — não expandir antes de validar.


### Mini-chat por proposta (modelo Vinted)
**Contexto:** Negociação entre cliente e worker acontece fora da app (WhatsApp).
Trazer a negociação para dentro da app aumenta confiança e contexto.
**Ideia:** Cada job_proposal tem um chat associado — cliente e worker trocam
mensagens dentro dessa proposta específica. Chat visível no card da proposta
(cliente) e no detalhe do worker. Mensagens em tempo real via Supabase Realtime
(infraestrutura já existe). Após proposta rejeitada/retirada, chat fica em
modo leitura (histórico).
**Modelo de dados:**
- Tabela `proposal_messages`: id, proposal_id, sender_id, content, created_at
- RLS: só client e worker da proposta veem as mensagens
- Realtime: subscrição por proposal_id
**UI:** bottom sheet da proposta tem duas tabs — "Detalhes" e "Chat".
Chat simples com bolhas, campo de texto, enviar. Sem fotos no MVP do chat.
**Porque é relativamente simples:** Realtime já configurado, padrão de
bottom sheet já existe, tabela é simples.
**Prioridade:** Alta — diferenciador forte vs contacto por WhatsApp.
Implementar depois de MVP estável e testado.

### Relações persistentes Worker ↔ Cliente + Jobs recorrentes
**Contexto:** Após o primeiro trabalho concluído, cliente e worker têm uma
relação que vale a pena preservar dentro da app. Hoje perdem-se para o WhatsApp.
**Visão em camadas (implementar por ordem):**

**Camada 1 — Conversa persistente (pós mini-chat de proposta)**
Canal de mensagens direto entre worker e cliente, criado automaticamente após
o primeiro job completed entre os dois. Mantém-se para trabalhos futuros.
Substitui o WhatsApp para comunicação recorrente.

**Camada 2 — Jobs recorrentes**
Dentro da conversa, cliente ativa "repetir trabalho" com frequência
(semanal, quinzenal, mensal). Worker confirma. Jobs seguintes criam-se
automaticamente com proposta automática (mesmo worker, mesmo preço).
Sem passar pelo marketplace — relação direta.

**Camada 3 — Perfil de cliente para o worker**
Worker vê histórico com aquele cliente: trabalhos feitos, morada guardada,
notas pessoais ("tem cão", "portão azul"), ganhos totais.

**Modelo de dados:**
- `worker_client_relationships`: id, worker_id, client_id, status, created_at, notes
- `relationship_messages`: id, relationship_id, sender_id, content, created_at
- `recurring_jobs`: id, relationship_id, service_type_id, frequency, next_date, last_job_id, status

Relação criada automaticamente após primeiro job completed entre os dois.

**Porque é estratégico:**
- Resolve desintermediação (relação vive na app, WhatsApp perde valor)
- Receita recorrente previsível para o worker
- Retém ambos os lados a longo prazo
- Base para programa de benefícios (worker com X recorrentes → nível Pro)
- Dados de uso (frequência, sazonalidade, padrões)

**Dependências:** Mini-chat por proposta deve estar implementado primeiro.
**Prioridade:** Muito Alta — é a feature anti-desintermediação mais importante.

---

## Notificações e comunicação

### Push notifications (FCM)
**Contexto:** Realtime in-app funciona, mas não notifica fora da app.
**Ideia:** Firebase Cloud Messaging + Supabase Edge Function que dispara push quando entra notificação na tabela.
**Prioridade:** Muito alta — pós-MVP imediato. Workers vão perder pedidos sem isto.

### Chat in-app
**Contexto:** Hoje a comunicação é via WhatsApp depois de confirmar.
**Ideia:** Chat simples (Supabase Realtime, tabela `messages`) para negociar antes/durante o trabalho sem sair da app.
**Prioridade:** Média — pós-MVP.

### Lembretes sazonais
**Contexto:** Jardinagem é sazonal — clientes podem esquecer "está na altura de podar".
**Ideia:** Notificações por categoria/serviço em datas específicas. Ex: outubro → "Está na altura de preparar o jardim para o inverno."
**Prioridade:** Média.

### Resumo diário do worker
**Contexto:** Pode ter perdido propostas durante o dia se a app estava fechada.
**Ideia:** Notificação ao fim do dia: "Hoje recebeste 2 propostas, ganhaste €X."
**Prioridade:** Baixa.

---

## Performance e técnico

### Otimizar N+1 query em propostas
**Contexto:** Cada `_ProposalCard` chama `workerNameProvider` separadamente — N round-trips para N propostas.
**Ideia:** Join `worker_profiles` em `fetchPendingProposalsForJob` para trazer nomes na mesma query.
**Prioridade:** Baixa — só relevante quando houver muitas propostas por job.

### Compressão e thumbnails de fotos
**Contexto:** Hoje comprimimos a 1280px no upload. Para thumbs na lista podia ser mais agressivo.
**Ideia:** Gerar thumb 400px no upload (segundo ficheiro) e usar nas listas. Original só no detalhe.
**Prioridade:** Baixa.

### Image transformations do Supabase
**Contexto:** Supabase tem CDN com transforms on-the-fly (resize, quality) — mas no Free Plan tem limites.
**Ideia:** Avaliar quando upgrade fizer sentido.
**Prioridade:** Baixa.

---

## Avaliações (Fase 11 já planeada, mas notas)

### Avaliações bilaterais
Cliente avalia worker, worker avalia cliente. Visíveis no perfil de ambos.

### Resposta a avaliações
Worker pode responder publicamente a uma avaliação ("Obrigado!", ou explicar contexto se for negativa).

### Avaliação só com transação concluída
Só permitir avaliar jobs `completed`. Evita avaliações falsas.

---

## Marca e produto

### Nome próprio em português
**Contexto:** "LocalServices" é genérico e mau para SEO.
**Ideia:** Considerar nome memorável em português antes do lançamento público. Mudar agora é barato, depois é caro.
**Prioridade:** Alta — decisão de marca.

### Logo e identidade visual
**Contexto:** Faltam ativos visuais para a app e marketing.
**Ideia:** Trabalhar com o designer no UI Playground em paralelo à app principal.
**Prioridade:** Alta.

---

## Performance técnica

### Optimizar get_jobs_in_radius para filtrar propostas do worker na BD (✅ implementado)
**Contexto:** Actualmente o Flutter faz 2 queries — uma para jobs no raio,
outra para proposals do worker — e filtra client-side. Pode ser uma query só.
**Solução:** Adicionar parâmetro `p_worker_id` ao RPC e fazer NOT EXISTS
na query SQL para excluir jobs onde o worker já tem proposta pending.
**Prioridade:** Média.

### fetchCompletedWorkerProposals: mover filtro para BD
**Contexto:** A query usa `.range(page * pageSize, ...)` antes de filtrar `job_requests.status == 'completed'` client-side. Páginas podem ter menos items que `pageSize` mesmo quando há mais páginas, levando o utilizador a não carregar mais quando ainda existem dados.
**Solução:** Criar RPC `get_completed_worker_proposals(p_worker_id, p_limit, p_offset)` que filtra por `status = 'accepted'` E `job_requests.status = 'completed'` antes de paginar — garantindo que o `LIMIT` se aplica após o filtro.
**Prioridade:** Média — afeta UX da paginação em workers com histórico longo.

### Paginação nas tabs Por confirmar e Agendados
**Contexto:** Actualmente sem limite. Para workers muito activos com muitas
propostas pendentes, pode ficar lento.
**Solução:** Adicionar paginação igual à tab Concluídos quando houver dados reais
que justifiquem (>50 items por tab).
**Prioridade:** Baixa — resolver quando houver utilizadores reais com volume alto.

---

## Bugs pendentes / melhorias técnicas

### Limpar funções RPC obsoletas (overload morto)
**Contexto:** Descoberto durante a criação da migration baseline (2026-06-19).
A BD viva tinha versões antigas de funções que coexistiam com as atuais via
overload do Postgres (mesmo nome, assinatura diferente).
- ~~`cancel_job(job_id_param uuid)`~~ — **resolvido em migration 0008** (DROP FUNCTION aplicado).
- ~~`create_proposal` overloads antigos~~ — **resolvidos em migration 0008** (ambas as assinaturas antigas removidas).
- `get_jobs_in_radius(worker_lat, worker_lng, radius_km)` sem `p_worker_id`
  — **ainda por remover**: esta versão não foi incluída no DROP da migration
  0008 (confirmado por inspeção do SQL). Ainda funciona mas ficou substituída
  pela versão com `p_worker_id`.
**Risco restante:** se alguma chamada esquecida no código ainda usar a
assinatura sem `p_worker_id`, corre sem filtrar o worker — overload
resolution silenciosa. Confirmar (grep no código Dart) antes de fazer DROP.
**Solução:** DROP FUNCTION da assinatura antiga em migration futura.
**Prioridade:** Média-Alta — limpeza de segurança barata.

---

## Como manter este ficheiro

- Sempre que aparecer uma ideia boa que **não cabe na fase atual**, adicionar aqui.
- Cada item: descrição curta + porquê + prioridade subjetiva.
- Quando uma ideia for implementada, remover daqui e mover para `decisions_log.md`.
- Rever esta lista no fim de cada fase para reavaliar prioridades.