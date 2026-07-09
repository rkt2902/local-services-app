# LocalServices — Project Status

> Snapshot honesto do estado do projeto. Atualizado em 2026-07-09.
> Sem spin — o que funciona, o que não funciona, o que bloqueia utilizadores reais.

---

## O que funciona end-to-end hoje

**Autenticação**
- Registo (email + password), escolha de role, login, logout.
- Prevenção de alteração de role após registo (trigger `tg_prevent_profile_role_change`).

**Perfil de worker**
- Setup com avatar, tipos de serviço, localização base (geocoding via Nominatim), raio de atuação, ferramentas.
- Avatar: upload com compressão, cache-busting por timestamp, invalidação de provider após setup.
- Edição posterior do perfil.
- `worker_profiles_public` view expõe apenas campos seguros (sem `base_lat`/`base_lng`).

**Criação de pedido (cliente)**
- Serviço, morada (geocoding), data/disponibilidade/urgência/dimensão, descrição, até 2 fotos.
- Fotos comprimidas antes do upload (máx. 800px, qualidade 60%).

**Descoberta de jobs (worker)**
- `get_jobs_in_radius` (PostgREST RPC) filtra por raio e exclui jobs onde o worker já tem proposta.
- Mapa com ícone de localização abre Google Maps com coordenadas do job.
- Lista + detalhe de job com `AddressMapLink`.

**Propostas**
- Worker cria proposta (preço/hora, horas estimadas, data/hora, necessidade de ajuda).
- Cliente vê lista de propostas com nome e avatar do worker.
- Cliente aceita ou recusa; rejeição devolve o job ao mercado.
- `create_proposal` via RPC atómica com check `auth.uid()`.

**Ajudantes (help requests)**
- Worker principal cria `help_request` com nº de vagas e equipamento necessário.
- Workers próximos candidatam-se; principal aprova/rejeita via lobby.
- `help_acceptances.status DEFAULT 'pending'` correto.
- Ajudante vê nome do worker principal (contacto telefónico não surfacado — MVP intencional).

**Ciclo de vida do job**
- `open → confirmed → awaiting_confirmation → completed`.
- Auto-expiração para `no_response` ao fim de 48h (pg_cron, a cada 3h).
- Auto-confirmação para `completed` ao fim de 3 dias em `awaiting_confirmation` (pg_cron, a cada 3h).
- Remarcação: qualquer das partes propõe, a outra aceita/rejeita.
- Cancelamento: cliente cancela job `open` ou `confirmed` (com opção de reabertura).

**Avaliações**
- Cliente avalia worker principal (propaga a todos os ajudantes aceites).
- Worker principal avalia cada ajudante.
- `worker_rating_summary` view com `security_invoker = true`.
- Avaliações visíveis no histórico de jobs.

**Notificações**
- 19 tipos de notificação com navegação deep-link correta.
- `context.go` nos lifecycle events (elimina RT1 keyReservation crash).
- Invalidação correta de providers ao receber cada tipo de notificação.
- Funciona apenas com a app aberta (sem push quando em background — ver Gaps).

**Segurança de dados**
- RLS ativa em todas as tabelas.
- `accept_proposal`, `create_proposal`, `sync_worker_service_types` com check `auth.uid()`.
- `job_reports` restrito a participantes do job.
- RPCs de avaliação verificam participação.
- Alteração de role impedida por trigger.

---

## Gaps conhecidos (sem spin)

### CRÍTICO — bloqueia utilizadores reais agora

**Migration 0032 não aplicada à BD viva**
O live DB ainda tem os FKs antigos (`job_proposals_worker_id_fkey` e
`help_acceptances_worker_id_fkey` apontam para `worker_profiles(profile_id)` em vez de
`profiles(id)`). O código Dart usa o hint `profiles!job_proposals_worker_id_fkey` —
PostgREST não resolve o join porque o FK não aponta para `profiles`. Resultado: nome e
avatar do worker aparecem como `null`/"—" em todos os cards de proposta visíveis pelo cliente.

**Fix:** aplicar `archive/0032_audit_fixes.sql` via Supabase SQL Editor.

---

### ALTO — antes de mostrar a alguém fora da equipa

**Sem push notifications (FCM)**
Notificações in-app funcionam enquanto a app está aberta (Supabase Realtime). Quando a
app está em background ou fechada, o worker não recebe novos jobs, o cliente não recebe
propostas. Workers ativos perdem trabalho. Bloqueador funcional real.

