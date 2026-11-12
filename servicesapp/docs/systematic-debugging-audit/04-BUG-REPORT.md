# 04. Relatório de bugs

Estado auditado: ramo do PR #47 (commit `7c9f539`, migrations até à 0073). 14 registos: 1 alto (risco de processo), 3 médios, 10 baixos. Nenhum crítico encontrado.

Regras usadas:

- **Confirmado** = reproduzido com um comando que qualquer pessoa pode repetir (BD local ou leitura direta do código, com ficheiro e linha).
- **Suspeito** = hipótese com evidência parcial, ainda por confirmar no ambiente real.
- Na auditoria nenhum bug foi corrigido. Depois, a pedido do Henrique (12/11), foram corrigidos 13 dos 14: os de BD na migration `0074_audit_fixes.sql` (criada, **não aplicada**) e os de app no código. Só o BUG-014 fica, porque se resolve aplicando as migrations 0067 a 0074 por ordem. A regressão está em `supabase/tests/audit/` (162/162 no 10_flows, 19/19 no 30_findings, RACE-01 a RACE-04 a passar). Os problemas já resolvidos nas revisões de 02/11 a 12/11 (partes 1 a 5) não estão repetidos aqui; os cenários deles continuam a passar no ramo do #47.

Severidade: Critical (perda de dados ou falha de segurança explorável em larga escala), High (bloqueia um fluxo principal ou expõe dados pessoais), Medium (estado errado ou incoerente num fluxo principal, com saída difícil), Low (incómodo, higiene ou abuso pouco provável).

| Bug | Título | Severidade | Prioridade | Estado |
|---|---|---|---|---|
| BUG-014 | App e BD fora de passo: 0067 a 0073 por aplicar | High (risco de processo) | P0 | Suspeito |
| BUG-001 | Retirar proposta ao mesmo tempo que é aceite deixa o trabalho incoerente | Medium | P1 | Corrigido (0074) |
| BUG-002 | Pedido criado pela API pode nascer "já iniciado" | Medium | P2 | Corrigido (0074) |
| BUG-004 | Descoberta de pedidos usa coordenadas vindas da app e não verifica o papel | Medium (privacidade) | P2 | Corrigido (0074) |
| BUG-006 | Raio do jardineiro sem limite na BD (avisos de todo o país) | Low | P2 | Corrigido (0074) |
| BUG-003 | Servidor aceita pedido com data fixa no passado | Low | P3 | Corrigido (0074) |
| BUG-005 | Limite de 2 fotos falha com envios em paralelo | Low | P3 | Corrigido (0074) |
| BUG-007 | Proposta aceita horas mínimas maiores do que as máximas | Low | P3 | Corrigido (0074) |
| BUG-008 | Textos sem limite de tamanho escritos pela API | Low | P3 | Corrigido (0074) |
| BUG-009 | Avaliações legíveis por anónimos, com ids | Low (decisão) | P3 | Corrigido (0074) |
| BUG-012 | Segunda avaliação é ignorada em silêncio | Low | P3 | Corrigido (0074) |
| BUG-013 | "Este pedido já não está aberto" não refresca a lista de propostas | Low | P3 | Corrigido (app) |
| BUG-010 | Links legais usam SnackBar em vez de AppToast | Low | P3 | Corrigido (app) |
| BUG-011 | Cor solta fora do design system no onboarding | Low | P3 | Corrigido (app) |

---

## BUG-014

