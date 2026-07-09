# LocalServices — Decisions Log

> Registo de decisões técnicas importantes. Memória entre sessões Browser/Code.
> Formato: data — decisão — motivo.

## 2026-07-09 — Auditoria completa B1-B4 (DB) + C1-C4 (Dart) + migration 0032

### Contexto

Auditoria de segurança e correctness em duas camadas: (1) schema/RLS/funções via `snapshot_tables.csv`; (2) código Dart via leitura de todo `lib/`. Achados documentados em tabelas B1-B4 e C1-C4. Migration 0032 escrita para corrigir os itens críticos e altos. **NÃO APLICADA — aplicar manualmente via SQL Editor.**

---

### B2-C1 CRÍTICO: FKs quebrados causavam null em nomes/avatares de workers (produção)

**Root cause confirmado:** `job_proposals_worker_id_fkey` e `help_acceptances_worker_id_fkey` apontavam para `worker_profiles(profile_id)` em vez de `profiles(id)`. Migration 0031 foi um no-op silencioso: usou `IF NOT EXISTS` para verificar a existência do constraint pelo nome, encontrou-os (apontando para a tabela errada), e saltou o `ADD CONSTRAINT`. As strings de join `profiles!job_proposals_worker_id_fkey(full_name, avatar_url)` e `profiles!help_acceptances_worker_id_fkey(full_name, avatar_url)` em `proposal_repository.dart:42` e `help_request_repository.dart:88` pediam ao PostgREST para resolver o join via um FK cujo destino era `worker_profiles`, não `profiles` — join silenciosamente nulo.

**Fix (migration 0032, Priority 1):** DROP ambos os constraints; ADD CONSTRAINT apontando para `profiles(id) ON DELETE CASCADE`. Os dados existentes são consistentes (worker_id = profiles.id = worker_profiles.profile_id — mesmo UUID). O hint de join em Dart não muda: o nome do FK mantém-se, só o destino muda.

**Semântica de CASCADE após a mudança:** Apagar um profile cascada diretamente a job_proposals e help_acceptances (novo FK directo) e a worker_profiles (FK existente). Resultado final idêntico ao anterior.

**Após aplicar:** executar `NOTIFY pgrst, 'reload schema'` (ou reiniciar PostgREST no dashboard) para que o schema cache seja atualizado e os embed joins funcionem.

---

### B2 CRÍTICO: accept_proposal sem verificação de auth.uid() = client_id

**Vulnerabilidade:** qualquer utilizador autenticado que conhecesse um `proposal_id` e `job_id` podia chamar `rpc('accept_proposal', ...)` e aceitar uma proposta em nome do cliente — confirmando o job, notificando o worker, e criando um help_request automaticamente. A função é `SECURITY DEFINER`, by-passa RLS completamente.

**Fix (migration 0032, Priority 2a):** `CREATE OR REPLACE FUNCTION accept_proposal` com check no início: `IF NOT EXISTS (SELECT 1 FROM job_requests WHERE id = p_job_id AND client_id = auth.uid()) THEN RAISE EXCEPTION ...`. Resto do corpo idêntico ao snapshot.

---

### B2 CRÍTICO: create_proposal sem verificação de p_worker_id = auth.uid()

**Vulnerabilidade:** qualquer autenticado podia passar `p_worker_id = victim_uuid` e submeter uma proposta em nome de outro worker — incrementando o `proposal_count` do job da vítima, enviando notificação ao cliente com o nome errado, e bloqueando o slot de proposta da vítima nesse job.

**Fix (migration 0032, Priority 2b):** `IF p_worker_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Não autorizado.'` no início de `create_proposal`. Usa `IS DISTINCT FROM` para segurança com NULL.

---

### B2 CRÍTICO: sync_worker_service_types sem verificação de p_worker_id = auth.uid()

**Vulnerabilidade:** qualquer autenticado podia chamar `rpc('sync_worker_service_types', {'p_worker_id': victim_uuid, 'p_service_type_ids': []})` e apagar todos os tipos de serviço de outro worker. A policy `ALL USING (auth.uid() = worker_id)` em `worker_service_types` é bypassed por SECURITY DEFINER.

**Fix (migration 0032, Priority 2c):** `IF p_worker_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Não autorizado.'` no início de `sync_worker_service_types`.

---

### B3 ALTO: profiles.role escalação via UPDATE directo

**Vulnerabilidade:** a policy `"Utilizador atualiza o seu perfil"` tinha `USING (auth.uid() = id)` mas nenhum `WITH CHECK`. Um utilizador podia enviar `PATCH /profiles?id=eq.<uid>` com `{"role":"worker"}` e a BD aceitava — qualquer `client` tornava-se `worker` (ou vice-versa) sem nenhum obstáculo.

**Fix (migration 0032, Priority 3):** Trigger `tg_prevent_profile_role_change` (`BEFORE UPDATE ON profiles FOR EACH ROW`) que lança exceção se `NEW.role IS DISTINCT FROM OLD.role`. Trigger é o guard primário porque `WITH CHECK` em políticas de UPDATE só tem acesso ao NEW row — impossível comparar com OLD.role em RLS. A policy foi recreada com `WITH CHECK (auth.uid() = id)` para consistência (não adiciona protecção de role por si só).

---

### B3: Políticas SELECT de profiles ausentes de todas as migrations

**Achado:** o live DB tinha três políticas SELECT granulares em `profiles` que substituíram a policy broad `USING(true)` do 0001_baseline via sessões interativas. Ausentes de todas as migrations 0001-0031 — rebuild a partir de migrations deixaria qualquer autenticado a ler qualquer perfil.

**Fix (migration 0032, Priority 5):**
- DROP `"Perfis são legíveis por utilizadores autenticados"` (0001 — broad, não estava no live DB)
- CREATE `"Utilizador vê o seu perfil"` — USING: `auth.uid() = id`
- CREATE `"Worker ve perfil de cliente com job confirmado"` — USING: join via accepted proposal
- CREATE `"Cliente ve perfil de worker com job confirmado"` — USING: `role = 'worker' AND client_has_confirmed_job_with_worker(id)`

---

### C2 MÉDIO: fetchCompletedWorkerProposals — filtro client-side antes de paginação

**Problema:** a query usava `.range(page * pageSize, ...)` antes de filtrar `job_requests.status == 'completed'` no cliente. Páginas podiam ter menos items que `pageSize` mesmo com mais dados disponíveis — utilizador chegava ao fim prematuro.

**Fix (Dart, proposal_repository.dart):** substituído filtro client-side por `.filter('job_requests.status', 'eq', 'completed')` — mesmo padrão já usado em `fetchScheduledWorkerProposals` (`.filter('job_requests.status', 'in', '(confirmed,awaiting_confirmation)')`). PostgREST usa semântica INNER JOIN para filtros em embedded resources, por isso o RANGE/LIMIT é aplicado após o filtro. TODO e `.where()` client-side removidos.

---

### C2 MÉDIO: job_repository.createJob usa .single() após INSERT

**Problema:** `.insert(...).select('id').single()` lança `PostgrestException` se a SELECT policy não cobrir o próprio row (teoricamente impossível — a policy SELECT é `USING: auth.uid() = client_id` e o insertor é o cliente), mas `.single()` é estritamente mais frágil que `.maybeSingle()`.

**Fix (Dart, job_repository.dart):** `.single()` → `.maybeSingle()` com null check explícito: `if (result == null) throw Exception('Job criado mas SELECT não devolveu dados.')`.

---

### Riscos aceites (B4) — documentados como trade-offs intencionais

**auto_confirm_completed_jobs e auto_expire_jobs chamáveis por qualquer autenticado:**
Ambas são SECURITY DEFINER sem `auth.uid()` check. Qualquer utilizador pode chamar via RPC. Efeito real: `auto_confirm` é idempotente (muda jobs `awaiting_confirmation` com `updated_at > 3 dias` para `completed` — no máximo adianta jobs que seriam confirmados de qualquer forma); `auto_expire` move jobs `open` com `expires_at < now()` para `no_response` — também idempotente. O impacto de uma chamada não autorizada é mínimo e não há dados sensíveis expostos. Fix recomendado em fase futura: adicionar `IF auth.uid() IS NULL THEN RAISE EXCEPTION` — não bloqueia a cron mas bloqueia chamadas via RPC externo.

**Ratings INSERT — sem verificação de participação:**
A policy `"Utilizador cria a sua avaliação"` verifica `auth.uid() = rater_id` mas não que o rater participou no job. Um utilizador autenticado pode inserir uma avaliação para qualquer `job_id` e `ratee_id` (o check `check_rater_not_ratee` apenas impede auto-avaliação). As RPCs `submit_client_rating`, `submit_principal_rating`, `submit_helper_rating` são SECURITY DEFINER e fazem verificação de participação completa — devem ser usadas em vez do INSERT directo. O INSERT directo (via REST) sem passar pelas RPCs é um bypass da lógica de negócio; a layer Dart usa sempre as RPCs. Risco aceite no MVP enquanto as RPCs forem o único ponto de acesso.

**Storage INSERT policies sem verificação de path:**
As policies `"Upload avatar autenticado"` e `"Upload autenticado em job-photos"` verificam apenas `auth.role() = 'authenticated'`. Qualquer autenticado pode fazer upload para qualquer path em `avatars` e `job-photos`. A policy de DELETE verifica ownership do path — é possível sobrescrever o avatar de outro utilizador (o path de um avatar é `<userId>.jpg`; a policy de UPDATE verifica o filename, mas o INSERT não). Risco aceite no MVP.

---

### C4: T4 ordering anti-patterns (6 ocorrências) — sem crash em código atual

**Achado:** 6 locais onde `ref.invalidate()` é chamado antes de `router.go()`/`router.pop()`. Verificado via `ref.watch` de cada ecrã que nenhum deles observa os providers invalidados — sem risco de crash T4 no código atual. Ficam como anti-patterns que se tornarão bugs reais se esses providers forem adicionados ao `build()` dos respectivos ecrãs. Documentados como Low, não corrigidos.

---

### Skipped / Não corrigido nesta sessão

- **T4 ordering anti-patterns** (6 locais) — Low, não crash-causing atualmente
- **auto_confirm/expire auth check** — Low, impacto mínimo, aceite no MVP
- **Ratings INSERT policy** — Low, aceite no MVP (RPCs são o único ponto de acesso)
- **Storage INSERT policies** — Low, aceite no MVP
- **worker_setup_screen.dart direct Supabase call** — Medium/Architecture, sem impacto de segurança

## 2026-07-07 — F10-S4 fix definitivo: worker_profiles RLS + view + FKs directos + geocoding

**Decisão de design:** `worker_profiles` restrito a owner-only SELECT (`profile_id = auth.uid()`). View pública `worker_profiles_public` expõe colunas seguras (`bio`, `radius_km`, `tools`, `location_name`, `photos`) a qualquer utilizador autenticado. View criada **sem `security_invoker`** (definer-style, default PostgreSQL) — é deliberado: com `security_invoker=true` a view retornaria 0 rows para não-owners, silenciosamente, sem erro. Diferença crítica face a `worker_rating_summary` (0028, que usa `security_invoker=true` corretamente porque a sua tabela subjacente tem `USING(true)` — sem restrição a bypassed).

