# Portal de administraÃ§Ã£o e suporte: especificaÃ§Ã£o

VersÃ£o de 13/11/2026. Documento autocontido para desenhar e construir o painel admin da ProJardim noutra conversa. LÃª tambÃ©m `docs/ARCHITECTURE.md` (stack, RLS, RPCs) e `CLAUDE.md` (regras fixas) antes de mexer em cÃ³digo.

## 1. Objetivo

Dar ao Henrique (e mais tarde a 1 ou 2 pessoas de suporte) uma ferramenta **sÃ³ web** para:

1. Responder a quem escreve para `suporte@projardim.pt` em minutos, com tudo o que precisa num sÃ³ ecrÃ£: quem Ã© a pessoa, os pedidos, as propostas, as fotos, as mensagens que a app lhe enviou e o que correu mal.
2. Seguir cada pedido do princÃ­pio ao fim ("rastreio"): quando foi criado, a quem foi mostrado, que propostas teve, quem aceitou, quando comeÃ§ou e acabou, que avisos saÃ­ram, se houve problemas.
3. Moderar: tratar relatos de problema e denÃºncias, esconder conteÃºdo, suspender contas, com explicaÃ§Ã£o ao utilizador e registo (Regulamento dos ServiÃ§os Digitais).
4. Gerir os planos dos jardineiros (jÃ¡ existe) e ver os nÃºmeros do negÃ³cio.
5. Cumprir a lei sem esforÃ§o: pedidos de acesso, exportaÃ§Ã£o e apagamento de dados (RGPD), registo de quem viu o quÃª.

Fora de Ã¢mbito: chat com utilizadores (o contacto Ã© por email), pagamentos dentro da app, app nativa do painel.

## 2. O que jÃ¡ existe

- Rotas `/admin` e `/admin/workers/:workerId`, fora dos papÃ©is e dos ShellRoutes (`core/router/route_guard.dart`, `app_router.dart`).
- `admin_gate_screen.dart`: login com email e senha, segundo fator TOTP obrigatÃ³rio (inscriÃ§Ã£o e verificaÃ§Ã£o), "Sem acesso" para contas que nÃ£o sÃ£o admin.
- Tabelas `admin_users` (quem Ã© admin) e `admin_actions` (registo de cada mudanÃ§a), migration `0060`.
- RPCs `admin_whoami`, `admin_overview(p_days)`, `admin_list_workers`, `admin_get_worker`, `admin_set_worker_plan`. Todas `SECURITY DEFINER`, com `assert_verified_admin()` (admin + sessÃ£o com MFA `aal2`).
- EcrÃ£ com separadores "VisÃ£o geral" (nÃºmeros) e "Jardineiros" (lista, detalhe, folha para mudar o plano).

Falta quase tudo o que Ã© suporte: clientes, pedidos, fotos, avaliaÃ§Ãµes, relatos, notificaÃ§Ãµes, moderaÃ§Ã£o, RGPD.

## 3. PrincÃ­pios (nÃ£o negociÃ¡veis)