- **Título:** A app no `main` e no PR #47 depende de migrations que a BD viva ainda não tem (0067 a 0073)
- **Fluxo afetado:** FLOW-056, FLOW-100 e, indiretamente, todos os que usam RPCs mudadas na 0068 a 0073 (FLOW-025, 031, 033, 046, 047, 048, 059, 090, 091, 093)
- **Severidade:** High (risco de processo, não de código) · **Prioridade:** P0
- **Ficheiros e linhas:** `supabase/migrations/0067_plan_badges_and_earnings.sql` a `0073_flow_review_part5.sql`; `lib/features/worker/data/worker_repository.dart:146` (`isMissingRpcError`); memória do projeto: "aplicadas até à 0066".
- **Descrição:** o código Flutter já assume as regras da 0067 a 0073 (painel de ganhos, selo do plano, trabalho por dias sem "Começar o dia", confirmação automática aos 7 dias com relato, lembretes de início). Se uma build nova for publicada antes de aplicar as migrations, os ecrãs mostram regras que o servidor ainda não cumpre.
- **Pré-condições:** publicar a app (lojas ou `deploy-web`) com a BD só até à 0066.
- **Passos para reproduzir:** não reproduzido na BD viva (não tenho acesso, e não devo ter). Na BD local: montar até à 0066 e chamar `get_my_earnings` dá `PGRST202`/função inexistente.
- **Resultado esperado:** a BD está sempre igual ou à frente da app publicada.
- **Resultado observado:** 7 migrations criadas e não aplicadas (fonte: memória do projeto e cabeçalhos dos ficheiros).
- **Evidência:** `ls supabase/migrations` mostra 0067 a 0073; os cabeçalhos dizem "NÃO APLICADA".
- **Causa raiz:** processo manual de aplicação (regra do projeto: o Claude nunca aplica). Hipótese, não confirmada: algumas builds de teste já correm contra a BD viva.
- **Impacto no utilizador:** painel de ganhos indisponível; trabalhos por dias com textos que não batem com o servidor; avisos que não chegam.
- **Impacto noutros fluxos:** a 0068 corrige `get_pending_proposals_for_job` com DROP + CREATE: sem ela, a lista de propostas pode falhar se a 0067 estiver aplicada sozinha (já documentado no PR #45).
- **Solução recomendada:** aplicar 0067 a 0073 por ordem no SQL Editor **antes** de publicar a próxima build; depois correr TM-054 para confirmar os 11 jobs do cron.
- **Teste de regressão necessário:** `bash supabase/tests/audit/run.sh` (as migrations aplicam numa BD vazia) e os testes manuais P0.
- **Estado:** Suspeito (depende do que está publicado hoje).

## BUG-001

- **Título:** Se o jardineiro retira a proposta no mesmo instante em que a cliente a aceita, o trabalho fica confirmado com uma proposta "retirada"
- **Fluxo afetado:** FLOW-043 (retirar), FLOW-025 (aceitar), FLOW-045 (os meus trabalhos), FLOW-101
- **Severidade:** Medium · **Prioridade:** P1
- **Ficheiros e linhas:** `supabase/migrations/0001_consolidated_baseline.sql:1007` (`withdraw_proposal`, nunca reescrita depois); comparar com `accept_proposal` (usa `FOR UPDATE`).
- **Descrição:** `withdraw_proposal` verifica `status = 'pending'` com um `IF NOT EXISTS (...)` e depois faz `UPDATE job_proposals SET status = 'superseded' WHERE id = p_proposal_id`, sem repetir a condição de estado nem bloquear a linha. Se a aceitação estiver a meio, o `UPDATE` espera pelo bloqueio, a aceitação grava `accepted`, e a seguir o `UPDATE` reescreve para `superseded`.
- **Pré-condições:** proposta pendente; duas pessoas a carregar no botão com milissegundos de diferença.
- **Passos para reproduzir:** `bash supabase/tests/audit/run.sh keep && bash supabase/tests/audit/20_concurrency.sh` (RACE-02). Reproduzido 3 vezes seguidas.
- **Resultado esperado:** uma das duas ações falha com mensagem clara; o estado fica `confirmed/accepted` ou `open/superseded`.
- **Resultado observado:** `job_requests.status = confirmed`, `accepted_proposal_id` aponta para uma proposta `superseded`; o jardineiro recebe "proposta aceite" e a cliente "proposta retirada"; `proposal_count` desce; no quadro do jardineiro o trabalho aparece no Histórico (`get_worker_job_board('completed')`) e não na Agenda.
- **Evidência:** `evidence/bd-20_concurrency.txt` (FAIL RACE-02); notificações do pedido: `proposal_accepted` ao jardineiro e `proposal_withdrawn` à cliente.
- **Causa raiz:** confirmada. Verificação e escrita separadas (TOCTOU) sem `FOR UPDATE` nem `AND status = 'pending'` no `UPDATE`.
- **Impacto no utilizador:** a cliente julga que tem jardineiro e ele julga que desistiu; ninguém aparece no dia.
- **Impacto noutros fluxos:** Agenda, lembretes de início (contam como trabalho confirmado), ganhos.
- **Solução recomendada:** na migration seguinte, `SELECT ... FOR UPDATE` da proposta e do pedido no início de `withdraw_proposal` e `UPDATE ... WHERE id = p_proposal_id AND status = 'pending'` com verificação de `FOUND`. Sem mudança de assinatura.
- **Teste de regressão necessário:** RACE-02 tem de passar; T-PROP-23 e os cenários da parte 5 (pedido direto: retirar conta como recusa).
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-002

- **Título:** O INSERT direto em `job_requests` aceita campos de execução (`started_at`, `marked_done_at`, fotos, lembretes)
- **Fluxo afetado:** FLOW-020, FLOW-031, FLOW-046, FLOW-048
- **Severidade:** Medium (manipulação de estado pela própria cliente) · **Prioridade:** P2
- **Ficheiros e linhas:** `supabase/migrations/0042_security_hardening.sql:96` (policy "Client cria jobs": verifica 17 colunas, não estas); `0062_job_followups_and_better_notifications.sql` (`job_request_track_visibility` limpa só 4 colunas no INSERT).
- **Descrição:** a policy de INSERT bloqueia estado, proposta aceite, cancelamentos e remarcações, mas não `started_at`, `marked_done_at`, `before_photo_paths`, `after_photo_paths`, `completion_photo_path`, `day_reminder_sent_on`, `overdue_notified_at`, `confirmation_reminder_sent_at`, `start_reminder_for`, `late_start_reminder_for`, `undated_expiry_warned_at`.
- **Pré-condições:** sessão de cliente e acesso à API (a chave pública vem dentro da app).
- **Passos para reproduzir:** `30_findings.sql`, cenário F-002 (criar com `started_at = now()`, propor, aceitar).
- **Resultado esperado:** o servidor ignora ou recusa esses campos no INSERT.
- **Resultado observado:** o trabalho aceite já está "em curso"; o jardineiro não consegue cancelar ("O trabalho já começou") nem Iniciar ("já foi iniciado").
- **Evidência:** `evidence/bd-30_findings.txt` (F-002a a F-002f) e T-JOB-06 em `bd-10_flows.txt`.
- **Causa raiz:** confirmada. Lista de colunas da policy feita antes das colunas novas da 0046, 0052, 0072 e 0073.
- **Impacto no utilizador:** jardineiro preso num trabalho que não pode cancelar; textos de "em curso" errados. A app oficial nunca envia estes campos, por isso só acontece com chamadas manuais à API.
- **Impacto noutros fluxos:** confirmação automática, lembretes, ganhos.
- **Solução recomendada:** no `job_request_track_visibility` (ramo INSERT), pôr a NULL todos os campos de execução e de lembretes. Mais robusto do que alargar a policy.
- **Teste de regressão necessário:** T-JOB-06 e F-002 passam a dar `started_at` NULL; T-JOB-01 e o fluxo completo continuam a passar.
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-004

- **Título:** `get_jobs_in_radius` usa coordenadas vindas da app e qualquer conta (também de cliente) lista pedidos abertos de outras pessoas
- **Fluxo afetado:** FLOW-040, FLOW-041
- **Severidade:** Medium (privacidade) · **Prioridade:** P2
- **Ficheiros e linhas:** `supabase/migrations/0070_privacy_and_deleted_account_fixes.sql:23` (só verifica `auth.uid() IS NOT NULL`; raio limitado a 50, centro livre).
- **Descrição:** o centro da pesquisa é o `worker_lat/worker_lng` enviado pela app, não a base gravada no perfil, e a função não exige `role = 'worker'`. Com várias chamadas consegue-se listar todos os pedidos abertos do país: zona, coordenadas arredondadas a 2 casas (cerca de 1 km), descrição, serviço, datas e o `client_id`.
- **Passos para reproduzir:** T-DISC-07 (jardineiro do Porto com coordenadas de Lisboa) e T-DISC-08 (conta de cliente).
- **Resultado esperado:** só jardineiros, e só à volta da base gravada (mais o `search_extra_km`).
- **Resultado observado:** ambos devolvem o pedido de Lisboa.
- **Evidência:** `evidence/bd-10_flows.txt` (FAIL T-DISC-07 e T-DISC-08).
- **Causa raiz:** confirmada. Desenho original da RPC (antes da 0043 o raio já era da app); a morada exata está protegida, a zona não.
- **Impacto no utilizador:** recolha em massa de pedidos (concorrência a copiar clientes, ou perfil de quem pede o quê e onde, mais o `client_id`). A morada exata continua escondida.
- **Impacto noutros fluxos:** a app usa GPS atual ou a base; mudar a regra pode esconder pedidos a um jardineiro que trabalha longe da base. Decidir antes de corrigir.
- **Solução recomendada:** exigir `role = 'worker'`; usar a base de `worker_profiles` (ignorando as coordenadas recebidas, ou aceitando-as só a menos de X km da base); não devolver `client_id` mascarado a quem não tem proposta.
- **Teste de regressão necessário:** T-DISC-01..08, FLOW-040 na app (TM-033).
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-006

- **Título:** `worker_profiles.radius_km` sem limite na BD; um raio de 5000 km recebe avisos (e push) de todos os pedidos
- **Fluxo afetado:** FLOW-007, FLOW-013, FLOW-099
- **Severidade:** Low · **Prioridade:** P2
- **Ficheiros e linhas:** `worker_profiles` sem `CHECK` em `radius_km`; `0062_job_followups_and_better_notifications.sql:183` (`job_candidate_workers` compara com o raio gravado, sem `LEAST(..., 50)`, ao contrário das RPCs de pesquisa).
- **Passos para reproduzir:** `30_findings.sql`, F-006 (UPDATE direto a 5000 km; pedido em Faro avisa o jardineiro de Lisboa).
- **Resultado esperado:** raio entre 1 e 50 km, como o slider.
- **Resultado observado:** aceite; aviso `new_job_in_radius` de Faro entregue.
- **Evidência:** `evidence/bd-30_findings.txt` (F-006a a F-006c).
- **Causa raiz:** confirmada. A regra 1 a 50 só existe na UI e nas RPCs de leitura.
- **Impacto:** um jardineiro recebe pushes de todo o país (custo de envio FCM e "vantagem" sobre os outros). Não expõe moradas.
- **Solução recomendada:** `CHECK (radius_km BETWEEN 1 AND 50)` (validar antes os dados atuais) e `LEAST(radius_km, 50)` em `job_candidate_workers`.
- **Teste de regressão necessário:** F-006 recusado; setup do jardineiro (TM-008).
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-003

- **Título:** O servidor aceita um pedido com data fixa no passado
- **Fluxo afetado:** FLOW-020, FLOW-090
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** policy "Client cria jobs" (`0042_security_hardening.sql:96`): não verifica `preferred_date`.
- **Passos para reproduzir:** T-JOB-08 e F-003.
- **Resultado esperado:** recusa (como `update_job_request` já faz, T-EDIT-03).
- **Resultado observado:** criado; nenhum jardineiro o vê; o cron seguinte fecha-o como `no_response` e avisa a cliente.
- **Evidência:** `evidence/bd-30_findings.txt` (F-003a a F-003c).
- **Causa raiz:** confirmada. A app impede no seletor de data; o servidor não repete a regra. Caso real possível: rascunho de ontem publicado hoje, se o ecrã de rever não revalidar (não verificado na UI, ver TM-017).
- **Solução recomendada:** acrescentar `(date_mode <> 'fixed' OR preferred_date >= today_pt())` à policy ou ao trigger de INSERT.
- **Teste de regressão necessário:** T-JOB-08, TM-017.
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-005

- **Título:** O máximo de 2 fotos por pedido não resiste a dois envios ao mesmo tempo
- **Fluxo afetado:** FLOW-020, FLOW-101
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `0069_multi_day_and_started_job_rules.sql:614` (`job_photos_before_insert` faz `count(*)` sem bloquear o pedido).
- **Passos para reproduzir:** `20_concurrency.sh`, RACE-03.
- **Resultado observado:** 3 fotos no pedido.
- **Causa raiz:** confirmada. Contagem sem `SELECT ... FOR UPDATE` no `job_requests`.
- **Impacto:** quase nenhum (a app envia em sequência); a vista pode mostrar 3 fotos.
- **Solução recomendada:** `PERFORM 1 FROM job_requests WHERE id = NEW.job_id FOR UPDATE;` antes da contagem.
- **Teste de regressão necessário:** RACE-03, T-JOB-09..12.
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-007

- **Título:** `create_proposal` aceita horas mínimas maiores do que as máximas
- **Fluxo afetado:** FLOW-042
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `0058_proposal_pricing_and_work_days.sql:91`.
- **Passos para reproduzir:** T-PROP-07 e F-007b (6h a 2h gravado).
- **Resultado observado:** gravado; estimativas de custo de equipa e ganhos usam números trocados.
- **Causa raiz:** confirmada. Validação só na UI (opções fixas 1-2h, 2-4h, ...). A mesma função já valida dias e pessoas (F-007c recusa 0 pessoas).
- **Solução recomendada:** `IF p_estimated_hours_min > p_estimated_hours_max THEN RAISE ...` (o mesmo para dias, a confirmar).
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-008

- **Título:** Textos sem limite de tamanho escritos diretamente pela API
- **Fluxo afetado:** FLOW-012, FLOW-013, FLOW-029
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** colunas `profiles.full_name`, `profiles.phone`, `worker_profiles.bio`, `job_reports.description` sem `CHECK`.
- **Passos para reproduzir:** F-008 (nome com 100 000 caracteres aceite); verificação manual igual para `bio` (100 000) e `job_reports.description` (200 000), feita em transação com `ROLLBACK`.
- **Causa raiz:** confirmada. Limites só nos `TextField`. Já tinha sido levantado em parte na revisão parte 3 (ponto 5); continua por fazer para estas colunas.
- **Impacto:** abuso de armazenamento, ecrãs partidos para a outra parte (nome gigante nas propostas e avaliações).
- **Solução recomendada:** `CHECK (char_length(...) <= N)` com N igual ao da UI.
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-009

- **Título:** Avaliações legíveis por anónimos, com `job_id`, `rater_id` e `ratee_id`
- **Fluxo afetado:** FLOW-074
- **Severidade:** Low (decisão de privacidade) · **Prioridade:** P3
- **Ficheiros e linhas:** `0001_consolidated_baseline.sql:659` (policy `USING (true)` para o papel `public`).
- **Passos para reproduzir:** T-RATE-11 (anónimo lê as 4 avaliações).
- **Causa raiz:** confirmada; deliberada no início (cartão público). Desde a 0033/0059 o cartão usa a view `worker_public_card`, por isso a leitura direta anónima pode já não ser precisa (hipótese a confirmar no código: a app lê `ratings` com sessão).
- **Solução recomendada:** decidir se a leitura direta fica só para `authenticated` e sem `rater_id` de clientes.
- **Estado:** Confirmado (comportamento); correção depende de decisão. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-012

- **Título:** Avaliar duas vezes devolve sucesso e ignora a segunda
- **Fluxo afetado:** FLOW-030
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `0049_pending_decisions.sql:1276` (`ON CONFLICT ... DO NOTHING`).
- **Passos para reproduzir:** T-RATE-04a/04b (a segunda chamada passa e as estrelas continuam 5).
- **Causa raiz:** confirmada; protege duplicados, mas sem aviso. Se a UI deixar reabrir o ecrã (não verificado, TM-025), a pessoa julga que alterou a nota.
- **Solução recomendada:** devolver erro "Já avaliaste este trabalho" ou permitir editar de forma explícita.
- **Estado:** Confirmado. **Corrigido** a 12/11 (migration 0074, não aplicada); ver o PR #48.

## BUG-013

- **Título:** Aceitar uma proposta num pedido que entretanto fechou mostra o erro mas não refresca a lista
- **Fluxo afetado:** FLOW-025
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `lib/features/jobs/presentation/client_proposal_detail_screen.dart:49-70` (procura "expirou", "já não está disponível", "já processada", "não encontrada"); a 0073 passou a lançar "Este pedido já não está aberto." (T-PROP-22).
- **Causa raiz:** confirmada por leitura: o texto novo cai no ramo `failed`, que não invalida `pendingProposalsForJobProvider`.
- **Impacto:** a cliente vê a mensagem certa mas a lista antiga fica até puxar para atualizar.
- **Solução recomendada:** incluir "não está aberto" no ramo `unavailable` (ou passar a usar um `HINT`/código em vez de texto).
- **Estado:** Confirmado (código); não reproduzido na UI. **Corrigido** a 12/11 (código da app); ver o PR #48.

## BUG-010

- **Título:** Abrir Termos e Política usa `SnackBar` em vez de `AppToast`
- **Fluxo afetado:** FLOW-076
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `lib/core/widgets/app_legal_links.dart:17-33`.
- **Causa raiz:** confirmada; quebra a regra do CLAUDE.md ("AppToast, nunca SnackBar"). Só aparece quando o browser não abre.
- **Solução recomendada:** `AppToast.maybeOf(context)?.error(...)`.
- **Estado:** Confirmado. **Corrigido** a 12/11 (código da app); ver o PR #48.

## BUG-011

- **Título:** `Color(0xFFD7E5D0)` fora do design system
- **Fluxo afetado:** FLOW-001
- **Severidade:** Low · **Prioridade:** P3
- **Ficheiros e linhas:** `lib/features/onboarding/presentation/widgets/onboarding_page_indicator.dart:12`.
- **Causa raiz:** confirmada; única cor solta fora de `core/theme/` (`grep -rn 'Color(0x' lib | grep -v core/theme`).
- **Solução recomendada:** token em `AppColors` (por exemplo `onboardingDotInactive`) ou `AppColors.primaryContainer` se o tom servir.
- **Estado:** Confirmado. **Corrigido** a 12/11 (código da app); ver o PR #48.

---

## Hipóteses investigadas e descartadas

| Hipótese | Teste | Resultado |
|---|---|---|
| Duas aceitações em paralelo confirmam duas propostas | RACE-01 | Não: a segunda recebe "Este pedido já não está aberto." |
| Duplo envio de proposta cria duas | RACE-04 | Não: "Já tens uma proposta para este pedido." |
| Utilizador consegue mudar o dono de uma notificação | T-NOTIF-03 | Não: permissão de coluna recusa |
| Cliente consegue criar notificações ou avaliações à mão | T-NOTIF-01, T-RATE-05 | Não: RLS recusa |
| Ajudante ou jardineiro recusado lê o telefone da cliente | T-HELP-09, T-PROP-27 | Não |
| Crons podem ser chamados por um utilizador | T-CRON-01..04 | Não: `permission denied` |
| Algum cron rebenta com os dados dos fluxos | T-CRON-05 | Não: os 11 correm sem erro |
| Painel admin abre sem segundo fator | T-ADM-04 | Não: "Sem acesso." |
| Tipos de notificação do SQL sem tratamento na app | script de contrato (ver 07) | Não: os tipos batem |
| RPCs chamadas pela app com nomes ou parâmetros errados | `rpccheck.py` + revisão manual dos 3 avisos | Não: os avisos eram falsos positivos (parâmetros sem `p_`) |
| Segredos no repositório | `git grep` por JWT, chaves Google e `service_role` | Não encontrados; `google-services.json` está no `.gitignore` |