**Migration 0031** (`0031_missing_profile_fks.sql`) — NOT APLICADA:
- Adiciona `job_proposals_worker_id_fkey` → `profiles(id)` (FK declarado em 0001_baseline mas nunca registado em `pg_constraint` — mesmo root cause do 0029)
- Adiciona `help_acceptances_worker_id_fkey` → `profiles(id)` (idem)
- Puramente aditivo; zero alteração de comportamento; seguro a qualquer momento

**Migration 0030** (`0030_worker_profiles_security.sql`) — NOT APLICADA (aplicar DEPOIS de 0031 + Dart Phase B verificados em prod):
- `ADD COLUMN IF NOT EXISTS location_name text`
- DROP `"Worker profiles são públicos"` (USING(true) — causa raiz de F10-S4)
- DROP `"Cliente ve perfil de worker com job confirmado"` (0027 — também expunha base_lat/base_lng a clientes confirmados)
- CREATE `"Worker lê o seu próprio perfil"` — `USING (profile_id = auth.uid())`
- CREATE VIEW `worker_profiles_public` (definer-style, sem security_invoker) — `bio, radius_km, tools, location_name, photos`
- INSERT/UPDATE policies não afetadas (`"Worker cria o seu próprio worker profile"`, `"Worker atualiza o seu próprio worker profile"`)

**Phase B Dart** — selects atualizados para join directo (não via worker_profiles):
- `proposal_repository.dart:42` — `profiles!job_proposals_worker_id_fkey(full_name, avatar_url)`
- `help_request_repository.dart:88` — `profiles!help_acceptances_worker_id_fkey(full_name, avatar_url)`
- `proposal_model.dart` + `help_request_model.dart` fromJson — `json['profiles']` (um nível)
- Phase B3: grep exaustivo de `lib/` para `worker_profiles(` como join target — zero ocorrências adicionais

**Phase D Dart** — `create_job_screen.dart`: `GeocodingService.reverseGeocode` chamado após GPS (`_getLocation`) e tap no mapa (`_onMapTap`). Só preenche `_addressController` se estiver vazio — não sobrescreve input manual. Import `geocoding_service.dart` adicionado.

**Ordem de aplicação obrigatória:** 0031 (apply) → Dart Phase B (deploy + verify) → 0030 (apply). Inverter causa janela de quebra.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Security fix: worker_profiles USING(true) eliminado + GeocodingService (Nominatim)

**Achado de segurança (alta severidade):** a policy `"Worker profiles são públicos"` (0001_baseline.sql) usava `USING (true)` — qualquer utilizador autenticado podia ler `base_lat` e `base_lng` de qualquer worker diretamente via REST. A policy `"Cliente ve perfil de worker com job confirmado"` (migration 0027) ia na mesma direção mas com scope mais restrito.

**Migration 0030** (escrita, NOT APLICADA — aplicar via Supabase SQL Editor):
1. `ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS location_name text` — nome público da cidade/zona do worker (sem rua ou coordenadas exatas).
2. DROP `"Worker profiles são públicos"` + DROP `"Cliente ve perfil de worker com job confirmado"` em `worker_profiles`.
3. CREATE `"Worker lê o seu próprio perfil"` — `USING (profile_id = auth.uid())` — worker lê apenas o seu próprio row.
4. CREATE VIEW `public.worker_profiles_public` (`WITH (security_invoker = true)`) — expõe `profile_id, bio, service_radius_km, tools_description, location_name, created_at, updated_at` — sem `base_lat`, `base_lng`, sem `photos`. GRANT SELECT TO authenticated.

**Reads de Dart que precisam de atenção após migration aplicada (NOT alterados agora):**
- `proposal_repository.dart` — join `.select('*, worker_profiles(profiles!...fkey(...))')` chamado pelo cliente. Após remoção da policy de cliente, join devolve null. **Precisa de update para join direto em `profiles`.**
- `help_request_repository.dart` — join `.select('*, worker_profiles(profiles(...))')` chamado pelo worker principal para ver candidatos. Worker A não pode ler `worker_profiles` de worker B após migration. **Precisa de update.**
- `worker_repository.dart fetchProfile()` / `hasProfile()` — leem o próprio row — continuam a funcionar.

**GeocodingService** — `lib/core/services/geocoding_service.dart`:
- Nominatim (OpenStreetMap) — gratuito, sem API key, via `http: ^1.2.2`
- `reverseGeocode(lat, lng)` → `({String locationName, String addressText})?`
- `locationName` = cidade/town/village/county mais específico disponível (para `worker_profiles.location_name`)
- `addressText` = rua + número + código postal + cidade (para uso futuro como `address_text` padrão em criação de job)
- User-Agent: `ProJardim/1.0 (projardim@example.com)` — obrigatório pela política Nominatim
- Retorna `null` em qualquer erro — callers não crasham

**Wiring:** `worker_setup_screen.dart` e `worker_profile_screen.dart` — após GPS ou pesquisa de morada, fire-and-forget `GeocodingService.reverseGeocode` → `_locationName` em estado → passado a `WorkerProfile(locationName: ...)` no save. `toWorkerJson()` inclui `location_name` condicionalmente (`if (locationName.isNotEmpty)`) — evita erro PostgREST antes de migration aplicada.

`flutter analyze`: 0 issues. Migration 0030 NOT aplicada.

---

## 2026-07-06 — AddressMapLink: render por coordenadas, não por address text

**Problema:** `AddressMapLink` nunca aparecia porque todos os callers usavam `if (job.addressText.isNotEmpty)` como guard — e `address_text` estava vazio/null nos dados de teste.

**Fix em 3 partes:**

1. **`address_map_link.dart`** — widget agora renderiza sempre que `lat != 0 || lng != 0`. Se `address` estiver vazio, mostra "Ver no mapa" como label. Só oculta com `SizedBox.shrink()` se `lat == 0 && lng == 0` (sem dados de localização).

2. **Guards substituídos** — `if (job.addressText.isNotEmpty)` → `if (job.locationLat != 0 || job.locationLng != 0)` em todos os 8 pontos de chamada:
   - `client_job_detail_screen.dart`
   - `worker_home_screen.dart`
   - `worker_jobs_screen.dart`
   - `client_jobs_screen.dart`
   - `worker_job_detail_screen.dart` (detalhe + `_ProposalSheet`)
   - `worker_my_job_detail_screen.dart`
   - `worker_help_requests_screen.dart` (`_AcceptedCard`)

3. **`job_model.dart`** — `json['address_text'] as String` → `json['address_text'] as String? ?? ''` — null-safe, evita crash em runtime se a coluna estiver NULL na BD.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Google Maps integration completa em todos os ecrãs

**URL verificado:** `https://www.google.com/maps/search/?api=1&query=$lat,$lng` via `LaunchMode.externalApplication`. Sem `canLaunchUrl()` — só `launchUrl`. AndroidManifest já tem `<data android:scheme="https"/>` em queries — sem alterações ao manifesto.

**AddressMapLink** (ícone + label "Localização" + morada sublinhada + seta externa) adicionado a:
- `worker_home_screen.dart` — discovery card (substituiu GestureDetector inline)
- `worker_job_detail_screen.dart` — detalhe do pedido + topo do `_ProposalSheet`
- `worker_my_job_detail_screen.dart` — já existia
- `worker_jobs_screen.dart` — cards de propostas (todas as tabs) — **adicionado agora**
- `client_job_detail_screen.dart` — aba Detalhes para todos os estados — **adicionado agora**
- `client_jobs_screen.dart` — cards da lista (plain text substituído por link tappable) — **adicionado agora**
- `worker_help_requests_screen.dart` `_AcceptedCard` — já existia

**Compact map link** (ícone + "Ver no mapa" inline) adicionado a:
- `worker_help_requests_screen.dart` `_HelpRequestCard` (discovery) — **adicionado agora**. `HelpRequestSummary` tem lat/lng mas não `address_text` (RPC `get_help_requests_in_radius` não o devolve) — AddressMapLink inaplicável; link compacto com coordenadas diretas.

**Nota:** o endereço em `client_job_detail_screen.dart` é do próprio pedido do cliente — sem exposição de morada de terceiros.

---

## 2026-07-06 — Bug 3 causa raiz confirmada e corrigida (migration 0029 — NOT APLICADA)

**Causa raiz:** PostgREST devolve `worker_profiles: {profiles: null}` no join de dois saltos `worker_profiles(profiles(full_name, avatar_url))` apesar do JOIN SQL direto funcionar corretamente. A causa mais provável é que o FOREIGN KEY `worker_profiles.profile_id → profiles(id)` (declarado inline em 0001_baseline.sql com `PRIMARY KEY REFERENCES profiles(id)`) está ausente de `pg_constraint` na BD viva — possivelmente porque `CREATE TABLE IF NOT EXISTS` saltou o corpo da tabela quando a tabela já existia sem o FK. Sem este FK em `pg_constraint`, o PostgREST não consegue construir o segundo salto do join no schema cache e retorna null silenciosamente.

**Evidência:** a live query SQL (`JOIN wp ON wp.profile_id = jp.worker_id JOIN p ON p.id = wp.profile_id`) resolve `full_name` corretamente — os dados e a UUID estão certos. O problema é exclusivamente de descoberta de FK pelo PostgREST.

**Fix duplo (belt-and-suspenders):**

**(a) Migration 0029** — `DO $$ BEGIN IF NOT EXISTS (...referential_constraints WHERE table_name='worker_profiles' AND column_name='profile_id') THEN ALTER TABLE worker_profiles ADD CONSTRAINT worker_profiles_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE; END IF; END $$;` — seguro: a query `IF NOT EXISTS` verifica qualquer FK na coluna (independente do nome), pelo que é no-op se o FK já existir. Após aplicar, o PostgREST recalcula o schema cache e o join de dois saltos passa a funcionar.

**(b) FK hint explícito no select** — `proposal_repository.dart fetchPendingProposalsForJob` alterado de `.select('*, worker_profiles(profiles(full_name, avatar_url))')` para `.select('*, worker_profiles(profiles!worker_profiles_profile_id_fkey(full_name, avatar_url))')`. O hint diz ao PostgREST exatamente qual FK usar para o segundo salto, eliminando qualquer ambiguidade mesmo se houver múltiplos FKs de/para `worker_profiles`. `fromJson` não muda — o key path `json['worker_profiles']['profiles']['full_name']` é idêntico.

`[BUG3_DIAG] debugPrint` removido de `proposal_repository.dart`. Import `flutter/foundation.dart` removido.

Migration 0029 **APLICADA** em 2026-07-07.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Bug 3 diagnóstico + regressão A2 em client_home_screen corrigida

**Bug 3 — Logging de diagnóstico adicionado (aguarda captura de log ao vivo):**

`debugPrint('[BUG3_DIAG] raw first proposal: ${data.first}')` adicionado em `proposal_repository.dart fetchPendingProposalsForJob`, imediatamente antes do `.map(fromJson)`. Quando Henrique abrir o ecrã com propostas, o logcat mostrará o JSON cru para confirmar se a chave `worker_profiles` está presente e com que shape exato chega da BD. Import `package:flutter/foundation.dart` adicionado ao ficheiro (necessário para `debugPrint` fora de um widget).