1. **SÃ³ RPCs `admin_*`.** O painel nunca lÃª tabelas diretamente. Cada RPC comeÃ§a por `PERFORM assert_verified_admin();` (ou pela verificaÃ§Ã£o de papel, ver 4) e Ã© `SECURITY DEFINER` com `SET search_path = public`. Nunca recebe o id do admin da app: usa `auth.uid()`.
2. **Tudo o que muda fica em `admin_actions`**, com quem, quando, o quÃª, o alvo, o valor antes e depois e o motivo obrigatÃ³rio.
3. **Ler dados pessoais tambÃ©m fica registado** (`admin_access_log`, ver 6.1): abrir a ficha de uma pessoa, ver o telefone, abrir fotos, exportar dados. Pedido de motivo curto ao abrir uma ficha de utilizador ("Email de suporte 12/11", "Relato #123").
4. **MÃ­nimo necessÃ¡rio.** Listas mostram nomes e estados; telefone, email, morada exata e fotos sÃ³ na ficha, com toque para revelar (fica registado).
5. **Nunca apagar Ã s escondidas.** ModeraÃ§Ã£o esconde (`hidden_at`, `hidden_reason`) em vez de apagar, exceto quando a lei obriga a apagar (pedido RGPD, conteÃºdo ilegal).
6. **Explicar ao utilizador.** Cada decisÃ£o de moderaÃ§Ã£o gera uma "declaraÃ§Ã£o de motivos" guardada e enviada por notificaÃ§Ã£o na app e por email.
7. **Web sÃ³.** Layout de secretÃ¡ria (largura â‰¥ 1024): navegaÃ§Ã£o lateral fixa, listas em tabela, painel de detalhe Ã  direita. Em ecrÃ£s pequenos mostra "Usa um computador". MantÃ©m os tokens do design system (`AppColors`, `AppSpacing`, `AppRadius`, `textTheme`) e o motion obrigatÃ³rio.
8. **Sem dados de teste em produÃ§Ã£o.** Filtro global "esconder contas de teste" (emails com `+teste`) nos nÃºmeros.

## 4. PapÃ©is no painel

Hoje `admin_users` nÃ£o tem papÃ©is. Acrescentar `admin_users.role` com:

| Papel | Pode |
|---|---|
| `owner` | tudo, incluindo gerir admins, exportar e apagar dados (RGPD) e ver o registo de acessos |
| `support` | ver utilizadores, pedidos, fotos, notificaÃ§Ãµes; notas internas; reenviar avisos; abrir casos |
| `moderator` | o que `support` pode, mais esconder conteÃºdo, avisar e suspender contas |

FunÃ§Ã£o `assert_admin_role(VARIADIC p_roles text[])` usada pelas RPCs que mudam coisas.

## 5. Mapa do painel

NavegaÃ§Ã£o lateral:

1. **InÃ­cio**: nÃºmeros do dia e o que precisa de atenÃ§Ã£o.
2. **Pesquisa global** (sempre visÃ­vel no topo): email, nome, telemÃ³vel, id de pedido, id de utilizador.
3. **Casos de suporte**
4. **Pedidos**
5. **Pessoas** (clientes e jardineiros juntos, com filtro de papel)
6. **Relatos e denÃºncias**
7. **AvaliaÃ§Ãµes**
8. **Planos** (o que jÃ¡ existe em "Jardineiros", com histÃ³rico)
9. **Avisos enviados** (notificaÃ§Ãµes e push)
10. **Privacidade (RGPD)**
11. **Registo** (aÃ§Ãµes e acessos)
12. **DefiniÃ§Ãµes** (admins, textos de resposta, limites)

### 5.1 InÃ­cio

- CartÃµes: pedidos novos hoje, pedidos abertos sem propostas hÃ¡ mais de 24 h, trabalhos para hoje, trabalhos Ã  espera de confirmaÃ§Ã£o hÃ¡ mais de 36 h, relatos por tratar, casos abertos com prazo a vencer, contas novas, pushes falhados nas Ãºltimas 24 h.
- Lista "Precisa de ti": casos e relatos ordenados pelo prazo (1 dia Ãºtil, 15 dias Ãºteis).
- GrÃ¡fico simples de 30 dias: pedidos criados, aceites e concluÃ­dos.

### 5.2 Pesquisa global

Um campo que aceita qualquer coisa. Resultados agrupados: Pessoas, Pedidos, Casos. Enter abre o primeiro. RPC `admin_search(p_query text, p_limit int)`.

### 5.3 Casos de suporte

Para nÃ£o perder emails: um caso por assunto, criado Ã  mÃ£o a partir de um email (copiar e colar) ou automaticamente a partir de um relato na app.