**SA3 — Storage INSERT sem verificação de path**
Qualquer utilizador autenticado pode fazer upload para qualquer path em `avatars` e
`job-photos`. Policy de UPDATE já verifica o path; INSERT não. Risco: overwrite de avatar
de outro utilizador. Mitigação parcial: o app só faz upload para o próprio path; sem interface
de exploração de paths. Aceite no MVP.

**SA2 — ratings INSERT sem verificação de participação**
Policy `"Utilizador cria a sua avaliação"` verifica apenas `rater_id = auth.uid()`. Via
REST direto (bypass das RPCs), qualquer utilizador autenticado pode inserir uma avaliação
para qualquer `(job_id, ratee_id)`. As RPCs verificam participação e são o único caminho
no código Dart. Aceite no MVP.

**Contacto do worker principal não visível aos ajudantes**
Ajudantes veem o nome do worker principal (via `HelpAcceptanceSummary`) mas não o seu
contacto (telefone/WhatsApp). A regra de negócio está correta; a exibição do contacto é
um item por implementar.

---

### MÉDIO — gaps de UX/segurança antes do lançamento mais amplo

- Labels de `JobStatus` inconsistentes entre ecrãs (P1/A1 — 4 implementações independentes).
- Sem CHECK constraints em `job_proposals.people_needed` e `help_requests.slots_needed`.
- Jobs cancelados antes de qualquer proposta aceite não aparecem no histórico do cliente
  (`acceptedProposalId = null`) — pode ser intencional, não está documentado.
- SA1: `auto_confirm_completed_jobs` e `auto_expire_jobs` sem verificação de `auth.uid()`.
- Validação de número de telefone fraca (aceita qualquer string, incluso "1").
- `worker_setup_screen.dart` chama Supabase diretamente no widget (único violation arquitetural).

---

### BAIXO — limpeza conhecida

- Cores hex hardcoded divergentes do seed do tema (P2/P3).
- Wildcard silencioso em `_HistoryCard._statusLabel` (P4).
- Diagrama de pastas em `architecture.md` desatualizado (P7).
- Falta CHECK `hourly_rate >= 0` em `job_proposals` (B4).
- `estimated_hours` legacy nullable em `job_proposals` por remover (B3).

---

## Postura de segurança

### O que está protegido

| Área | Mecanismo |
|---|---|
| Acesso a dados | RLS em todas as tabelas; sem acesso público a nenhuma |
| Mutações críticas | SECURITY DEFINER RPCs com check `auth.uid()` |
| Coordenadas do worker | `worker_profiles_public` view exclui `base_lat`/`base_lng` |
| Denúncias de job | Restrito a cliente e worker com proposta aceite |
| Avaliações | RPCs verificam participação no job |
| Alteração de role | Trigger BEFORE UPDATE bloqueia qualquer tentativa |
| Perfil de worker | SELECT restrito ao próprio; view pública sem coordenadas |

### Riscos aceites (revisitar antes do lançamento público)

| Código | Risco | Impacto real | Fix futuro |
|---|---|---|---|
| SA1 | auto_confirm/auto_expire sem check auth | Funções idempotentes; abuso = acelerar o que cron faria | `IF auth.uid() IS NULL THEN RAISE EXCEPTION` |
| SA2 | ratings INSERT sem participação via REST | RPCs verificam; bypass requer chamada REST direta | Policy INSERT com verificação de participação |
| SA3 | Storage INSERT sem verificação de path | Upload para path alheio possível; sem UI que exponha paths | Restringir INSERT a `own uid` no filename |

---

## O que é preciso antes do primeiro utilizador real fora da equipa

### Obrigatório (bloqueador)

1. **Aplicar migration 0032** — corrige os FKs quebrados no live DB. Esforço: S. `archive/0032_audit_fixes.sql` via SQL Editor.
2. **FCM push notifications** — workers perdem jobs sem isto. Esforço: L (Firebase project + Edge Function). Prioridade máxima após 0032.

### Recomendado (antes de ir a público)

3. **Verificação de identidade** — serviços prestados em casa de pessoas. Upload de documento, verificação manual mínima. Sem isto, confiança zero para utilizadores externos à equipa.
4. **Nome/marca** — "LocalServices" é placeholder. Mudar antes de qualquer exposição pública — depois é caro.
5. **Testar em dispositivo Android real com utilizadores externos** — Run 1 e Run 2 foram executados pela equipa; cenários de utilizador novo (onboarding, first job, first proposal) precisam de validação externa.

### Nice-to-have antes do lançamento

6. Correção SA3 (Storage INSERT path restriction) — S.
7. Validação de número de telefone (9 dígitos mínimo) — S.
8. CHECK constraints em `people_needed`/`slots_needed` — S (migration manual).