As linhas exatas de parsing em `JobProposal.fromJson` que estão sob suspeita:
```dart
workerName: (json['worker_profiles'] as Map<String, dynamic>?)?
    ['profiles']?['full_name'] as String?,
workerAvatarUrl: (json['worker_profiles'] as Map<String, dynamic>?)?
    ['profiles']?['avatar_url'] as String?,
```
Se o log mostrar `worker_profiles: null` → workers sem `worker_profiles` row (hipótese de data). Se mostrar `worker_profiles: {profiles: null}` → join chega mas `profiles` está null (FK mismatch). Se mostrar shape diferente → chave errada no `fromJson`.

**Regressão A2 encontrada e corrigida — `client_home_screen.dart` ainda passava `extra: job`:**

Grep exaustivo de `lib/` para `extra:` com objetos de domínio encontrou 1 call site remanescente: `client_home_screen.dart:91` passava `extra: job` (um `JobRequest` completo) no `context.push('/client/job/${job.id}')` do card de job na home do cliente. Esta rota foi migrada para ID-based routing na sessão A2 de 2026-06-29 — todos os outros call sites (`client_jobs_screen.dart`, `notification_handler.dart`) já tinham o extra removido, mas este ficou. Era este o call site que gerava o aviso GoRouter "An extra with complex data type JobRequest is provided without a codec." Corrigido: `extra: job` removido; a rota recebe apenas o ID e carrega via `jobByIdProvider` como os restantes.

Os únicos `extra:` remanescentes em toda a app são `{'initialTabIndex': 1}` em 3 casos em `notification_handler.dart` — passa um `int` primitivo, confirmado seguro (sem codec necessário para primitivos).

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Bugs 1, 2, 4 corrigidos (testes 2026-07-05)

**Bug 1 — Avatar não aparecia após upload (dois sub-problemas):**

**1a — `createProfile` não escrevia `avatar_url` em `profiles`:** `worker_repository.dart createProfile()` atualizava `profiles` apenas com `full_name` e `phone`. `workerProfileProvider` lê `avatar_url` de `profiles` (via `getProfile`), pelo que o avatar carregado durante o setup era silenciosamente ignorado. Corrigido: adicionado `if (profile.avatarUrl != null) 'avatar_url': profile.avatarUrl` ao mapa de `profiles.update()` em `createProfile`, espelhando exatamente o que `updateProfile` já fazia.

**1b — Cache de NetworkImage servia imagem antiga após re-upload:** `uploadAvatar` em ambos os repositórios (`worker_repository.dart` e `client_repository.dart`) faz upsert sempre para o mesmo path `$userId.jpg`. O URL público resultante é idêntico ao anterior — Flutter reutiliza a entrada em cache e a foto nova nunca aparece. Corrigido: `uploadAvatar` retorna agora `'$url?v=${DateTime.now().millisecondsSinceEpoch}'` em ambos os repositórios. O parâmetro de query muda a cada upload, forçando o `NetworkImage` a tratar o URL como novo.

**1c — `workerProfileProvider` não invalidado após setup:** `worker_setup_screen.dart _save()` chamava `sessionStatusProvider.notifier.refresh()` mas não invalidava `workerProfileProvider`. Se o worker navegasse para o perfil imediatamente após o setup, via dados em cache sem avatar. Corrigido: `ref.invalidate(workerProfileProvider)` adicionado imediatamente após `context.go('/worker/home')` (padrão T4: navegar primeiro, invalidar depois).

---

**Bug 2 — Crash keyReservation em notificações de discovery (newJobInRadius, proposalRejected, jobReopened):**

`notification_handler.dart` usava `context.push` nos 3 casos de discovery do worker. Se o worker já estivesse a ver o ecrã de detalhe de um job quando a notificação chegava, o push duplicava a rota ativa, causando a assert `keyReservation.contains(key) is not true` (mesma classe do RT1). A decisão de usar `push` para preservar navegação para trás foi reavaliada: o custo de crash supera o benefício de UX da back-navigation a partir de uma notificação. Corrigido: `context.push` → `context.go` nos 3 casos (`newJobInRadius` linha 19, `proposalRejected` linha 55, `jobReopened` linha 83). `context.go` substitui o stack — sem possibilidade de rota duplicada.

---

**Bug 4 — Foto do cliente ausente no card de contacto do worker (dupla omissão):**

`client_repository.dart fetchClientBasicInfo()` selecionava apenas `full_name, phone` — `avatar_url` nunca era fetched. Adicionado `avatar_url` ao select e ao mapa de retorno (default `''` para null). Fallback vazio em `client_providers.dart` atualizado para incluir `'avatar_url': ''`. Na UI, `worker_my_job_detail_screen.dart` (card "Cliente") substituiu `Row(Icon + Text)` pelo widget reutilizável `UserAvatarWithName` — passa `name`, `avatarUrl` (null se string vazia), e `nameStyle` com a cor `onPrimaryContainer` do tema. Import `user_avatar_with_name.dart` adicionado.

---

**Bug 5 — Restart após conclusão de job (não é bug de código):**

Investigado e documentado como limitação conhecida: a atualização de estado em tempo real depende da stream do Supabase Realtime estar ativa. Se o utilizador tiver a app em background quando a notificação `jobMarkedDone`/`jobCompleted` chega, a stream pode estar desligada e o estado não atualiza sem restart. Código de invalidação nos dois lados confirmado correto (`_markCompleted` invalida providers do worker; `notification_providers.dart` invalida providers do cliente via `jobMarkedDone`). Push notifications via FCM resolveria este problema — ver item de alta prioridade em `improvements.md`.

**Bug 3 — Pending:** aguarda resultado de live query para confirmar workers sem `worker_profiles` row.

`flutter analyze` após todas as alterações: **0 issues**.

---

## 2026-07-04 — Auditoria de segurança Fase 10 (dados/RLS apenas; UI ignorada por redesign pendente)

3 achados confirmados, 2 corrigidos em migration 0028, 1 confirmado já correto:

**F10-S1 — policy INSERT de `job_reports` demasiado permissiva:** `"Utilizador reporta problema"` (0001_baseline.sql:442) verificava apenas `auth.uid() = reporter_id` — qualquer utilizador autenticado podia submeter um report para qualquer `job_id`. Corrigido em 0028: nova policy `"Participante pode reportar o seu job"` exige que o reporter seja o cliente do job OU o worker com proposta aceite. Nota: a policy anterior foi confirmada pelo nome exato (`"Utilizador reporta problema"`) — a policy `"Authenticated users can report jobs"` mencionada no brief era um placeholder incorreto.

**F10-S2 — `worker_rating_summary` sem `security_invoker` capturado em migration:** 0024 criou a view sem `security_invoker = true`; fix aplicado no SQL Editor após 0024 não estava em nenhuma migration — rebuild a partir de migrations revertia o fix. Capturado em 0028 com `CREATE OR REPLACE VIEW ... WITH (security_invoker = true)`. Comportamento atual não muda (ratings SELECT USING (true) é público), mas qualquer future tightening de RLS na tabela `ratings` seria silenciosamente bypassado por uma view security-definer.

**F10-S3 — `fetchRatingsWithRaterNames` audited, sem alteração necessária:** Select atual é `'*, rater:profiles!rater_id(full_name)'` — phone já não estava incluído no join. O `*` aplica-se apenas a colunas de `ratings` (stars, comment, rater_id, ratee_id, job_id, created_at). Nenhuma exposição de phone; nenhuma alteração ao código Dart.

Migration 0028 **APLICADA** em 2026-07-07.

---

## 2026-07-04 — M4 implementado: PendingSignupNotifier substitui state.extra no fluxo de registo

`state.extra` removido como portador de `fullName`/`phone` entre `SignupScreen` e `ChooseRoleScreen`. Substituído por `NotifierProvider<PendingSignupNotifier, PendingSignupState>` em `lib/features/auth/application/pending_signup_provider.dart`. Dados ficam em memória Riverpod — sobrevivem a qualquer tick de auth-state ou redirect do router, sem dependência de navigation stack.

Ficheiros alterados: `signup_screen.dart` escreve para o provider antes de `context.go('/choose-role')` (sem extra); `choose_role_screen.dart` lê via `ref.read(pendingSignupProvider)` em `_submit()` e chama `.clear()` após `createProfile` com sucesso; `app_router.dart` simplificado para `builder: (_, _) => const ChooseRoleScreen()` (sem leitura de `state.extra`). Campos `required this.fullName`/`required this.phone` removidos do construtor de `ChooseRoleScreen`. Riverpod 3.x — usado `Notifier`/`NotifierProvider` (não `StateNotifier`/`StateNotifierProvider`, removidos na v2).

---

## 2026-07-04 — P-8-7 filtro server-side em fetchScheduledWorkerProposals; P-10-2 confirmado já resolvido

**P-8-7 — filtro movido para servidor:** `fetchScheduledWorkerProposals` em `proposal_repository.dart` — adicionado `.filter('job_requests.status', 'in', '(confirmed,awaiting_confirmation)')` ao query PostgREST via embedded resource filter. Bloco `.where()` Dart eliminado. Sort por `confirmed_date` mantido client-side (PostgREST não suporta ORDER BY em campos de embedded resource). Antes: worker com N jobs concluídos transferia todos os N registos `accepted` para filtrar 1-2 no cliente. Depois: apenas registos com job `confirmed | awaiting_confirmation` chegam ao cliente.

**P-10-2 — confirmado já resolvido:** Leitura de `help_request_model.dart` confirmou que `HelpAcceptanceSummary` já tem `principalPhone: String` e `principalWorkerId: String` com defaults `''`, parseados em `fromJson`. `_AcceptedCard` em `worker_help_requests_screen.dart` já apresenta botão WhatsApp gated em `principalPhone.isNotEmpty`. Implementação completa — provavelmente introduzida em RC3 / migration 0022 (2026-06-27). Nenhum código alterado; apenas marcado resolvido em `improvements.md`.

---

## 2026-07-04 — proposalRejected invalida workerProposalForJobProvider; P-8-2 N+1 eliminado

**FIX 1 — `proposalRejected` invalidation gap:** `notification_providers.dart`, case `proposalRejected` — adicionado `ref.invalidate(workerProposalForJobProvider)` (família completa, sem chave — `workerId` não está disponível no contexto do sync provider; mesmo padrão de `proposalWithdrawn`). `relatedId = p_job_id` confirmado via migration 0001_baseline.sql. Gap identificado na auditoria de 2026-07-01 e agora fechado.

**FIX 2 (P-8-2) — N+1 eliminado em `_ProposalCard`:** `fetchPendingProposalsForJob` em `proposal_repository.dart` alterado de `.select()` para `.select('*, worker_profiles(profiles(full_name, avatar_url))')` — join de dois saltos (padrão idêntico ao T7 fix: `job_proposals.worker_id → worker_profiles.profile_id → profiles.id`; FK direta `job_proposals → profiles` não existe). `JobProposal` recebeu dois campos opcionais: `workerName: String?` e `workerAvatarUrl: String?`, parsed via `(json['worker_profiles'] as Map?)?['profiles']?['full_name/avatar_url']`. `_ProposalCard` em `client_job_detail_screen.dart` removeu `ref.watch(workerBasicInfoProvider(proposal.workerId))` e lê `proposal.workerName` / `proposal.workerAvatarUrl` diretamente — N queries por lista → 1 query. `workerBasicInfoProvider` permanece em uso na mesma classe para `_workerContactCard` (line 533); import mantido.