- Lista: estado (aberto, Ã  espera do utilizador, resolvido), tipo (dÃºvida, reclamaÃ§Ã£o, privacidade, denÃºncia, autoridade), pessoa, pedido ligado, prazo, quem trata.
- Detalhe: linha do tempo do caso (mensagens copiadas, notas internas, aÃ§Ãµes tomadas), ligaÃ§Ãµes para a pessoa e o pedido, botÃµes "Copiar resposta modelo" (textos de `docs/SUPORTE.md`), "Marcar resolvido".
- Prazo calculado em dias Ãºteis a partir da data de receÃ§Ã£o: 1 dia Ãºtil para a primeira resposta, 15 dias Ãºteis para reclamaÃ§Ãµes, 1 mÃªs para privacidade.

### 5.4 Pedidos (rastreio)

Lista com filtros: estado, serviÃ§o, zona/distrito, data, urgente, com relato, pedido direto, sem propostas, cliente, jardineiro.

Detalhe de um pedido, em 3 colunas:

1. **Resumo**: serviÃ§o, estado atual com a fase do `JobFlowStepper`, cliente, jardineiro aceite, ajudantes, morada (revelar), data combinada, preÃ§o e duraÃ§Ã£o da proposta aceite, tempo registado, valor estimado.
2. **Linha do tempo** (o coraÃ§Ã£o do rastreio), por ordem, cada linha com data e hora de Lisboa:
   - pedido criado (e pedido direto a quem, prazo do pedido direto);
   - avisos "Novo pedido perto de ti": a quantos jardineiros, quantos pushes entregues ou falhados;
   - cada proposta (jardineiro, preÃ§o, data), retiradas e expiradas;
   - aceitaÃ§Ã£o (qual proposta, quando);
   - pedido de ajudantes, candidaturas, aceites, recusas, vagas alteradas;
   - remarcaÃ§Ãµes propostas, aceites, recusadas;
   - lembretes enviados (1 h antes, 30 min sem iniciar);
   - iniciado (com fotos de antes), dias de trabalho, concluÃ­do (fotos de depois), confirmado pelo cliente ou automaticamente Ã s 48 h;
   - cancelamento (quem, motivo, se reabriu);
   - avaliaÃ§Ãµes dadas;
   - relatos de problema;
   - aÃ§Ãµes de admin sobre o pedido.
3. **Fotos e anexos**: galeria das fotos do pedido, de antes e de depois, com ampliaÃ§Ã£o. Abrir fica registado.

AÃ§Ãµes: nota interna, reenviar um aviso a uma das partes, esconder uma foto (com motivo), cancelar o pedido em nome do suporte (motivo obrigatÃ³rio, avisa as partes), abrir caso ligado.

**Dados para a linha do tempo.** Parte jÃ¡ existe em colunas (`created_at`/`updated_at`, `job_proposals.accepted_at`, `started_at`, `marked_done_at`, `cancel_reason`, `job_work_days`, `notifications`), mas nÃ£o hÃ¡ data prÃ³pria de cancelamento nem histÃ³rico de mudanÃ§as de estado. Para ser fiÃ¡vel e completo, criar uma tabela `job_events` (ver 6.2) escrita por triggers nas tabelas do fluxo, em vez de reconstruir Ã  mÃ£o. Os registos antigos ficam sÃ³ com o que dÃ¡ para deduzir das colunas.

### 5.5 Pessoas

Lista com filtros: papel, plano, zona, data de registo, com relatos, suspensa, eliminada, conta de teste.

Ficha:

- CabeÃ§alho: nome, foto, papel, desde quando, estado (ativa, suspensa atÃ©, eliminada), plano e validade, mÃ©dia e nÃºmero de avaliaÃ§Ãµes.
- Contacto (revelar): email, telemÃ³vel, Ãºltimo acesso.
- Separadores: Pedidos (cliente) ou Trabalhos e Propostas (jardineiro), Ajudas, AvaliaÃ§Ãµes dadas e recebidas, Relatos, Avisos recebidos (notificaÃ§Ãµes e estado do push), Aparelhos (plataforma, data do token, sem o token), Agenda (sÃ³ nÃºmero de entradas; o conteÃºdo Ã© de terceiros e nÃ£o se abre sem motivo legal), CartÃ£o (visitas por origem, por mÃªs), Casos, AÃ§Ãµes de admin.
- AÃ§Ãµes (por papel): nota interna, avisar (mensagem na app e email), suspender (duraÃ§Ã£o, motivo, declaraÃ§Ã£o de motivos), levantar suspensÃ£o, mudar plano (jÃ¡ existe), forÃ§ar fim de sessÃ£o, exportar dados (RGPD), apagar conta (RGPD, sÃ³ `owner`, usa o mesmo fluxo da app `delete_my_account` adaptado).

**Suspender** precisa de suporte no backend: `profiles.suspended_until`, `profiles.suspension_reason`; as RPCs de escrita (`create_job`, `create_proposal`, `apply_to_help_request`, etc.) recusam com uma mensagem clara; a app mostra um ecrÃ£ "Conta suspensa atÃ© ..." com o motivo e como contestar. Para jardineiros, encerrar de vez exige aviso de 30 dias (Termos, ponto 12), por isso o painel pede a data de efeito e agenda o encerramento.

### 5.6 Relatos e denÃºncias

- Fila Ãºnica: relatos de problema da app (`job_reports`) e denÃºncias recebidas por email (criadas Ã  mÃ£o).
- Cada item: tipo, quem reportou, sobre quem ou o quÃª, pedido ligado, texto, fotos do trabalho, estado, prazo.
- DecisÃ£o: sem aÃ§Ã£o, aviso, esconder conteÃºdo, suspender, encaminhar a autoridade. Motivo obrigatÃ³rio. Gera a declaraÃ§Ã£o de motivos (Regulamento dos ServiÃ§os Digitais, art. 17) com: o que foi decidido, os factos, a regra dos Termos aplicada, se houve meios automÃ¡ticos (nÃ£o hÃ¡) e como contestar (email, 6 meses, tribunal ou resoluÃ§Ã£o extrajudicial).
- ContestaÃ§Ãµes ficam ligadas Ã  decisÃ£o e sÃ£o revistas por outra pessoa quando houver mais de um admin.

### 5.7 AvaliaÃ§Ãµes

Lista com filtros (estrelas, com comentÃ¡rio, denunciada, escondida). AÃ§Ãµes: esconder comentÃ¡rio (fica a nota), esconder avaliaÃ§Ã£o inteira (casos graves), repor. Sempre com motivo e aviso a quem escreveu.

### 5.8 Planos

O que jÃ¡ existe (`admin_set_worker_plan`) mais: histÃ³rico de planos por jardineiro, planos a acabar nos prÃ³ximos 7 dias, notas do contrato (jÃ¡ existe `worker_plans.notes`), lembrete para renovar. Sem pagamentos na app: registar referÃªncia da fatura e data de pagamento.

### 5.9 Avisos enviados

- NotificaÃ§Ãµes da app por utilizador e por pedido, com tipo, tÃ­tulo e data.
- Estado do push: entregue, falhado (e o erro do FCM), sem token. Exige guardar o resultado da Edge Function `send-push` numa tabela `push_deliveries` (ver 6.4).
- Ãštil para "nÃ£o me chegou o aviso": vÃª-se logo se a pessoa nÃ£o tem token, se o FCM falhou ou se o aviso nem foi criado.

### 5.10 Privacidade (RGPD)

- Pedidos de acesso, exportaÃ§Ã£o, retificaÃ§Ã£o e apagamento, com prazo de 1 mÃªs.
- "Exportar dados" gera um JSON com tudo o que diz respeito Ã  pessoa (perfil, pedidos, propostas, avaliaÃ§Ãµes, notificaÃ§Ãµes, plano, visitas ao cartÃ£o agregadas), para enviar por email. RPC `admin_export_user_data(p_user_id)`, sÃ³ `owner`, registado.
- "Apagar conta" pelo fluxo existente, com confirmaÃ§Ã£o dupla.
- Registo de pedidos tratados (para demonstrar cumprimento Ã  CNPD).