---

## 2026-07-01 — Parte A: UX do formulário de proposta reestruturado + Parte B: ícone de mapa

**Parte A — Formulário de proposta (`worker_job_detail_screen.dart` `_ProposalSheet`):** Campo `TextFormField` "Pessoas necessárias" substituído por `CheckboxListTile` "Preciso de ajuda". Quando desmarcada: `people_needed = 1` e `helpers_equipment_required = false` (valores por omissão, sem submenu visível). Quando marcada: revela `DropdownButton<int>` (opções 2–5, total incluindo o principal) mapeado para `people_needed` e `SwitchListTile` "Ajudantes devem trazer equipamento próprio" mapeado para `helpers_equipment_required`. Ao desmarcar: ambos os valores resetam antes de ocultar o submenu. `_peopleController` removido; `_needsHelp`, `_peopleNeeded`, `_helpersEquipmentRequired` substituem.

**Parte A — Discovery do ajudante (`worker_help_requests_screen.dart` `_HelpRequestCard`):** Quando `equipment_required = false`, o checkbox "Levo o meu equipamento" foi substituído por texto estático "Sem equipamento necessário" com ícone neutro. `broughtEquipment` passa sempre como `summary.equipmentRequired` (true quando obrigatório, false quando não). `_broughtEquipment` Map e parâmetros `broughtEquipment`/`onBroughtEquipmentChanged` removidos do widget e do estado pai.

**Parte B — Ícone de mapa nos cards do worker (`worker_home_screen.dart`):** Endereço em texto removido dos cards de discovery. Substituído por `GestureDetector` com `Icon(Icons.map_outlined)` que abre Google Maps diretamente via `launchUrl` com as coordenadas do job. `url_launcher` importado.

**Parte B — AddressMapLink no detalhe de job (`worker_job_detail_screen.dart`):** Bloco `Row(Icon + Text)` com endereço em texto simples substituído por `AddressMapLink` (já existia noutros ecrãs — padrão reutilizado). `address_map_link.dart` importado.

**Parte B — Confirmações:** `worker_my_job_detail_screen.dart` já usava `AddressMapLink`. `worker_help_requests_screen.dart` já usava `AddressMapLink` na tab "As minhas candidaturas" (linha 547). `client_job_detail_screen.dart` não mostra morada de terceiros — sem mapa no ecrã do cliente (confirmado, skip intencional).

---

## 2026-07-01 — RT3, RT5, RT9 resolvidos + widget UserAvatarWithName criado

**RT3:** `fetchWorkerBasicInfo` estendido para incluir `avatar_url` (SELECT `full_name, phone, avatar_url`). `_workerContactCard` em `client_job_detail_screen.dart` substituiu `Icon(Icons.person_outlined) + Text(name)` pelo novo widget `UserAvatarWithName`. Widget criado em `lib/core/widgets/user_avatar_with_name.dart` — `StatelessWidget` que exibe `CircleAvatar` com `NetworkImage(avatarUrl)` se URL não-vazio, ou inicial do nome caso contrário, seguido do nome em `Text` expandido.

**RT5:** `_acceptedProposalCard` adicionado a `client_job_detail_screen.dart`. No bloco `confirmed`, inserido antes de `_workerContactCard` quando `acceptedProposalAsync.asData?.value != null`. Mostra taxa/hora, horas estimadas, total estimado, pessoas. `acceptedProposalForJobProvider` já era watchado no mesmo `data` block desde sessão anterior — nenhum novo provider necessário.

**RT9:** `_RatingChip` (`ConsumerWidget`) adicionado a `worker_jobs_screen.dart`. Observa `myRatingForJobProvider(jobId)`. Quando rating existe, exibe chip `★ N/5` na `_JobCard` dos jobs com `job.status == JobStatus.completed`. `_buildCompletedSection` em `worker_my_job_detail_screen.dart` confirmado correto (gated em job.status == completed dentro de proposal.status == accepted).

**Bónus (STEP 6):** `_ProposalCard` em `client_job_detail_screen.dart` actualizado para usar `workerBasicInfoProvider` em vez de `workerNameProvider` — `CircleAvatar` com avatar ou inicial substitui `Icon(Icons.person_outlined)`. Rating star e restante layout inalterados.

---

## 2026-07-01 — Auditoria completa de notification_handler.dart (RT1, RT4, T6 resolvidos)

Auditoria de todos os 19 tipos de notificação em `notification_handler.dart`. Casos corrigidos: (1) **RT4** — `proposalAccepted` com fetch nulo agora faz `context.go('/worker/home')` + SnackBar em vez de break silencioso; mesmo padrão aplicado a `helpRequestApproved` e `helpWithdrew`. (2) **RT1** — todos os lifecycle cases convertidos de `context.push` para `context.go`, eliminando o keyReservation crash por push duplicado para rota já ativa. (3) **T6 completo** — `jobCancelled`, `rescheduleProposed/Accepted/Rejected`, `jobCompleted` agora têm split por role (cliente → `/client/job/$id`; worker → async fetch proposalId → `/worker/my-job/$pid?jobId=$id`, fallback home); `jobMarkedDone` e `jobNoResponse` navegam para `/client/job/$id` (client-only); `jobReopened` navega para `/worker/job/$id` (push). (4) `helpRejected` agora navega para candidaturas em vez de break silencioso. (5) `context.mounted` verificado após cada `await` em todos os casos. Import `job_providers.dart` removido (deixou de ser usado após mover `ref.invalidate` para `notification_providers.dart`). RT2 e RT8 confirmados presentes em `notification_providers.dart`. Gap menor identificado: `proposalRejected` em `notification_providers.dart` não invalida `workerProposalForJobProvider` (não bloqueante).

---

## 2026-07-01 — RT2, RT6, RT8 corrigidos (Grupo 1 do plano de ataque do Run 1)

`proposalReceived` em `notification_providers.dart` agora invalida `jobByIdProvider(notification.relatedId)` (RT2) — garante que o cliente no ecrã de detalhe vê a pill de estado actualizada quando chega uma nova proposta. Handlers de remarcação do worker (`_proposeReschedule`, `_acceptReschedule`, `_rejectReschedule` em `worker_my_job_detail_screen.dart`) confirmados já correctos por leitura directa — todos têm `ref.invalidate(jobByIdProvider(widget.jobId))` após `router.pop()` (RT6 já estava resolvido). `jobCompleted` em `notification_providers.dart` agora invalida `myRatingForJobProvider(notification.relatedId)` e `myRatingForJobAndRateeProvider` (família completa) para que o ecrã de avaliação reflicta o estado correcto sem restart (RT8); import `rating_providers.dart` adicionado ao ficheiro.

---

## 2026-07-01 — Run 1 do dashboard de testes: 9 achados cross-referenciados

Run 1 do dashboard de testes manuais (executado no dia anterior, cross-referenciado hoje) revelou 9 achados: 1 crash novo (RT1), 1 avatar ausente no card de contacto (RT3 — NOVO), 1 gap de UI genuíno já identificado duas vezes no mesmo dia (RT5), 3 gaps concretos em fixes já existentes mas incompletos (RT2, RT4, RT8), e 2 achados a confirmar por leitura directa de código antes de corrigir (RT6, RT9). RT7 confirma que o padrão de fix já correto (T4) funciona quando aplicado — usar como referência para os restantes. Todos registados em `improvements.md` com códigos RT1–RT9. Nenhum corrigido nesta sessão — documentação apenas.

---

## 2026-07-01 — Migration 0027 aplicada à BD viva

Migration `0027_doc_audit_fixes.sql` aplicada manualmente via Supabase SQL Editor por Henrique. Todos os 5 fixes activos: `client_has_confirmed_job_with_worker` + policy (P-FA1), `sync_worker_service_types` RPC (P-67-2), 4 índices em falta (P-FA5+M3), `help_acceptances.status DEFAULT 'pending'` (P-FA6), policy SELECT cliente `help_requests` (M5).

---

## 2026-06-30 — Auditoria de docs: 5 gaps confirmados corrigidos via migration 0027 + T6 expandido

### Contexto

Verificação manual dos itens "Crítico" e "Alta prioridade" de `improvements.md` contra a BD viva e o código actual. Henrique confirmou dois items via live query directa:
- **P-FA5:** `SELECT indexname FROM pg_indexes WHERE tablename IN ('help_requests','help_acceptances')` → **0 rows** — nenhum dos 3 índices existia.
- **P-FA6:** `SELECT column_default FROM information_schema.columns WHERE table_name='help_acceptances' AND column_name='status'` → `'accepted'::text` — default incorreto confirmado.

Os restantes 3 items (P-FA1, P-67-2, M5) confirmados por grep exaustivo de migrations 0001–0026 e inspeção do código Dart.

**Achado adicional:** item `get_jobs_in_radius overload antigo` em `improvements.md` estava marcado como "ainda por remover". Verificação de `0011_drop_obsolete_get_jobs_in_radius.sql` confirmou que já contém `DROP FUNCTION IF EXISTS get_jobs_in_radius(numeric, numeric, integer)` — item era STALE; nenhuma acção necessária.

### Migration 0027_doc_audit_fixes.sql — CRIADA, NÃO APLICADA

**IMPORTANTE: Este ficheiro foi criado mas NÃO aplicado à base de dados. Aplicar manualmente via Supabase SQL Editor.**

Cinco fixes num único ficheiro (`supabase/migrations/0027_doc_audit_fixes.sql`):

#### P-FA1 — `client_has_confirmed_job_with_worker` + policy ausentes de todas as migrations

`CREATE OR REPLACE FUNCTION client_has_confirmed_job_with_worker(p_worker_id uuid)` com os três estados correctos (`confirmed`, `awaiting_confirmation`, `completed`) + `CREATE POLICY "Cliente ve perfil de worker com job confirmado" ON worker_profiles FOR SELECT USING (client_has_confirmed_job_with_worker(profile_id))`.

Nota: `worker_profiles` PK é `profile_id` (confirmado em `0001_baseline.sql` linha 35) — a policy usa `profile_id`, não `id`.

#### P-67-2 — sync de serviços do worker agora atómico via RPC

Dart: `_syncServiceTypes` em `worker_repository.dart` substituído por chamada única `_client.rpc('sync_worker_service_types', params: {...})`. As duas chamadas PostgREST separadas (DELETE + INSERT) sem transação foram eliminadas — o intervalo de tempo em que o worker podia ficar com ZERO serviços deixa de existir.

SQL: `CREATE OR REPLACE FUNCTION sync_worker_service_types(p_worker_id uuid, p_service_type_ids uuid[]) RETURNS void LANGUAGE plpgsql SECURITY DEFINER` — DELETE + INSERT numa única transação.

#### P-FA5 + M3 — índices em falta criados