### 5.11 Registo

- `admin_actions`: quem mudou o quÃª, filtrÃ¡vel por admin, alvo e data.
- `admin_access_log`: quem viu que dados pessoais e porquÃª.
- SÃ³ `owner` vÃª o registo dos outros; cada admin vÃª o seu.

### 5.12 DefiniÃ§Ãµes

Gerir admins e papÃ©is (convite por email, exigir TOTP), textos modelo de resposta, limite do plano GrÃ¡tis (hoje constante na funÃ§Ã£o `free_plan_monthly_job_limit`), modo manutenÃ§Ã£o (mensagem na app).

## 6. AlteraÃ§Ãµes Ã  base de dados

Tudo em migrations novas (prÃ³ximo nÃºmero: confirmar com `ls supabase/migrations`), nunca aplicadas pelo Claude Code. Cada tabela nova com RLS ligada e sem policies (acesso sÃ³ pelas RPCs).

### 6.1 `admin_access_log`
`id, admin_id, target_type (user|job|photo|export), target_id, reason text, created_at`. Escrita dentro das RPCs de leitura sensÃ­veis.

### 6.2 `job_events`
`id, job_id, actor_id (null = sistema), kind text, payload jsonb, created_at`. Triggers `AFTER INSERT/UPDATE` em `job_requests`, `job_proposals`, `help_requests`, `help_acceptances`, `job_work_days`, `ratings`, `job_reports`, e nas funÃ§Ãµes de cron que mudam estados. `kind` com um conjunto fechado (`created`, `proposal_sent`, `proposal_withdrawn`, `accepted`, `rescheduled`, `started`, `day_finished`, `marked_done`, `confirmed`, `auto_confirmed`, `cancelled`, `expired`, `helper_*`, `rated`, `reported`, `admin_*`). ConservaÃ§Ã£o: enquanto o pedido existir.

### 6.3 `support_cases` e `support_case_entries`
Caso: `id, kind, status, user_id, job_id, received_at, first_response_due, resolution_due, assigned_to, resolved_at`. Entradas: `id, case_id, author_id, kind (message_in|message_out|note|action), body, created_at`. ConservaÃ§Ã£o: 3 anos depois de resolvido (cron de limpeza).

### 6.4 `push_deliveries`
`id, notification_id, user_id, platform, status (sent|failed|no_token), error text, created_at`. Escrita pela Edge Function `send-push`. ConservaÃ§Ã£o: 30 dias (cron).

### 6.5 ModeraÃ§Ã£o
`moderation_decisions`: `id, target_type (rating|photo|profile|job|account), target_id, decision, reason, terms_clause, statement_sent_at, decided_by, created_at, appeal_of`. Colunas `hidden_at`, `hidden_reason` em `ratings` e `job_photos`; as views e RPCs pÃºblicas passam a ignorar o que estÃ¡ escondido.

### 6.6 SuspensÃµes
`profiles.suspended_until timestamptz`, `profiles.suspension_reason text`, funÃ§Ã£o `assert_not_suspended()` chamada nas RPCs de escrita.

### 6.7 PapÃ©is
`admin_users.role text NOT NULL DEFAULT 'owner' CHECK (role IN ('owner','support','moderator'))`.