```sql
CREATE INDEX IF NOT EXISTS idx_help_requests_job_id ON help_requests (job_id);
CREATE INDEX IF NOT EXISTS idx_help_requests_proposal_id ON help_requests (proposal_id);
CREATE INDEX IF NOT EXISTS idx_help_acceptances_worker_id ON help_acceptances (worker_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications (user_id, created_at DESC);
```

`help_acceptances.worker_id` era o mais urgente: avaliado pelo RLS em TODAS as queries à tabela, não só em queries explícitas da app. M3 (índice de notificações) agrupado aqui por ser a mesma classe de fix — índice ausente confirmado por grep de todas as migrations anteriores.

#### P-FA6 — DEFAULT de `help_acceptances.status` corrigido

`ALTER TABLE help_acceptances ALTER COLUMN status SET DEFAULT 'pending';`

O DEFAULT `'accepted'` causava rejeição silenciosa de qualquer INSERT que omitisse `status` (RLS WITH CHECK `status = 'pending'` bloqueava com count=0, sem erro visível). Só rows futuras são afectadas — rows existentes não mudam.

#### M5 — policy SELECT para cliente em `help_requests` alargada

`DROP POLICY IF EXISTS "Cliente vê help requests pendentes de aprovação" ON help_requests; CREATE POLICY "Cliente vê help requests dos seus jobs" ON help_requests FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM job_requests WHERE id = help_requests.job_id AND client_id = auth.uid()))` — a policy anterior (migration 0003) só cobria `pending_approval`; a nova cobre todos os estados para jobs do próprio cliente.

### T6 — 5 tipos de notificação adicionais resolvidos em `notification_handler.dart`

Adicionada navegação precisa para 5 tipos anteriormente ausentes do switch de `NotificationHandler`:

| Tipo | `relatedId` | Acção |
|---|---|---|
| `newJobInRadius` | `job_id` | `context.push('/worker/job/${relatedId}')` |
| `proposalReceived` / `proposalWithdrawn` | `job_id` | `context.push('/client/job/${relatedId}')` |
| `proposalRejected` | `job_id` | `context.push('/worker/job/${relatedId}')` |
| `proposalAccepted` | `job_id` | fetch `fetchAcceptedProposalForJob(jobId)` → `context.push('/worker/my-job/${proposal.id}?jobId=${relatedId}')` |

`proposalAccepted` requer fetch assíncrono porque `relatedId = job_id` mas a rota precisa de `proposalId` — reutilizado o padrão async já existente para `helpRequestApproved`/`helpWithdrew`.

`helpAccepted`/`helpJobCancelled`: mantidos com `extra: {'initialTabIndex': 1}` — avaliado que passar um `int` primitivo em `extra` para um ecrã de lista é seguro (sem objeto de domínio stale, sem crash risk; pior caso é degradação de UX para tab errada).

`helpRequestReopened`: mantido com `context.push('/worker/help-requests')` (descoberta) — destino correcto para o worker re-candidatar-se ao slot reaberto.

**T6 ainda aberto:** `jobCancelled`, `jobReopened`, `rescheduleProposed`, `rescheduleAccepted`, `rescheduleRejected`, `jobMarkedDone`, `jobCompleted` — navegam para lista genérica. Fix: push para `/client/job/$relatedId` ou `/worker/my-job/$proposalId?jobId=$relatedId` conforme role. Worker paths requerem `fetchAcceptedProposalForJob(relatedId)` para obter `proposalId`.

**`flutter analyze`:** limpo após todas as alterações (0 issues).

---

## 2026-06-29 — T4 corrigido: ordering race entre ref.invalidate() e router.go() em _markCompleted()

Causa raiz: `ref.invalidate()` chamado **antes** de `router.go()` no caminho de sucesso de `_markCompleted()` em `worker_my_job_detail_screen.dart`. As três invalidações (`scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobsInRadiusProvider`) disparavam notificações síncronas ao `WidgetRef` do ecrã, registando-o como dependente ativo a reconstruir. De seguida, `dialogNavigator.pop()` e `router.go('/worker/home')` iniciavam a desmontagem do ecrã — mas o `WidgetRef` ainda estava na lista `_dependents` dos elementos de provider que tinham acabado de notificá-lo. O `ProviderElement.dispose()` do Riverpod asserta `_dependents.isEmpty`, falhando com `'_dependents.isEmpty': is not true`. Agravado pelo bloco `finally` que chamava `setState()` com `mounted == true` após a navegação já ter sido iniciada, agendando mais uma reconstrução.

**Fix aplicado:** reordenação no caminho de sucesso para `pop → go → snackBar → invalidate`. A invalidação acontece depois do ecrã já ter começado a sair da árvore — o `WidgetRef` está a ser limpo, não a receber notificações novas. Adicionado `navigatedAway = true` antes de `router.go()`; bloco `finally` alterado para `if (!navigatedAway && mounted) setState(...)`, eliminando o `setState` supérfluo no caminho de sucesso.

**Lição geral:** nunca invalidar providers **antes** de uma navegação que vai desmontar o ecrã atual. A invalidação dispara `notifyListeners()` síncronos — se o `WidgetRef` do ecrã for dependente do provider, é marcado como dirty. Se a desmontagem começar antes do rebuild ser processado, o Riverpod encontra a inconsistência na limpeza de dependentes. A regra de ouro: `navigate → then invalidate`, não `invalidate → then navigate`.

**Candidatos adicionais da mesma classe de bug identificados em `client_job_detail_screen.dart` — corrigidos preventivamente na sessão seguinte:** linhas 80-84 (cancel open job), 130-141 (cancel confirmed job), 374-378 (accept proposal). Ver entrada seguinte.

---

## 2026-06-29 — Bug do nome/avatar do candidato no lobby corrigido

Causa: 3.º waterfall (`profileSummaryProvider` por candidato) mascarava erros silenciosamente via `?? {}` e mostrava `'—'` enquanto carregava. Fix: join direto de `profiles` na query de `fetchCandidatesForHelpRequest`, eliminando o waterfall e a possibilidade de erro mascarado.

**Detalhe técnico do join:** `help_acceptances.worker_id` aponta para `worker_profiles(profile_id)` e NÃO diretamente para `profiles(id)`. O join correto é de dois saltos via PostgREST embedded resources: `.select('*, worker_profiles(profiles(full_name, avatar_url))')`. A FK sugerida originalmente `profiles!help_acceptances_worker_id_fkey` seria inválida (não existe essa FK direta). O JSON aninhado é desserializado em `HelpAcceptance.fromJson` via `json['worker_profiles']?['profiles']`. `HelpAcceptance` passou a ter os campos `fullName` e `avatarUrl` (ambos `String?`). O bloco `profileSummaries` e as funções `nameOf`/`avatarOf` do `worker_help_requests_lobby_screen.dart` foram removidos; os cards passam a ler `c.fullName ?? 'Sem nome'` e `c.avatarUrl` diretamente.

---

## 2026-06-29 — T2 corrigido: overflow no card de contacto do worker

T2 corrigido. Nome do worker no card de contacto envolvido em `Expanded` + `TextOverflow.ellipsis`, eliminando o overflow de 52px confirmado em dispositivo real.

**Ficheiros alterados:**
- `client_job_detail_screen.dart` — `_workerContactCard()`: Row do nome e Row da data/hora do agendamento, ambos sem `Expanded`. Dois textos dinâmicos (nome do worker, output de `_formatConfirmedSchedule()`) agora envolvidos em `Expanded(child: Text(..., overflow: TextOverflow.ellipsis, maxLines: 1))`.
- `worker_my_job_detail_screen.dart` — card de contacto do cliente (linhas ~640-652): Row do nome do cliente com `Text(info['full_name'])` sem `Expanded` — mesma classe de bug, corrigido preventivamente com o mesmo padrão.

**Outros Rows inspecionados e confirmados seguros:** reschedule banner (ambos os ficheiros), awaiting-completion banner, status banners (rejected, superseded, pending), rating card — todos já tinham `Expanded`. `Text('Trabalho avaliado')` (linha ~994, `client_job_detail_screen.dart`) é string estática de 16 chars, sem risco de overflow.

---

## 2026-06-29 — Fix preventivo do padrão T4 em 3 locais de client_job_detail_screen.dart

Aplicado o mesmo padrão de reordenação do T4 a 3 locais de `client_job_detail_screen.dart` que tinham a mesma classe de risco de `_dependents.isEmpty`, antes de crashar em produção.

**Locais corrigidos:**
- `_cancelJob` (path `job.status == open`): `_cancelOpenJob` block — `cancelJob()` → `navigatedAway = true` → `router.go('/client/jobs')` → snackBar → `invalidate` ×2. Guard `!navigatedAway && mounted` no `finally`.
- `_cancelJob` (path `job.status == confirmed`): mesmo padrão — `newJobId` capturado antes, navega primeiro, snackbar condicional (newJobId != null), depois invalidate. Guard `!navigatedAway && mounted` no `finally`.
- `_acceptProposal`: sem `finally` — apenas reordenação: `acceptProposal()` → `router.go('/client/jobs')` → snackBar → `invalidate` ×2. Sem guard necessário (catch block só reseta estado de erro, não existe `finally`).

**Por que só estes 3:** as funções de reschedule (`_proposeReschedule`, `_acceptReschedule`, `_rejectReschedule`) invalidam `jobByIdProvider(widget.jobId)` (watched pelo ecrã) mas **não navegam para fora** — o ecrã permanece na árvore e o rebuild da invalidação é processado normalmente. `_confirmJobCompletion` invalida `clientJobsProvider` (não watched pelo ecrã) antes de navegar — sem risco. Confirmado por grep exaustivo do ficheiro.

---

## 2026-06-29 — 3 bugs reais na área de ajudantes corrigidos via migration 0026

Investigação completa de 3 bugs confirmados em `help_requests`. Causa raiz identificada em todos os 3; migration `0026_helper_lobby_fixes.sql` criada — **NÃO aplicada, aplicar manualmente via Supabase SQL Editor.**

**(1+2) Policy SELECT em falta para o worker principal em `help_requests` (gap C3.2)** — causava dois comportamentos distintos:
- `createHelpRequest()` lançava exceção em Dart: o INSERT tem WITH CHECK correto e passa (proposta accepted verificada), mas o `.select('id').single()` encadeado usa `RETURNING id` internamente (PostgREST `Prefer: return=representation`). O `RETURNING` está sujeito a RLS SELECT — sem policy SELECT para o principal, devolve 0 rows e `.single()` lança. A row **fica na BD**; Dart vê exceção. Fix: `CREATE POLICY "Worker principal vê os seus help requests" ON help_requests FOR SELECT USING (EXISTS (SELECT 1 FROM job_proposals WHERE id = proposal_id AND worker_id = auth.uid()))`.
- Lobby vazio (`WorkerHelpRequestsLobbyScreen`): `fetchHelpRequestsForJob()` é um SELECT PostgREST direto em `help_requests`; sem policy SELECT, o principal obtém sempre 0 rows mesmo havendo rows na BD. Fix: mesma policy.

**(3) Exclusão `NOT EXISTS` em falta em `get_help_requests_in_radius`** — depois de se candidatar a um help_request, o worker continuava a vê-lo na lista de descoberta porque a função não exclui help_requests onde o caller já tem uma `help_acceptance`. Item catalogado como A2/cluster η nas melhorias da Fase 9 (improvements.md) desde a auditoria original — nunca implementado em nenhuma migration subsequente (0008–0025), não era uma regressão. Fix: `AND NOT EXISTS (SELECT 1 FROM help_acceptances ha WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid())` adicionado ao WHERE da função.

**Lição geral registada:** qualquer `.insert().select().single()` está sujeito a RLS SELECT no `RETURNING`, não só a RLS INSERT. Verificar SEMPRE que existe policy SELECT correspondente antes de assumir que um INSERT funcional implica leitura funcional.

---

## 2026-06-29 — A2 Prompt B: /worker/my-job/:id e /worker/job/:id/help-requests convertidos para ID-based routing

Route `/worker/my-job/:id` usa query param `?jobId=` para carregamento paralelo (decisão 2026-06-29, evita cascade sequencial proposta→job). `WorkerMyJobDetailScreen` reescrito com `required this.proposalId, required this.jobId` (ambos String): ambos os providers observados em paralelo no topo de `build()`, `liveStatus`/`liveJobStatus` simplificados — providers são a única fonte, fallback para widget eliminado. Route `/worker/job/:id/help-requests` simplificada para só `jobId`; `WorkerHelpRequestsLobbyScreen` usa `acceptedProposalForJobProvider(widget.jobId)` para obter proposta, `_suggestedRate()` aceita `JobProposal?` nulo, degrada para taxa 0 com validação existente `> 0` no sheet. `notification_handler.dart` simplificado nos dois casos de help_request (`helpRequestApproved`, `helpWithdrew`): pre-fetch manual de job+proposal removido — o fetch do `help_request` permanece apenas para resolver `job_id` a partir do `help_request_id` (confirmed: `related_id` IS `help_request_id`). `flutter analyze` limpo. Completa A2 — fecha P6 (todas as 4 rotas convertidas), resolve T1/T3 nestes 2 ecrãs finais, desbloqueia T6.

## 2026-06-29 — A2 Prompt A: /client/job/:id e /worker/job/:id convertidos de state.extra para ID-based routing

`state.extra! as JobRequest` removido das duas rotas — elimina o crash T3 (nullable extra em deep-link/notification) e o problema T1 (snapshot estático diverge do provider quando o job muda). Ambas as telas passam a receber `jobId: String` e carregam dados via `jobByIdProvider(jobId)` que já existia. Call sites (`client_jobs_screen.dart`, `worker_home_screen.dart`) simplificados — `extra: job` removido. `_job.copyWith()` optimistic updates substituídos por `ref.invalidate(jobByIdProvider(...))`. `/worker/my-job/:id` e `/worker/job/:id/help-requests` ficam para Prompt B (dependência de cascade loading com proposal).

## 2026-06-29 — T5: cancelamento de job confirmado pelo cliente agora opt-in (migration 0025)

**Problema confirmado:** `cancel_job` RPC aplicava reabertura automática ao path do cliente (quando `reopen_count_client < 1`) sem pedir consentimento. Comportamento correto apenas para o worker — quando o worker cancela, faz sentido encontrar um substituto; quando o cliente cancela, não.

**Inspeção direta do SQL (0013) revelou:** o `array_append` de `excluded_worker_ids` já estava dentro de `IF v_is_worker THEN` — a exclusão do worker nunca se aplicava ao path do cliente. O único problema real era a reabertura sem consentimento.

**Decisão de produto (2026-06-29):** cancelamento de job confirmado pelo cliente mostra dois diálogos sequenciais:
1. `CancelJobDialog` — picker de razão (existente, inalterado)
2. Novo dialog — "Voltar a publicar? Queres voltar a publicar este pedido para encontrar outro prestador?" (Sim/Não)

A reabertura só acontece se o cliente carregar em Sim E `reopen_count_client < 1`. Sem exclusão de workers no path do cliente — a exclusão é uma medida de responsabilização do worker, não se aplica aqui.

**Worker path completamente inalterado:** auto-reabre sempre (dentro do limite de 2), exclui sempre o worker que cancelou, notifica o cliente com `job_reopened`.

**Ficheiros alterados:**
- `supabase/migrations/0025_cancel_job_client_reopen_choice.sql` — DROP overload antigo + CREATE com `p_client_wants_reopen boolean DEFAULT NULL`. **NÃO aplicado — aplicar manualmente via Supabase SQL Editor.**
- `lib/features/jobs/data/job_repository.dart` — `cancelJob()` aceita `bool? clientWantsReopen`, só passa ao RPC quando não null.
- `lib/features/jobs/presentation/client_job_detail_screen.dart` — segundo dialog após CancelJobDialog; passa `clientWantsReopen` ao repository.

---

## 2026-06-29 — Sessão de testes manuais extensa: 6 bugs reais encontrados (T1-T6)

Henrique testou a app em dispositivo físico. 6 findings confirmados por observação direta (screenshots 1-6). Documentados em `improvements.md` — secção "Sessão de testes manuais — 2026-06-29" com códigos T1-T6.

**Resumo dos findings:**
- **T1** — Desync de estado de propostas: home mostra "1 proposta", detalhe do mesmo job mostra "À espera de proposta". Resolvido por force-close; confirma divergência entre snapshot stale em `state.extra` e estado real da BD.
- **T2** — Overflow de renderização no card de contacto do worker (`client_job_detail_screen.dart`, método `_workerContactCard`): "OVERFLOWED BY 52 PIXELS" na borda direita.
- **T3** — Red screen: `Null check operator used on a null value` durante navegação na área de lista de jobs. Alta correlação com P6 (`state.extra!` sem fallback em 4 rotas).
- **T4** — Red screen: `'_dependents.isEmpty': is not true` — assertion Flutter de ChangeNotifier/InheritedWidget, reproduzido duas vezes no fluxo de "Confirmar conclusão?" em `worker_my_job_detail_screen.dart`. Bug mais crítico da sessão por ser hard crash consistentemente reproduzível.
- **T5** — Lógica de cancelamento invertida: quando o **cliente** cancela, o RPC `cancel_job` recria o job e exclui o worker — comportamento desenhado para quando é o **worker** que cancela. O branch de reopen+exclusão não distingue o caller.
- **T6** — Gap de routing de notificações elevado a prioridade alta. Henrique confirmou explicitamente: *"a notificação deve levar o utilizador ao sítio exato a que se refere, não a uma lista genérica."* T1 e T3 são provavelmente sintomas diretos desta lacuna. P6 e P-8-9 re-priorizados de gap diferido para Tier 0/1 em `improvements.md`.

**Nenhum ficheiro `.dart` ou `.sql` foi alterado nesta sessão — só documentação.**

---

## 2026-06-28 — Substituído loadingExempt por fix estrutural no redirect()

`loadingExempt` (allowlist de rotas imunes ao redirect `/loading`) eliminado de `app_router.dart`. Substituído por `return null` incondicional no bloco `if (sessionAsync.isLoading)`.

**Motivo:** a allowlist era uma correção sintomática — crescia sintoma a sintoma (`/worker/setup` → depois três rotas adicionais) sem atacar a causa raiz. A causa raiz: `redirect()` nunca devia redirecionar para `/loading` quando o utilizador já está numa rota estabelecida. Um tick transitório de `isLoading` (ex: refresh de token a cada 60 min) não representa um estado desconhecido — representa uma sessão já resolvida a renovar o seu token. Redirecionar para `/loading` neste momento destrói o widget tree corrente mid-flight (ImagePicker a aguardar, upload em curso, etc.) e descarta trabalho silenciosamente.

**Comportamento correto com `return null`:**
- Arranque a frio (`loc == '/loading'`, `isLoading == true`): fica no spinner — correto.
- Tick mid-session em qualquer rota autenticada: fica onde está — correto.
- `/choose-role` com `extra` após signUp: fica onde está, preserva `fullName`/`phone` — correto.

**Backcompatibility com fixes anteriores:**
- P-67-1: coberto (caso geral inclui o caso específico).
- `/choose-role` extra loss: coberto (return null ≡ allowlist para esta rota).
- `role == null` skip, cross-role guard, worker profile complete: só são alcançados após `!isLoading` — inalterados.
- `loadingExempt` era uma `const List<String>` file-local sem outros usos — removida sem rastos.

**Hipótese:** resolve também o bug de criação de job com foto (mesma causa raiz — tick de token-refresh a meio do submit, entre `createJob` e `uploadJobPhoto`, destrói `_CreateJobScreenState` enquanto a sequência de upload está a aguardar). Diagnostic logging em `job_repository.dart`/`create_job_screen.dart` **mantido propositadamente** até confirmação por teste real — remover só depois.

---

## 2026-06-28 — loadingExempt expandido: P-67-1 era instância de classe de bug mais ampla

Confirmado via bug real reportado por Henrique (logcat + reprodução): qualquer rota com `ImagePicker` (ou outro `await` sobre interação OS assíncrona longa) está vulnerável ao mesmo redirect `/loading` → home que destrói silenciosamente a foto em curso. O guard `if (!mounted) return;` é defensivo mas o dano já está feito antes de disparar — o `State` foi descartado pelo router antes do picker retornar.

A fix original de P-67-1 (2026-06-26) adicionou apenas `/worker/setup` a `loadingExempt`. A investigação de 2026-06-28 confirmou que mais três rotas com `ImagePicker` estavam desprotegidas:

| Rota | Interação OS | Resultado sem fix |
|---|---|---|
| `/worker/profile` | `ImagePicker` + `Geolocator.requestPermission` / `getCurrentPosition` | Avatar não muda; picker retorna com `!mounted` |
| `/client/profile` | `ImagePicker` | Avatar não muda; picker retorna com `!mounted` |
| `/client/create-job` | `ImagePicker` + `Geolocator.requestPermission` / `getCurrentPosition` | Foto descartada; picker retorna com `!mounted` |

Todas três adicionadas a `loadingExempt` em `app_router.dart` (mesmo ficheiro, mesma lista, mesma fix class que P-67-1).

**Outras interações OS encontradas — não adicionadas:**
- `launchUrl(LaunchMode.externalApplication)` em `worker_my_job_detail_screen.dart`, `client_job_detail_screen.dart`, `worker_help_requests_screen.dart`, `address_map_link.dart` (widget reutilizável): abre WhatsApp/Maps. O `await` retorna imediatamente (basta iniciar o intent), não aguarda o utilizador regressar. Quando regressa, o tick de auth pode disparar, causando navegação para home — incómodo mas sem perda de dados. Não adicionado a `loadingExempt` por agora (diferente mecanismo, sem in-flight async ao regressar).
- `showDatePicker` / `showTimePicker`: dialogs Flutter in-app, não atividades Android. Não backgroundam o engine, não disparam tick de auth. Seguros.
- `Geolocator.distanceBetween()`: síncrono, sem interação OS. Seguro.

**Lição:** ao corrigir este tipo de bug no futuro, verificar TODAS as rotas com interações OS assíncronas de uma vez, não rota a rota.

---

## 2026-06-28 — Desbloqueado fluxo `pending_approval` (inventário backend-sem-UI)