### 6.8 RPCs novas (resumo)
`admin_search`, `admin_list_jobs`, `admin_get_job` (com linha do tempo e fotos), `admin_list_people`, `admin_get_person`, `admin_reveal_contact`, `admin_list_reports`, `admin_decide_report`, `admin_hide_rating`, `admin_hide_photo`, `admin_suspend_user`, `admin_lift_suspension`, `admin_resend_notification`, `admin_cancel_job`, `admin_export_user_data`, `admin_list_cases`, `admin_get_case`, `admin_save_case`, `admin_add_case_entry`, `admin_list_actions`, `admin_list_access_log`, `admin_list_push_deliveries`. Todas com `assert_verified_admin()` e, nas que mudam coisas, `assert_admin_role(...)` e registo em `admin_actions`. Quando o `RETURNS TABLE` mudar, `DROP FUNCTION` explÃ­cito antes.

### 6.9 Fotos
As fotos estÃ£o num bucket pÃºblico (qualquer um com o URL abre). Para o painel nÃ£o Ã© problema, mas o RGPD fica mais seguro com bucket privado e URLs assinados de curta duraÃ§Ã£o. Deixar como decisÃ£o separada (mexe na app toda).

## 7. ImplementaÃ§Ã£o na app (Flutter web)

- Pasta `lib/features/admin/`, mesmo padrÃ£o do resto: repository (sÃ³ RPCs), providers, wrapper + view pura com ViewData.
- `AdminShell` prÃ³prio com navegaÃ§Ã£o lateral (nÃ£o reutilizar os shells de cliente e jardineiro). Rotas `/admin/...` fora dos ShellRoutes da app.
- Tabelas com ordenaÃ§Ã£o e paginaÃ§Ã£o no servidor (`p_page`, `p_page_size`), esqueletos enquanto carrega, estado vazio e erro com "Tentar novamente".
- URLs partilhÃ¡veis: `/admin/jobs/:id`, `/admin/people/:id`, `/admin/cases/:id` (para colar num email interno).
- Datas sempre em hora de Lisboa, com o dia da semana.
- Atalhos de teclado: `/` foca a pesquisa, `Esc` fecha o painel de detalhe.
- Galeria de fotos com o `photo_viewer_screen.dart` existente.

## 8. Fases

**Fase 1, antes do lanÃ§amento (o mÃ­nimo para dar suporte):** pesquisa global, Pessoas (lista e ficha sÃ³ de leitura, revelar contacto registado), Pedidos (lista e detalhe com linha do tempo a partir das colunas que jÃ¡ existem, fotos), Relatos (lista e marcar tratado), `admin_access_log`, papÃ©is.

**Fase 2, primeiras semanas:** `job_events` com triggers, `push_deliveries`, Avisos enviados, Casos de suporte, notas internas.

**Fase 3:** ModeraÃ§Ã£o completa (esconder, suspender, declaraÃ§Ãµes de motivos, contestaÃ§Ãµes), AvaliaÃ§Ãµes, Privacidade (exportar e apagar), histÃ³rico de planos, DefiniÃ§Ãµes.

## 9. Como testar

- Testes SQL (`supabase/tests/audit/`): cada RPC recusa sem sessÃ£o, sem MFA, sem ser admin e com o papel errado; regista em `admin_actions` e `admin_access_log`; nÃ£o devolve nada escondido nas RPCs pÃºblicas.
- Testes Flutter das views puras (ViewData de exemplo) e dos presenters da linha do tempo.
- Teste manual: um caso real de ponta a ponta (cliente queixa-se de que o jardineiro nÃ£o apareceu): encontrar pela pesquisa, ver a linha do tempo, ver os avisos enviados, decidir, responder com o texto modelo, fechar o caso.

## 10. O que nÃ£o fazer

- NÃ£o ler tabelas diretamente da app do painel, nem com a service role key no cliente.
- NÃ£o aceitar o id do admin vindo da app.
- NÃ£o mostrar telefones, emails e moradas em listas.
- NÃ£o apagar conteÃºdo como forma de moderaÃ§Ã£o normal.
- NÃ£o abrir a Agenda dos jardineiros (dados de terceiros) sem motivo legal registado.
- NÃ£o mostrar o painel na app mÃ³vel nem na bottom nav.