Dois pontos de entrada de UI adicionados para o fluxo de expansão de equipa pós-confirmação, identificado no inventário de 2026-06-28 como "backend completo, zero UI".

### Lado do principal (`worker_my_job_detail_screen.dart`)

Botão **"Adicionar ajudante"** (`OutlinedButton.icon`, ícone `group_add_outlined`) dentro do bloco `liveJobStatus == JobStatus.confirmed`. Toca abre um `showModalBottomSheet` com `StatefulBuilder`:
- Stepper de quantidade (mín. 1) — `slotsNeeded`
- `CheckboxListTile` "Exigir equipamento próprio" — `equipmentRequired`
- Botão "Enviar pedido" chama `createHelpRequest(createdPostConfirmation: true)` → cria `help_request` com status `pending_approval`
- Sucesso: SnackBar "Pedido de ajuda enviado para aprovação do cliente." + invalida `helpRequestsForJobProvider`
- Removido o card placeholder "A funcionalidade de equipa estará disponível em breve." (já não necessário)

### Lado do cliente (`client_job_detail_screen.dart`)

Card **`_PendingHelpRequestCard`** (widget privado, cor `secondaryContainer`) injetado na secção `confirmed` logo após o `_workerContactCard`. Aparece para cada `help_request` com `status == pending_approval` (RLS já filtra — clientes só veem `pending_approval`):
- Ícone + texto "O prestador pediu ajuda extra para este trabalho"
- Linha de detalhe: nº de ajudantes + indicador de equipamento
- Botão "Aprovar equipa" chama `approveHelpRequest(helpRequestId)` → muda para `open`, notifica principal
- Sucesso: SnackBar "Equipa aprovada! O prestador pode agora procurar ajudantes." + invalida `helpRequestsForJobProvider`
- Se não houver `pending_approval` para o job, nada é renderizado (sem clutter de estado vazio)

### Notificação `helpRequestApproved` — sem alteração necessária

`notification_handler.dart` já encaminha `helpRequestApproved` para o lobby do principal com job + proposal objects resolvidos (`/worker/job/{jobId}/help-requests`). O fluxo de ponta a ponta está completo sem alteração no handler.

---

## 2026-06-27 — RCB1 + RCB2 + RCB3 (migration 0023 + 1-line Dart fix)

### RCB1 — `withdraw_help_acceptance`: guarda de job-status adicionada

A função não validava o estado do job pai — um ajudante podia "desistir" de um job
já `completed` ou `cancelled`, o que enviava notificações `help_request_reopened`
para uma vaga que já não existia.

**Fix (migration 0023):** adicionado `v_job_status text` ao DECLARE e, depois das
validações de propriedade e status da candidatura, um SELECT que lê
`job_requests.status` via `help_requests.job_id`. Se o job não estiver em
`'confirmed'` ou `'awaiting_confirmation'`, a função lança exceção antes de qualquer
UPDATE ou notificação.

### RCB2 — `cancel_job`: ajudantes aceites passam para `'cancelled'`

A cascata de `cancel_job` (desde migration 0007) rejeitava apenas candidaturas
`pending`, deixando as `accepted` no estado `'accepted'` indefinidamente após o
job cancelar.

**Decisão RC1 (Henrique):** reutilizar `'cancelled'` existente — *"foi só cancelado
é info suficiente"*. Nenhum novo status necessário.

**Fix (migration 0023):** um segundo `UPDATE help_acceptances SET status = 'cancelled'
WHERE status = 'accepted'` adicionado **depois** do INSERT de notificações
`help_job_cancelled` (que faz SELECT WHERE ha.status = 'accepted'). A ordem é
intencional: a notificação precisa de encontrar os helpers ainda em `'accepted'`
antes de os mover.

### RCB3 — Texto de `job_reports` corrigido

`client_job_detail_screen.dart:266` — substituído:
> "Descreve o que aconteceu. A nossa equipa vai rever o caso."

por:
> "Descreve o que aconteceu. O teu relato fica registado para referência futura."

`job_reports` é write-only (sem trigger, sem webhook, sem notificação). A promessa
de revisão era falsa e poderia criar expectativas erradas nos utilizadores.

---

## 2026-06-27 — RC3 fix: ajudantes passam a ver logística do job (migration 0022)

### Contexto

Revisão conceptual 2026-06-27 (RC3 em `improvements.md`) identificou que um ajudante
aceite não via dentro da app: data/hora confirmada, endereço do trabalho, nem contacto
do prestador principal. Tinha de obter essa informação fora da app.

### Extensão de `get_my_help_acceptances` (migration 0022)

Mesmo padrão DROP + CREATE de migration 0021 (mudança de shape de RETURNS TABLE).
Novos campos adicionados ao SELECT existente — o JOIN com `profiles p` já existia
(para `principal_name`), bastou acrescentar `p.phone` e os campos de `job_requests`:

| Coluna nova | Fonte | Notas |
|---|---|---|
| `confirmed_date` | `jr.confirmed_date` | nullable — null até job confirmado |
| `confirmed_time` | `jr.confirmed_time` | nullable — "HH:MM:SS" do PostgreSQL |
| `address_text` | `jr.address_text` | string vazia se não preenchida |
| `location_lat` | `jr.location_lat` | numeric |
| `location_lng` | `jr.location_lng` | numeric |
| `principal_phone` | `p.phone` | nullable — string vazia se null |

`HelpAcceptanceSummary` (Dart) extendido com 6 campos retrocompatíveis (defaults
seguros: `null` para datas, `''` para strings, `0.0` para coords).

### Widget reutilizável: `AddressMapLink`

`lib/core/widgets/address_map_link.dart` — `StatelessWidget` que:
- Recebe `address` (String), `lat` (double), `lng` (double)
- Renderiza uma linha tappable (ícone de mapa + texto sublinhado + seta de abertura)
- Abre `https://www.google.com/maps/search/?api=1&query=lat,lng` via `url_launcher`
  (`LaunchMode.externalApplication` — mesmo modo usado para WhatsApp)
- Padding idêntico ao `_infoRow` existente (6px vertical) para manter consistência visual

Aplicado em dois locais:
- `worker_help_requests_screen.dart` — `_AcceptedCard`: ajudante vê data agendada,
  link de mapa e botão WhatsApp para o principal (todos condicionais: só renderiza se
  o campo não for null/vazio)
- `worker_my_job_detail_screen.dart` — prestador principal: endereço do job passa de
  `_infoRow` estático para `AddressMapLink` tappable

### Cliente explicitamente excluído

`AddressMapLink` não é adicionado a nenhum ecrã de cliente. O cliente criou o job e
conhece o endereço — não precisa de direções para o seu próprio local.

---

## 2026-06-26 — Fase 11 (Avaliações): design e implementação

### Quatro relações de avaliação

| Quem avalia | Quem é avaliado | RPC | Notas |
|---|---|---|---|
| Cliente | Prestador principal | `submit_client_rating` | Nota propaga-se também a cada ajudante; comentário fica só no registo do principal |
| Cliente | Cada ajudante aceite | `submit_client_rating` (propagação automática) | Sem comentário; idempotente via ON CONFLICT DO NOTHING |
| Prestador principal | Cliente | `submit_principal_rating` | `p_ratee_id` = `client_id` |
| Prestador principal | Cada ajudante | `submit_principal_rating` | `p_ratee_id` = `worker_id` do ajudante |
| Ajudante | Prestador principal | `submit_helper_rating` | Principal auto-resolvido a partir de `accepted_proposal_id` |

### Decisão UX: Option A — inline, sem popup, sem novo tipo de notificação

Rejeitadas: notificação `rating_reminder` (custo de infra + noise) e popup automático (padrão intrusivo). A UI de avaliação é um card persistente no bloco "completed" de cada ecrã. O utilizador vê o prompt sempre que abre o detalhe de um trabalho concluído até avaliar.

### Constraint nova: `check_rater_not_ratee`

`ALTER TABLE ratings ADD CONSTRAINT check_rater_not_ratee CHECK (rater_id <> ratee_id)` — adicionado em migration 0021 para impedir auto-avaliação que os RPCs SECURITY DEFINER já proibiam por lógica mas não por constraint.

### `get_my_help_acceptances` atualizado (migration 0021)

Adicionadas colunas `job_id` e `principal_worker_id` ao resultado do RPC. Necessário para que `_AcceptedCard` consiga chamar `submit_helper_rating(p_job_id)` sem round-trip extra. `HelpAcceptanceSummary` tratado como retrocompatível: novos campos têm default `''` quando o RPC antigo não os devolve.

### Novo RPC `get_accepted_helpers_for_job(p_job_id)`

Usado pelo ecrã do prestador principal para listar ajudantes aceites com nome, para mostrar um card de avaliação individual por ajudante. Só retorna resultados se `jp.worker_id = auth.uid()` (caller é o principal).

### Provider para multi-ratee: `myRatingForJobAndRateeProvider((String, String))`

Chave é record Dart 3 `(jobId, rateeId)`. Necessário porque o principal tem múltiplos ratees por job (cliente + N ajudantes), cada um com estado de avaliação independente. Os rating cards do principal são `ConsumerStatefulWidget` privados que fazem o seu próprio watch.

---

## 2026-06-26 — Sessão 7 (quick wins): friendlyError, foto compressão, maybeSingle, _mapError

### Grupo 1 — friendlyError em 4 ecrãs (P-67-3, P-67-4, P-8-6)

`client_profile_screen.dart:97` — SnackBar de erro mostrava exceção em bruto; substituído por `friendlyError(e)`.
`worker_setup_screen.dart:384`, `worker_profile_screen.dart:452`, `create_job_screen.dart:281` — mesmo fix no widget `error:` de `serviceTypesAsync.when`.

### Grupo 2 — Compressão de fotos (P-8-3)

`job_repository.dart:58` — `minWidth`/`minHeight` 1280 → 800, `quality` 72 → 60. Alinhado com decisão de 2026-06-02 (limite 50MB do Free Plan).

### Grupo 3 — Auth UX pré-lançamento (P-67-5, P-67-6)

`worker_setup_screen.dart:178` — `.single()` → `.maybeSingle()` + null check com mensagem acionável "Perfil de utilizador não encontrado. Tenta fazer login novamente." (evita PGRST116 opaco em signup parcialmente falhado).
`auth_controller.dart:_mapError` — adicionados handlers para `email_not_confirmed` e `rate_limit`/`over_request_rate_limit` antes do fallback genérico. Necessário antes de reativar verificação de email para o launch.

---

## 2026-06-26 — P-8-1 + P-10-3 corrigidos (migration 0020, não aplicada)

Confirmado via live query directo por Henrique: `auto_confirm_completed_jobs` existe e está
agendado de 3h em 3h, mas só notificava o worker. `auto_expire_jobs` não existia.

**Migration 0020** criada localmente (`0020_no_response_cron_and_client_notify.sql`):
- `auto_expire_jobs()` — novo função SECURITY DEFINER com `FOR UPDATE SKIP LOCKED`,
  transição `open → no_response` quando `expires_at < now()` e `proposal_count = 0`,
  notificação `job_no_response` ao cliente. Cron job `'auto-expire-jobs'` com schedule `0 */3 * * *`.
- `auto_confirm_completed_jobs()` — recreada com second INSERT para `v_job.client_id`
  com tipo `job_completed` e body distinto ("sem resposta" vs "sem confirmação" para o worker).

**Dart:**
- `notification_handler.dart` — `jobNoResponse`: invalida `clientJobsProvider`, navega `/client/jobs`.
- `notification_providers.dart` — `jobNoResponse`: invalida `clientJobsProvider`.
- `notification_providers.dart` — `jobCompleted`: adicionado `clientJobsProvider` (necessário
  pois o cliente agora recebe `job_completed` via cron; o double-invalidate para confirmação
  manual é inócuo).

**NÃO aplicada à BD viva.** Aplicar via SQL Editor. Verificar após aplicar:
```sql
SELECT jobname, schedule, active FROM cron.job
WHERE jobname IN ('auto-expire-jobs', 'auto-confirm-completed-jobs');
```

---

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

## 2026-06-26 — P-FA2 + P-FA7 corrigidos via migration 0019 + Dart

### Confirmação via live query

Query directa ao `pg_policy` (2026-06-26) confirmou que **não existe nenhuma DELETE policy** em `storage.objects` para o bucket `job-photos`. A auditoria original (P-FA2) diagnosticou a policy de 0001 como "não-funcional" — o diagnóstico mais exacto é "ausente": a policy do 0001 nunca chegou a existir na BD viva, ou foi dropada em algum momento sem registo. Igualmente, **nenhuma DELETE policy existe na tabela `job_photos`** (P-FA7 confirmado).

### Causa-raiz: path incompatível com auth.uid()

Com o path de upload antigo `$jobId/<timestamp>.jpg`, `storage.foldername(name)[1]` extrai o `job_id` (UUID do job), não o `auth.uid()` (UUID do cliente). Mesmo que a storage DELETE policy tivesse existido, nunca poderia funcionar com este path.

### Correcção

**Dart — `job_repository.dart`:** `uploadJobPhoto` recebe agora `required String clientId`. Path de upload alterado de:
```
$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg
```
para:
```
$clientId/$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg
```
Com o novo path, `storage.foldername(name)[1]` extrai `clientId` = `auth.uid()` para o cliente que criou o job.

**`create_job_screen.dart:190`:** call site actualizado para passar `clientId: user.id` (variável já em scope na mesma função).

**Migration 0019:** cria dois blocos em simultâneo:
1. Storage DELETE policy `"job-photos: delete pelo dono"` usando `foldername(name)[1]` — agora correcto com o novo path.
2. Table DELETE policy `"Client apaga fotos do seu job"` em `job_photos` — verifica ownership via EXISTS subquery em `job_requests`.

### Caveat: fotos anteriores

Fotos já existentes na BD têm o path antigo (`$jobId/<timestamp>.jpg`). Para essas, `foldername(name)[1]` continua a extrair o `job_id` — não o `client_id` — e a nova storage DELETE policy não as abrange. Sem impacto: a app não tem ainda UI de apagamento de fotos.

### Estado

**Migration 0019 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

---

## 2026-06-26 — P-FA3 (CRÍTICO) corrigido via migration 0018

### Confirmação do bug via pg_policy

Query directa ao `pg_policy` (2026-06-26) confirmou que a policy de UPDATE de avatars (`"Update avatar pelo próprio utilizador"`) usava `(storage.foldername(name))[1]` — incompatível com o path real `$userId.jpg` (ficheiro no root do bucket, sem subpasta) usado pelo app em `worker_repository.dart:142` e `client_repository.dart:24`.

`storage.foldername('abc-uuid.jpg')` num ficheiro root-level devolve `{}` (array vazio); `[1]` é NULL; `auth.uid()::text = NULL` avalia a NULL (falso em PostgreSQL). A policy bloqueia silenciosamente todos os re-uploads.

O fix interativo de 2026-06-15 corrigiu **apenas a policy de INSERT** (primeiro upload de avatar) — a policy de UPDATE ficou por corrigir, o que significa que qualquer re-upload de avatar (mudança de foto de perfil após a primeira) estava a falhar silenciosamente em produção.

A policy de DELETE foi confirmada **totalmente ausente** da BD viva via pg_policy.

### Step 1 — Diagnóstico de impacto em utilizadores reais

Query de diagnóstico (requer acesso directo à BD — assistente não pode executar):
```sql
SELECT id, avatar_url, updated_at
FROM   profiles
WHERE  avatar_url IS NOT NULL
ORDER  BY updated_at DESC
LIMIT  10;
```
**Resultado: pendente** — executar manualmente para determinar se algum avatar foi actualizado com sucesso após o primeiro upload. Se `updated_at` de alguma linha for significativamente posterior a `created_at`, indica que o UPDATE path funcionou (ou que o utilizador re-fez upload e o INSERT policy foi avaliado porque o ficheiro não existia por outra razão). Se todos os avatars mostram `updated_at ≈ created_at`, é provável que nenhum utilizador alguma vez conseguiu mudar a foto de perfil com sucesso.

### Correcção (migration 0018)

- DROP de `"Update avatar pelo próprio utilizador"` (nome confirmado via pg_policy) e de `"avatars: update pelo dono"` (nome do 0001) por idempotência.
- CREATE policy de UPDATE com `regexp_replace(storage.filename(name), '\.[^.]+$', '')` — extrai UUID do filename sem extensão.
- CREATE policy de DELETE com a mesma lógica (DROP precautório de ambas as denominações possíveis).
- `storage.filename()` escolhido por ser sibling function de `storage.foldername()` (já confirmada funcional na BD viva pela sua presença nas policies existentes).

### Estado

**migration 0018 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

Após aplicar, verificar:
```sql
SELECT polname, cmd,
       pg_get_expr(polqual,      polrelid) AS using_expr,
       pg_get_expr(polwithcheck, polrelid) AS withcheck_expr
FROM   pg_policy
WHERE  polrelid = 'storage.objects'::regclass
  AND  polname  LIKE 'avatars%'
ORDER  BY polname;
```
Confirmar que `"avatars: update pelo próprio utilizador"` e `"avatars: delete pelo próprio utilizador"` aparecem com `regexp_replace(storage.filename(name)...)` nas expressões USING/WITH CHECK, e que `"Update avatar pelo próprio utilizador"` e `"avatars: update pelo dono"` desapareceram.

---

## 2026-06-26 — Sessão 3: lobby de ajudantes reestruturado; P-9-1 implementado (migration 0017)

### Bug real confirmado por Henrique — candidatos além da contagem visível não podiam ser aceites

O lobby usava um modelo de "grelha de N vagas fixas": cada vaga era mapeada a um candidato por ordem de chegada. Candidatos além do `slots_needed` ficavam marcados como `isOverflow = true` e eram não acionáveis — o botão de aceitar não aparecia. Isto era ERRADO: com 3 vagas e 5 candidatos pending, o principal só podia aceitar os primeiros 3. Os candidatos 4 e 5 ficavam invisíveis ao processo de seleção, mesmo com vagas abertas.

**Decisão de produto confirmada:** o principal pode escolher QUAIS candidatos aceitar entre TODOS os pending, não por ordem de chegada. Exemplo: 3 vagas, 5 candidatos — pode aceitar o 1.º, 4.º e 5.º especificamente, rejeitando o 2.º e 3.º.

### Mudança na UI: de "grelha de N vagas" para "lista de candidatos"

Lobby reestruturado em `worker_help_requests_lobby_screen.dart`:
- Removido `_SlotVM`, `_buildSlots()`, `_summaryCaption()`, `_SlotCard` e o conceito `isOverflow`
- Adicionado `_CandidateCard` — card tipo ListTile com avatar, nome, equipamento, taxa (se aceite), e botões de aceitar/rejeitar
- Cabeçalho por help_request: `"X de Y vagas preenchidas"` (conta real, não grid)
- Secção "Aceites" — candidatos aceites com taxa e checkmark, não acionáveis
- Secção "Por decidir" — TODOS os candidatos pending, cada um com botão "Aceitar" ativo e botão X de rejeição
- Guarda client-side: se `accepted_count >= slots_needed` (cache stale antes de refetch), o botão "Aceitar" é desativado; X permanece ativo independentemente do estado

### P-9-1 implementado (migration 0017)

`accept_help_candidate` recriado com loop FOR após o UPDATE que marca `help_request.status = 'filled'`:
- Rejeita todos os pending restantes (`status → 'rejected'`) excluindo o candidato recém-aceite
- Insere notificação `help_rejected` com corpo `'Todas as vagas foram preenchidas.'` para cada um
- Idêntico ao padrão de `auto_confirm_completed_jobs` (migration 0014)

Migration inclui também um DO block de cleanup único: rejeita + notifica todos os `help_acceptances` com `status = 'pending'` cujo `help_request` já está `'filled'` (órfãos de antes desta migration). Idempotente se count = 0. Count de órfãos na BD viva: desconhecido — correr `SELECT COUNT(*) FROM help_acceptances ha JOIN help_requests hr ON hr.id = ha.help_request_id WHERE ha.status = 'pending' AND hr.status = 'filled';` antes de aplicar.

### P-9-2 e P-9-4 fechados por mudança estrutural

P-9-2 ("candidatos overflow não acionáveis") e P-9-4 ("label 'Preenchida' ambígua no card overflow") tornaram-se moot: o modelo de overflow não existe. Não houve fix dirigido — a reestruturação para lista elimina a classe de problema inteiramente.

---

## 2026-06-26 — Sessão 2 da triagem pós-auditoria: P-67-1 e P5 corrigidos em `app_router.dart`

### P-67-1 — `/worker/setup` adicionado a `loadingExempt`

`loadingExempt` passou de `['/loading', '/choose-role']` para `['/loading', '/choose-role', '/worker/setup']`.

**Motivo:** o token Supabase é refrescado automaticamente a cada 60 minutos. Cada refresh dispara `SessionNotifier.build()` → `AsyncValue.loading()` → `RouterNotifier.notifyListeners()` → `redirect()` com `sessionAsync.isLoading = true`. Sem `/worker/setup` na lista de excepções, o redirect enviava o worker para `/loading` e de volta a uma nova instância vazia de `WorkerSetupScreen` — bio, serviços, raio, ferramentas todos perdidos silenciosamente, sem erro nenhum mostrado.

### P5 — Guard cross-role adicionado ao `redirect()`

Adicionado imediatamente após o bloco `role == null`:

```dart
if (role.value == 'client' && loc.startsWith('/worker/')) return '/client/home';
if (role.value == 'worker' && loc.startsWith('/client/')) return '/worker/home';
```

Usa `role.value` string comparison (padrão já existente no ficheiro, não enum identity). Colocado antes dos redirects de "rota pública → home" para evitar duplo redirect.

**Nota de scope:** este guard é uma mitigação parcial. Actualmente (P6 ainda aberto), acesso cross-role às rotas com `state.extra!` causa crash antes de chegar ao ecrã — o guard intercepta antes desse crash. Após P6 ser corrigido (routing baseado em ID), o guard passa a ser a protecção primária contra estado vazio silencioso com dados do UID errado.

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