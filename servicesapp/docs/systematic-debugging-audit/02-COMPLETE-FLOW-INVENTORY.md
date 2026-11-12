# 02. Inventário completo dos fluxos

Estado auditado: ramo do PR #47 (`claude/project-thread-4zzdn3`, commit `7c9f539`), que é o `main` mais as migrations 0071 a 0073. Total: **80 fluxos**. A ordem segue os grupos: conta (001 a 014), cliente (020 a 039), jardineiro (040 a 060), comum (070 a 079), admin (080 a 082), processos automáticos e transversais (090 a 101).

Os números saltam de propósito entre grupos para haver espaço para fluxos novos sem renumerar.

## Índice

| ID | Fluxo | Utilizador | Relacionados |
|---|---|---|---|
| [FLOW-001](#flow-001) | Onboarding (3 slides, primeira vez) | Visitante | FLOW-002, FLOW-009 |
| [FLOW-002](#flow-002) | Registo com email e senha | Visitante | FLOW-003, FLOW-006 |
| [FLOW-003](#flow-003) | Confirmação de email por código | Visitante registado | FLOW-002, FLOW-004 |
| [FLOW-004](#flow-004) | Login com email e senha | Utilizador registado | FLOW-009, FLOW-014 |
| [FLOW-005](#flow-005) | Login social Google/Facebook | Visitante | FLOW-006 |
| [FLOW-006](#flow-006) | Escolher papel (e telemóvel) | Utilizador sem papel | FLOW-007, FLOW-014 |
| [FLOW-007](#flow-007) | Setup do jardineiro (raio, base, serviços) | Jardineiro novo | FLOW-040, FLOW-099 |
| [FLOW-008](#flow-008) | Recuperar senha (OTP em 4 passos) | Utilizador registado | FLOW-004 |
| [FLOW-009](#flow-009) | Arranque e sessão (loading, restauro, erro de perfil) | Todos | FLOW-004, FLOW-014 |
| [FLOW-010](#flow-010) | Terminar sessão | Todos | FLOW-073 |
| [FLOW-011](#flow-011) | Eliminar conta | Cliente ou jardineiro | FLOW-002 |
| [FLOW-012](#flow-012) | Editar perfil do cliente (nome, telefone, foto) | Cliente | FLOW-077 |
| [FLOW-013](#flow-013) | Editar perfil do jardineiro (3 secções, destaques, links) | Jardineiro | FLOW-055, FLOW-091 |
| [FLOW-014](#flow-014) | Guarda de rotas por papel | Todos | todos |
| [FLOW-020](#flow-020) | Criar pedido (4 passos, rascunho, fotos) | Cliente | FLOW-021, FLOW-040, FLOW-099 |
| [FLOW-021](#flow-021) | Limite de 5 pedidos por hora | Cliente | FLOW-020 |
| [FLOW-022](#flow-022) | Editar pedido aberto | Cliente | FLOW-020 |
| [FLOW-023](#flow-023) | Pedido sem propostas: alargar pesquisa e avisos | Cliente | FLOW-094 |
| [FLOW-024](#flow-024) | Ver propostas recebidas (e recomendada) | Cliente | FLOW-025 |
| [FLOW-025](#flow-025) | Aceitar proposta | Cliente | FLOW-026, FLOW-043, FLOW-050 |
| [FLOW-026](#flow-026) | Recusar proposta | Cliente | FLOW-033 |
| [FLOW-027](#flow-027) | Detalhe do pedido do cliente (por estado) | Cliente | FLOW-025..FLOW-032 |
| [FLOW-028](#flow-028) | Confirmar conclusão | Cliente | FLOW-030, FLOW-091 |
| [FLOW-029](#flow-029) | Reportar problema depois de concluído | Cliente ou jardineiro | FLOW-091 |
| [FLOW-030](#flow-030) | Avaliar o jardineiro | Cliente | FLOW-074 |
| [FLOW-031](#flow-031) | Cancelar pedido ou trabalho (e reabrir) | Cliente ou jardineiro aceite | FLOW-020 |
| [FLOW-032](#flow-032) | Remarcar (propor, aceitar, recusar) | Cliente ou jardineiro aceite | FLOW-031 |
| [FLOW-033](#flow-033) | Pedir de novo (pedido direto, 24h) | Cliente | FLOW-034, FLOW-093 |
| [FLOW-034](#flow-034) | Pedido pelo cartão público /w/:id | Visitante → cliente | FLOW-033, FLOW-091 |
| [FLOW-035](#flow-035) | Os teus jardineiros (anteriores) | Cliente | FLOW-033 |
| [FLOW-036](#flow-036) | Contacto por WhatsApp | Cliente, jardineiro, ajudante | FLOW-025 |
| [FLOW-037](#flow-037) | Aprovar pedido de ajudantes (cliente) | Cliente | FLOW-050, FLOW-095 |
| [FLOW-038](#flow-038) | Início e lista de pedidos do cliente | Cliente | FLOW-027 |
| [FLOW-039](#flow-039) | Dicas da época (preferência) | Cliente | FLOW-097 |
| [FLOW-040](#flow-040) | Descobrir pedidos no raio | Jardineiro | FLOW-041 |
| [FLOW-041](#flow-041) | Detalhe da oportunidade (zona aproximada) | Jardineiro | FLOW-042 |
| [FLOW-042](#flow-042) | Enviar proposta (hora ou valor total) | Jardineiro | FLOW-024, FLOW-057 |
| [FLOW-043](#flow-043) | Retirar proposta | Jardineiro | FLOW-025 |
| [FLOW-044](#flow-044) | Recusar pedido direto ('Não posso desta vez') | Jardineiro escolhido | FLOW-033 |
| [FLOW-045](#flow-045) | Os meus trabalhos (Agenda · Propostas · Histórico) | Jardineiro | FLOW-053 |
| [FLOW-046](#flow-046) | Iniciar trabalho (fotos de antes) | Jardineiro responsável | FLOW-048 |
| [FLOW-047](#flow-047) | Trabalho por dias / vários dias | Jardineiro e cliente | FLOW-059, FLOW-090 |
| [FLOW-048](#flow-048) | Marcar como concluído (fotos de depois) | Jardineiro responsável | FLOW-028, FLOW-091 |
| [FLOW-049](#flow-049) | Avaliar cliente e ajudantes | Jardineiro responsável e ajudante | FLOW-074 |
| [FLOW-050](#flow-050) | Pedir ajudantes e gerir a equipa | Jardineiro responsável | FLOW-051, FLOW-095 |
| [FLOW-051](#flow-051) | Candidatar-se como ajudante / desistir | Jardineiro | FLOW-050 |
| [FLOW-052](#flow-052) | Trabalho visto pelo ajudante | Ajudante aceite | FLOW-050 |
| [FLOW-053](#flow-053) | Agenda (Hoje, Semana, Mês) | Jardineiro | FLOW-054 |
| [FLOW-054](#flow-054) | Agenda: adicionar, editar, apagar e séries | Jardineiro | FLOW-053 |
| [FLOW-055](#flow-055) | Cartão partilhável (QR, imagem, PDF, link) | Jardineiro | FLOW-034 |
| [FLOW-056](#flow-056) | Painel de ganhos (Pro) | Jardineiro Pro | FLOW-057 |
| [FLOW-057](#flow-057) | Plano e limite do Grátis | Jardineiro | FLOW-042, FLOW-082 |
| [FLOW-058](#flow-058) | Cartão frota (demo, OCR) | Jardineiro | nenhum |
| [FLOW-059](#flow-059) | Lembretes de início e atraso (0072) | Jardineiro | FLOW-098 |
| [FLOW-060](#flow-060) | Início do jardineiro (dashboard) | Jardineiro | FLOW-045 |
| [FLOW-070](#flow-070) | Lista de notificações (ler, filtros, limpar e desfazer) | Todos | FLOW-071 |
| [FLOW-071](#flow-071) | Abrir o destino ao tocar numa notificação | Todos | FLOW-075 |
| [FLOW-072](#flow-072) | Aviso no topo com a app aberta | Todos | FLOW-071 |
| [FLOW-073](#flow-073) | Push FCM | Todos (Android/iOS) | FLOW-071 |
| [FLOW-074](#flow-074) | As minhas avaliações (recebidas e dadas) | Todos | FLOW-030 |
| [FLOW-075](#flow-075) | Voltar, deep links e PopScope | Todos | FLOW-071 |
| [FLOW-076](#flow-076) | Contacto e suporte, Sobre, links legais | Todos | nenhum |
| [FLOW-077](#flow-077) | Uploads para o Storage (avatar e fotos) | Todos | FLOW-012, FLOW-020 |
| [FLOW-078](#flow-078) | Morada e GPS (Photon, Nominatim, geocoder nativo) | Cliente e jardineiro | FLOW-020, FLOW-007 |
| [FLOW-079](#flow-079) | Erros, sem rede e timeouts | Todos | todos |
| [FLOW-080](#flow-080) | Entrar no painel /admin (login + 2.º fator) | Admin | FLOW-081 |
| [FLOW-081](#flow-081) | Visão geral, lista e ficha de jardineiros | Admin | FLOW-082 |
| [FLOW-082](#flow-082) | Atribuir plano a um jardineiro | Admin | FLOW-057 |
| [FLOW-090](#flow-090) | Expirar pedidos e trabalhos (auto_expire_jobs) | Sistema (pg_cron) | FLOW-020, FLOW-047 |
| [FLOW-091](#flow-091) | Confirmação automática (48h; 7 dias com relato) | Sistema (pg_cron) | FLOW-028, FLOW-029 |
| [FLOW-092](#flow-092) | Lembretes diários (send_job_reminders) | Sistema (pg_cron) | FLOW-047 |
| [FLOW-093](#flow-093) | Fim da reserva do pedido direto | Sistema (pg_cron) | FLOW-033 |
| [FLOW-094](#flow-094) | Pedidos sem propostas (6h e 24h) | Sistema (pg_cron) | FLOW-023 |
| [FLOW-095](#flow-095) | Prazos dos pedidos de ajuda | Sistema (pg_cron) | FLOW-050 |
| [FLOW-096](#flow-096) | Limpeza (notificações, emails bloqueados) | Sistema (pg_cron) | FLOW-070, FLOW-011 |
| [FLOW-097](#flow-097) | Dicas da época | Sistema (pg_cron) | FLOW-039 |
| [FLOW-098](#flow-098) | Lembretes de início (0072) | Sistema (pg_cron) | FLOW-059 |
| [FLOW-099](#flow-099) | Avisar jardineiros de pedidos e ajudas novos (triggers) | Sistema | FLOW-007, FLOW-020 |
| [FLOW-100](#flow-100) | Versão web (Netlify) | Todos | todos |
| [FLOW-101](#flow-101) | Ações repetidas e concorrentes (transversal) | Todos | FLOW-025, FLOW-043, FLOW-020 |

## Transições entre fluxos (caminho principal)

```
FLOW-001 onboarding → FLOW-002 registo → FLOW-003 confirmar email → FLOW-006 papel
   ├─ cliente: FLOW-020 criar pedido → (FLOW-099 avisa jardineiros) → FLOW-024 propostas → FLOW-025 aceitar
   │           → FLOW-027 acompanhar → FLOW-028 confirmar → FLOW-030 avaliar → FLOW-033 pedir de novo
   └─ jardineiro: FLOW-007 setup → FLOW-040 descobrir → FLOW-042 propor → (aceite) FLOW-046 iniciar
               → FLOW-048 concluir → FLOW-049 avaliar; com ajudantes FLOW-050/051/052
Saídas: FLOW-031 cancelar, FLOW-032 remarcar, FLOW-043 retirar, FLOW-090 expirar, FLOW-091 confirmação automática
Entrada alternativa: QR/link → FLOW-034 cartão público → registo → pedido direto (FLOW-033/093)
```

## Funcionalidades inacessíveis ou desligadas

- `features/proposals/presentation/` está vazia (convenção conhecida, ver ARCHITECTURE.md secção 16).
- Rotas de Mensagens foram removidas a 18/10 (contacto só por WhatsApp). Não há código morto de chat.
- "Ver o local primeiro" (visita paga) ficou para a fase 2: não existe no código.
- Login com Apple: adiado até haver app iOS.
- Push e OCR não existem na web (desligam-se sozinhos).
- `get_my_earnings` e o selo do plano dependem da 0067, que está no repositório mas **não está aplicada** na BD viva; o painel de ganhos mostra "indisponível" (`isMissingRpcError`) até ser aplicada.
- Código de compatibilidade com migrations antigas (PGRST202, `WorkerPlan.unavailable`) continua no código; não faz mal (ARCHITECTURE.md secção 16, ponto 9).

## Ficha de cada fluxo

### FLOW-001

- **Nome:** Onboarding (3 slides, primeira vez)
- **Objetivo:** Apresentar a app antes do registo
- **Tipo de utilizador:** Visitante
- **Ponto de entrada:** /onboarding (automático na 1.ª abertura sem sessão)
- **Pré-condições:** Sem sessão; flag local hasSeenOnboarding=false
- **Passos:** 1. Abrir a app. 2. Passar os 3 slides. 3. Tocar em começar.
- **Componentes envolvidos:** ProJardimOnboardingScreen, OnboardingPageIndicator, hasSeenOnboardingProvider
- **Serviços/backend envolvidos:** Nenhum (shared_preferences)
- **Dados utilizados:** Flag local
- **Resultado esperado:** Vai para / e não volta a mostrar
- **Possíveis pontos de falha:** shared_preferences indisponível (web privada); flag não gravada
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-002, FLOW-009

### FLOW-002

- **Nome:** Registo com email e senha
- **Objetivo:** Criar conta
- **Tipo de utilizador:** Visitante
- **Ponto de entrada:** /signup
- **Pré-condições:** Sem sessão
- **Passos:** 1. Nome, telefone, email, senha (8+, maiúscula, número). 2. Aceitar termos. 3. Criar conta. 4. Segue para /verify-email ou /choose-role.
- **Componentes envolvidos:** SignupScreen, AppPasswordStrengthMeter, AuthRepository.signUp/createProfile
- **Serviços/backend envolvidos:** Supabase Auth signUp; profiles.upsert (RLS: só o próprio id)
- **Dados utilizados:** auth.users, profiles
- **Resultado esperado:** Conta criada, perfil com nome e telefone
- **Possíveis pontos de falha:** Email já registado; senha fraca; rede; email bloqueado 90 dias depois de eliminar (trigger)
- **Dependências externas:** Supabase Auth, SMTP (se confirmação ligada)
- **Fluxos relacionados:** FLOW-003, FLOW-006

### FLOW-003

- **Nome:** Confirmação de email por código
- **Objetivo:** Validar o email antes de entrar
- **Tipo de utilizador:** Visitante registado
- **Ponto de entrada:** /verify-email
- **Pré-condições:** Confirm email ligado no Supabase; SMTP configurado
- **Passos:** 1. Receber código de 6 dígitos. 2. Escrever no AppOtpInput. 3. verifyOTP(signup) abre sessão.
- **Componentes envolvidos:** VerifyEmailScreen, AppOtpInput
- **Serviços/backend envolvidos:** Supabase Auth verifyOTP
- **Dados utilizados:** nenhum
- **Resultado esperado:** Sessão aberta, segue para /choose-role
- **Possíveis pontos de falha:** Código errado/expirado; reenvio; email na pasta de spam
- **Dependências externas:** Supabase Auth + SMTP (Brevo)
- **Fluxos relacionados:** FLOW-002, FLOW-004

### FLOW-004

- **Nome:** Login com email e senha
- **Objetivo:** Entrar
- **Tipo de utilizador:** Utilizador registado
- **Ponto de entrada:** /login
- **Pré-condições:** Conta existente
- **Passos:** 1. Email e senha. 2. Entrar. 3. Router manda para o início do papel (ou para ?from=).
- **Componentes envolvidos:** LoginScreen, AuthController, SessionNotifier, resolveRedirect
- **Serviços/backend envolvidos:** Supabase Auth signInWithPassword; profiles (SELECT próprio)
- **Dados utilizados:** profiles.role
- **Resultado esperado:** Entra no início do papel certo
- **Possíveis pontos de falha:** Senha errada; email por confirmar (reenvia código); conta eliminada (login bloqueado); sem rede
- **Dependências externas:** Supabase Auth
- **Fluxos relacionados:** FLOW-009, FLOW-014

### FLOW-005

- **Nome:** Login social Google/Facebook
- **Objetivo:** Entrar sem senha
- **Tipo de utilizador:** Visitante
- **Ponto de entrada:** / ou /login (botões sociais)
- **Pré-condições:** OAuth configurado no Supabase, Google e Meta
- **Passos:** 1. Tocar em Google/Facebook. 2. Browser externo. 3. Volta por pt.projardim.app://login-callback (ou /login-callback na web). 4. Conta nova vai a /choose-role.
- **Componentes envolvidos:** AuthRepository.signInWithSocial, importSocialAvatar
- **Serviços/backend envolvidos:** Supabase Auth OAuth; Storage avatars
- **Dados utilizados:** auth.users, profiles, avatars/<id>.jpg
- **Resultado esperado:** Sessão aberta; foto copiada; telemóvel pedido se faltar
- **Possíveis pontos de falha:** Deep link não volta à app; conta Facebook sem email; foto falha (melhor esforço)
- **Dependências externas:** Google OAuth, Meta, deep links Android/iOS
- **Fluxos relacionados:** FLOW-006

### FLOW-006

- **Nome:** Escolher papel (e telemóvel)
- **Objetivo:** Definir cliente ou jardineiro
- **Tipo de utilizador:** Utilizador sem papel
- **Ponto de entrada:** /choose-role (forçado pelo router)
- **Pré-condições:** Sessão aberta, perfil sem role
- **Passos:** 1. Escolher papel. 2. Telemóvel se faltar. 3. Grava role. 4. Cliente → /client/home; jardineiro → /worker/setup.
- **Componentes envolvidos:** ChooseRoleScreen, RegistrationIdentity
- **Serviços/backend envolvidos:** profiles (UPDATE próprio); trigger tg_prevent_profile_role_change
- **Dados utilizados:** profiles.role, phone
- **Resultado esperado:** Papel gravado uma vez, não muda depois
- **Possíveis pontos de falha:** Mudar de papel por API (bloqueado); rede a meio
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-007, FLOW-014

### FLOW-007

- **Nome:** Setup do jardineiro (raio, base, serviços)
- **Objetivo:** Completar o perfil para receber pedidos
- **Tipo de utilizador:** Jardineiro novo
- **Ponto de entrada:** /worker/setup (forçado enquanto incompleto)
- **Pré-condições:** role=worker
- **Passos:** 1. Raio 1 a 50 km (slider). 2. Base por GPS ou morada. 3. Serviços (serviceTypesProvider). 4. Ferramentas. 5. Guardar.
- **Componentes envolvidos:** WorkerSetupScreen, GeocodingService, ServiceCategorySection
- **Serviços/backend envolvidos:** worker_profiles (UPSERT próprio), sync_worker_service_types
- **Dados utilizados:** worker_profiles, worker_service_types
- **Resultado esperado:** Perfil completo, router liberta as rotas /worker/*
- **Possíveis pontos de falha:** Permissão de GPS negada; geocoding falha; raio fora de 1-50 por API
- **Dependências externas:** GPS do dispositivo, Nominatim/Photon
- **Fluxos relacionados:** FLOW-040, FLOW-099

### FLOW-008

- **Nome:** Recuperar senha (OTP em 4 passos)
- **Objetivo:** Voltar a entrar sem a senha
- **Tipo de utilizador:** Utilizador registado
- **Ponto de entrada:** /forgot-password/request
- **Pré-condições:** SMTP e template com {{ .Token }}
- **Passos:** 1. Email. 2. Código de 6 dígitos (verifyOTP recovery). 3. Senha nova (updateUser). 4. Sai e volta ao login.
- **Componentes envolvidos:** RequestPasswordResetScreen, PasswordResetScreen, PasswordResetController
- **Serviços/backend envolvidos:** Supabase Auth
- **Dados utilizados:** nenhum
- **Resultado esperado:** Senha trocada
- **Possíveis pontos de falha:** Código errado; rede; bypass de kDebugMode só em debug
- **Dependências externas:** Supabase Auth + SMTP
- **Fluxos relacionados:** FLOW-004

### FLOW-009

- **Nome:** Arranque e sessão (loading, restauro, erro de perfil)
- **Objetivo:** Abrir a app no sítio certo
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** /loading
- **Pré-condições:** nenhum
- **Passos:** 1. Supabase.initialize. 2. Sessão restaurada do armazenamento. 3. Perfil lido. 4. Redirect; sem rede → /session-error.
- **Componentes envolvidos:** main.dart, SessionNotifier, RouterNotifier, SessionErrorScreen
- **Serviços/backend envolvidos:** profiles (SELECT próprio)
- **Dados utilizados:** Sessão local
- **Resultado esperado:** Ecrã inicial do papel; com perfil por carregar, ecrã de tentar novamente
- **Possíveis pontos de falha:** Token expirado; rede; Firebase sem ficheiros (desliga-se)
- **Dependências externas:** Supabase
- **Fluxos relacionados:** FLOW-004, FLOW-014

### FLOW-010

- **Nome:** Terminar sessão
- **Objetivo:** Sair da conta
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Conta > Terminar sessão
- **Pré-condições:** Sessão aberta
- **Passos:** 1. Confirmar. 2. Apaga o token push. 3. signOut. 4. Vai para /.
- **Componentes envolvidos:** sign_out_flow.dart, AuthController.signOut, PushNotificationService.unregister
- **Serviços/backend envolvidos:** unregister_device_token; Supabase Auth
- **Dados utilizados:** device_tokens
- **Resultado esperado:** Sem sessão, sem push neste aparelho
- **Possíveis pontos de falha:** Rede falha a meio (token fica); push continua a chegar
- **Dependências externas:** FCM
- **Fluxos relacionados:** FLOW-073

### FLOW-011

- **Nome:** Eliminar conta
- **Objetivo:** Apagar dados pessoais (RGPD, lojas)
- **Tipo de utilizador:** Cliente ou jardineiro
- **Ponto de entrada:** Conta > Eliminar conta
- **Pré-condições:** Sem trabalho em curso que bloqueie
- **Passos:** 1. check_can_delete_my_account. 2. Confirmar. 3. delete_my_account anonimiza, fecha pedidos, apaga tokens. 4. signOut local.
- **Componentes envolvidos:** delete_account_flow.dart
- **Serviços/backend envolvidos:** check_can_delete_my_account, delete_my_account, trigger de bloqueio do email
- **Dados utilizados:** profiles, job_requests, device_tokens, ...
- **Resultado esperado:** Conta anonimizada, pedidos abertos fechados, login bloqueado
- **Possíveis pontos de falha:** Trabalho ativo; ficheiros do Storage não apagados (conhecido)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-002

### FLOW-012

- **Nome:** Editar perfil do cliente (nome, telefone, foto)
- **Objetivo:** Manter dados de contacto
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/profile/edit
- **Pré-condições:** Sessão
- **Passos:** 1. Alterar campos. 2. Foto da galeria/câmara, comprimida. 3. Guardar.
- **Componentes envolvidos:** ClientEditProfileScreen/View
- **Serviços/backend envolvidos:** profiles (UPDATE próprio), Storage avatars
- **Dados utilizados:** profiles, avatars/<id>.jpg
- **Resultado esperado:** Dados atualizados
- **Possíveis pontos de falha:** Texto sem limite na BD; foto grande; permissão da câmara
- **Dependências externas:** image_picker
- **Fluxos relacionados:** FLOW-077

### FLOW-013

- **Nome:** Editar perfil do jardineiro (3 secções, destaques, links)
- **Objetivo:** Mostrar o trabalho no cartão
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/profile/edit
- **Pré-condições:** Perfil completo
- **Passos:** 1. Dados. 2. Zona e serviços. 3. Destaques (5×80) e links https.
- **Componentes envolvidos:** WorkerEditProfileScreen, worker_showcase_*
- **Serviços/backend envolvidos:** worker_profiles, sync_worker_service_types
- **Dados utilizados:** worker_profiles.highlights, social_links, bio
- **Resultado esperado:** Cartão público atualizado
- **Possíveis pontos de falha:** bio sem limite na BD; raio sem limite na BD
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-055, FLOW-091

### FLOW-014

- **Nome:** Guarda de rotas por papel
- **Objetivo:** Cada papel só nas suas rotas
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Qualquer rota
- **Pré-condições:** nenhum
- **Passos:** Router aplica resolveRedirect em cada navegação.
- **Componentes envolvidos:** route_guard.dart, app_router.dart
- **Serviços/backend envolvidos:** nenhum (a segurança real é a RLS)
- **Dados utilizados:** SessionStatus
- **Resultado esperado:** Cliente em /worker/* vai para /client/home e vice-versa; sem sessão vai para / com ?from=
- **Possíveis pontos de falha:** Open redirect por ?from= (protegido por safeReturnTarget)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** todos

### FLOW-020

- **Nome:** Criar pedido (4 passos, rascunho, fotos)
- **Objetivo:** Publicar um pedido
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/create-job (botão central)
- **Pré-condições:** Sessão de cliente
- **Passos:** 1. Serviço. 2. Data (fixa, flexível, disponibilidade), dimensão, morada/GPS. 3. Descrição e até 2 fotos. 4. Rever e publicar.
- **Componentes envolvidos:** ClientCreateJob*Screen, JobLocationPicker, JobRepository.createJob
- **Serviços/backend envolvidos:** INSERT job_requests (RLS), job_photos, Storage job-photos, trigger notify_workers_new_job
- **Dados utilizados:** job_requests, job_photos
- **Resultado esperado:** Pedido open, jardineiros do raio avisados
- **Possíveis pontos de falha:** Data fixa no passado aceite pela BD; campos de execução aceites no INSERT; 3.ª foto por corrida; sair a meio do envio
- **Dependências externas:** Photon/Nominatim, GPS, Storage
- **Fluxos relacionados:** FLOW-021, FLOW-040, FLOW-099

### FLOW-021

- **Nome:** Limite de 5 pedidos por hora
- **Objetivo:** Travar abuso
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Publicar
- **Pré-condições:** 5 pedidos na última hora
- **Passos:** Publicar o 6.º
- **Componentes envolvidos:** RLS de INSERT (client_recent_job_count)
- **Serviços/backend envolvidos:** job_requests
- **Dados utilizados:** nenhum
- **Resultado esperado:** 6.º recusado
- **Possíveis pontos de falha:** Mensagem genérica de RLS na app?
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-020

### FLOW-022

- **Nome:** Editar pedido aberto
- **Objetivo:** Corrigir um pedido antes de aceitar
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/job/:id/edit
- **Pré-condições:** Pedido open
- **Passos:** 1. Editar descrição, data, morada. 2. Guardar. 3. Quem já propôs é avisado (job_updated).
- **Componentes envolvidos:** ClientEditJobScreen
- **Serviços/backend envolvidos:** update_job_request
- **Dados utilizados:** job_requests
- **Resultado esperado:** Pedido atualizado, avisos enviados
- **Possíveis pontos de falha:** Pedido já não aberto; data no passado
- **Dependências externas:** Geocoding
- **Fluxos relacionados:** FLOW-020

### FLOW-023

- **Nome:** Pedido sem propostas: alargar pesquisa e avisos
- **Objetivo:** Conseguir propostas
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Cartão 'Ainda sem propostas' no detalhe
- **Pré-condições:** Pedido open sem propostas
- **Passos:** 1. Cron às 6h e 24h. 2. Cliente toca em alargar (+10 km, máx. 30).
- **Componentes envolvidos:** client_job_detail_screen
- **Serviços/backend envolvidos:** widen_job_search, process_open_job_followups
- **Dados utilizados:** job_requests.search_extra_km
- **Resultado esperado:** Pedido visto mais longe
- **Possíveis pontos de falha:** Outra pessoa a alargar (recusado)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-094

### FLOW-024

- **Nome:** Ver propostas recebidas (e recomendada)
- **Objetivo:** Comparar propostas
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/job/:id/proposals
- **Pré-condições:** Pedido com propostas
- **Passos:** 1. Lista com nome, foto, preço, selo do plano. 2. Recomendada = melhor média com 3+ avaliações.
- **Componentes envolvidos:** ClientProposalsScreen
- **Serviços/backend envolvidos:** get_pending_proposals_for_job
- **Dados utilizados:** job_proposals + identidade
- **Resultado esperado:** Só o dono vê
- **Possíveis pontos de falha:** Outro cliente a ler (recusado)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-025

### FLOW-025

- **Nome:** Aceitar proposta
- **Objetivo:** Contratar um jardineiro
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/job/:id/proposals/:proposalId → Aceitar por X
- **Pré-condições:** Proposta pendente válida
- **Passos:** 1. Ver detalhe. 2. Aceitar. 3. Pedido confirmed, outras recusadas, pedido de ajudantes se >1 pessoa. 4. Ecrã de confirmado com WhatsApp.
- **Componentes envolvidos:** ClientProposalDetailScreen, ClientJobConfirmedScreen
- **Serviços/backend envolvidos:** accept_proposal (FOR UPDATE), triggers de plano, validade e pedido direto
- **Dados utilizados:** job_requests, job_proposals, help_requests, notifications
- **Resultado esperado:** Um só jardineiro aceite, avisos certos
- **Possíveis pontos de falha:** Duplo toque; aceitar e o jardineiro retirar ao mesmo tempo (estado incoerente); orçamento expirado; pedido já fechado
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-026, FLOW-043, FLOW-050

### FLOW-026

- **Nome:** Recusar proposta
- **Objetivo:** Dizer que não a uma proposta
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Detalhe da proposta
- **Pré-condições:** Proposta pendente
- **Passos:** 1. Recusar. 2. Jardineiro avisado; se era o pedido direto, abre a todos.
- **Componentes envolvidos:** ClientProposalDetailScreen
- **Serviços/backend envolvidos:** reject_proposal (FOR UPDATE)
- **Dados utilizados:** job_proposals
- **Resultado esperado:** Proposta rejected
- **Possíveis pontos de falha:** Pedido direto recusado abre a todos (trigger)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-033

### FLOW-027

- **Nome:** Detalhe do pedido do cliente (por estado)
- **Objetivo:** Saber o que se passa e o próximo passo
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/job/:id
- **Pré-condições:** Pedido do próprio
- **Passos:** Stepper do topo, cartões por estado, ações (remarcar, cancelar, confirmar, avaliar, pedir de novo).
- **Componentes envolvidos:** ClientJobDetailScreen, JobFlowStepper, client_job_flow.dart
- **Serviços/backend envolvidos:** get_job_by_id, get_job_work_days, get_accepted_helpers_for_job
- **Dados utilizados:** nenhum
- **Resultado esperado:** Texto e ações certas em cada estado
- **Possíveis pontos de falha:** Estado mudou noutro aparelho (Realtime invalida)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-025..FLOW-032

### FLOW-028

- **Nome:** Confirmar conclusão
- **Objetivo:** Fechar o trabalho
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Detalhe: 'Confirmar que está feito'
- **Pré-condições:** awaiting_confirmation
- **Passos:** 1. Confirmar. 2. Pedido completed. 3. Pede avaliação.
- **Componentes envolvidos:** ClientJobDetailScreen
- **Serviços/backend envolvidos:** confirm_job_completion (FOR UPDATE)
- **Dados utilizados:** job_requests
- **Resultado esperado:** completed
- **Possíveis pontos de falha:** Duplo toque; outra pessoa a confirmar
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-030, FLOW-091

### FLOW-029

- **Nome:** Reportar problema depois de concluído
- **Objetivo:** Travar a confirmação automática
- **Tipo de utilizador:** Cliente ou jardineiro
- **Ponto de entrada:** Detalhe: 'Reportar um problema'
- **Pré-condições:** Trabalho marcado concluído
- **Passos:** 1. Descrição. 2. Enviar. 3. Confirmação automática passa a 7 dias (0071).
- **Componentes envolvidos:** client_job_detail_screen (AppSheet)
- **Serviços/backend envolvidos:** INSERT job_reports (RLS), trigger notify_job_report
- **Dados utilizados:** job_reports
- **Resultado esperado:** Relato gravado, outra parte avisada
- **Possíveis pontos de falha:** Descrição sem limite na BD
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-091

### FLOW-030

- **Nome:** Avaliar o jardineiro
- **Objetivo:** Dar estrelas e comentário
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/job/:id/rate-worker
- **Pré-condições:** Pedido completed
- **Passos:** 1. 1 a 5 estrelas. 2. Comentário. 3. Enviar.
- **Componentes envolvidos:** ClientRateWorkerScreen, RatingStarsInput
- **Serviços/backend envolvidos:** submit_client_rating
- **Dados utilizados:** ratings
- **Resultado esperado:** Uma avaliação por pessoa e trabalho
- **Possíveis pontos de falha:** Segunda avaliação ignorada sem aviso; estrelas fora de 1-5
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-074

### FLOW-031

- **Nome:** Cancelar pedido ou trabalho (e reabrir)
- **Objetivo:** Desistir
- **Tipo de utilizador:** Cliente ou jardineiro aceite
- **Ponto de entrada:** Detalhe: Cancelar
- **Pré-condições:** Pedido open/confirmed não iniciado
- **Passos:** 1. Motivo. 2. Voltar a publicar? 3. cancel_job (reabre pedido novo se pedido).
- **Componentes envolvidos:** Diálogo de cancelar
- **Serviços/backend envolvidos:** cancel_job (FOR UPDATE)
- **Dados utilizados:** job_requests, job_proposals, help_requests
- **Resultado esperado:** cancelled, propostas recusadas, ajudantes avisados
- **Possíveis pontos de falha:** Trabalho iniciado (recusado); 24h; outra pessoa
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-020

### FLOW-032

- **Nome:** Remarcar (propor, aceitar, recusar)
- **Objetivo:** Mudar a data combinada
- **Tipo de utilizador:** Cliente ou jardineiro aceite
- **Ponto de entrada:** Detalhe: Remarcar
- **Pré-condições:** confirmed
- **Passos:** 1. Propor data. 2. Outra parte aceita ou recusa.
- **Componentes envolvidos:** Diálogo de remarcar
- **Serviços/backend envolvidos:** propose_reschedule, accept_reschedule, reject_reschedule
- **Dados utilizados:** job_requests.reschedule_*
- **Resultado esperado:** Nova data gravada; ajudantes avisados
- **Possíveis pontos de falha:** Data passada; aceitar a própria; depois de iniciado
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-031

### FLOW-033

- **Nome:** Pedir de novo (pedido direto, 24h)
- **Objetivo:** Voltar a contratar o mesmo jardineiro
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Pedido concluído: 'Pedir de novo'
- **Pré-condições:** Trabalho concluído com esse jardineiro
- **Passos:** 1. Pedido novo com direct_source_job_id. 2. 24h só para ele. 3. Responde, recusa ou expira (abre a todos ou fica parado).
- **Componentes envolvidos:** client_create_job_*, direct_request presenters
- **Serviços/backend envolvidos:** trigger job_request_direct_before_insert, decline/release, expire_direct_job_requests
- **Dados utilizados:** job_requests.direct_*
- **Resultado esperado:** Reserva respeitada; avisos certos
- **Possíveis pontos de falha:** Jardineiro eliminou a conta; reserva expira com proposta já enviada (corrigido na 0073)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-034, FLOW-093

### FLOW-034

- **Nome:** Pedido pelo cartão público /w/:id
- **Objetivo:** Cliente novo pede a um jardineiro que conheceu
- **Tipo de utilizador:** Visitante → cliente
- **Ponto de entrada:** QR ou link /w/:workerId
- **Pré-condições:** Cartão ligado (plano)
- **Passos:** 1. Abrir cartão (visita registada). 2. Pedir orçamento. 3. Registo/login. 4. Pedido direto pelo cartão. 5. Visita ligada à conta (referral).
- **Componentes envolvidos:** WorkerPublicProfileScreen, directRequestAuthStore
- **Serviços/backend envolvidos:** worker_public_card (anon), log_worker_card_visit, claim_worker_card_visit
- **Dados utilizados:** worker_card_visits, client_referrals
- **Resultado esperado:** Pedido reservado ao jardineiro do cartão
- **Possíveis pontos de falha:** Visitas sem limite (inflacionar números); origem inválida vira 'link'
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-033, FLOW-091

### FLOW-035

- **Nome:** Os teus jardineiros (anteriores)
- **Objetivo:** Escolher alguém de confiança
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Início / pedidos
- **Pré-condições:** Trabalhos concluídos
- **Passos:** Lista do último trabalho por jardineiro, sem os avaliados abaixo de 4.
- **Componentes envolvidos:** client home widgets
- **Serviços/backend envolvidos:** get_my_previous_workers, get_repeat_hire_for_job
- **Dados utilizados:** nenhum
- **Resultado esperado:** Lista certa; eliminados ficam de fora (0070)
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-033

### FLOW-036

- **Nome:** Contacto por WhatsApp
- **Objetivo:** Falar com a outra parte
- **Tipo de utilizador:** Cliente, jardineiro, ajudante
- **Ponto de entrada:** Botão WhatsApp nos detalhes
- **Pré-condições:** Trabalho confirmado (telefone visível)
- **Passos:** 1. Tocar. 2. Abre wa.me/<351…>.
- **Componentes envolvidos:** AppWhatsAppButton, phone_utils.dart
- **Serviços/backend envolvidos:** profiles.phone (RLS só com trabalho confirmado)
- **Dados utilizados:** telefone
- **Resultado esperado:** Abre a conversa certa
- **Possíveis pontos de falha:** WhatsApp não instalado; telefone mal formatado
- **Dependências externas:** WhatsApp
- **Fluxos relacionados:** FLOW-025

### FLOW-037

- **Nome:** Aprovar pedido de ajudantes (cliente)
- **Objetivo:** Autorizar a equipa
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Detalhe do trabalho
- **Pré-condições:** help_request pending_approval
- **Passos:** 1. Ver pedido de ajudantes. 2. Aprovar. 3. Ou aprovação automática às 24h.
- **Componentes envolvidos:** client_job_detail_screen
- **Serviços/backend envolvidos:** approve_help_request, process_help_request_deadlines
- **Dados utilizados:** help_requests
- **Resultado esperado:** Pedido open
- **Possíveis pontos de falha:** Dia do trabalho chegou (trigger recusa)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-050, FLOW-095

### FLOW-038

- **Nome:** Início e lista de pedidos do cliente
- **Objetivo:** Ver o que precisa de mim
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** /client/home, /client/jobs
- **Pré-condições:** Sessão de cliente
- **Passos:** Lista com próximo passo por pedido; abas.
- **Componentes envolvidos:** ClientHomeScreen, ClientJobsScreen, NextStepRow
- **Serviços/backend envolvidos:** SELECT job_requests (próprios)
- **Dados utilizados:** nenhum
- **Resultado esperado:** Lista certa e atualizada
- **Possíveis pontos de falha:** Lista desatualizada sem Realtime
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-027

### FLOW-039

- **Nome:** Dicas da época (preferência)
- **Objetivo:** Receber ou não dicas
- **Tipo de utilizador:** Cliente
- **Ponto de entrada:** Definições
- **Pré-condições:** nenhum
- **Passos:** Ligar/desligar 'Dicas da época'.
- **Componentes envolvidos:** Definições do cliente
- **Serviços/backend envolvidos:** get_my_notification_preferences, set_seasonal_tips, send_seasonal_campaigns
- **Dados utilizados:** notification_preferences
- **Resultado esperado:** Preferência respeitada pelo cron
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-097

### FLOW-040

- **Nome:** Descobrir pedidos no raio
- **Objetivo:** Encontrar trabalho
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/available-jobs
- **Pré-condições:** Perfil completo
- **Passos:** 1. Lista por distância. 2. Filtro de categorias.
- **Componentes envolvidos:** WorkerAvailableJobsScreen
- **Serviços/backend envolvidos:** get_jobs_in_radius (coordenadas vindas da app, raio limitado a 50)
- **Dados utilizados:** job_requests mascarados
- **Resultado esperado:** Só pedidos da zona dele
- **Possíveis pontos de falha:** Coordenadas da app não são verificadas; qualquer papel pode chamar
- **Dependências externas:** GPS (opcional)
- **Fluxos relacionados:** FLOW-041

### FLOW-041

- **Nome:** Detalhe da oportunidade (zona aproximada)
- **Objetivo:** Decidir se propõe
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/job/:id
- **Pré-condições:** Pedido aberto visível
- **Passos:** Mostra zona, coordenadas arredondadas, fotos, nome do cliente.
- **Componentes envolvidos:** WorkerJobDetailScreen/View
- **Serviços/backend envolvidos:** get_job_by_id, get_open_job_client_identity
- **Dados utilizados:** nenhum
- **Resultado esperado:** Morada exata escondida até ser aceite
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** OSM tiles
- **Fluxos relacionados:** FLOW-042

### FLOW-042

- **Nome:** Enviar proposta (hora ou valor total)
- **Objetivo:** Propor preço e data
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/job/:id/propose
- **Pré-condições:** Pedido open, plano com margem
- **Passos:** 1. Modo (hora/total). 2. Duração ou dias. 3. Data/hora ou a combinar. 4. Ajudantes e equipamento. 5. Validade. 6. Enviar.
- **Componentes envolvidos:** WorkerSubmitProposalScreen, ProposalRepository.createProposal
- **Serviços/backend envolvidos:** create_proposal, triggers de plano, data passada e pedido direto
- **Dados utilizados:** job_proposals
- **Resultado esperado:** Proposta pendente, cliente avisado
- **Possíveis pontos de falha:** Duplicada; preço ≤0; data passada; horas mínimas > máximas aceites
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-024, FLOW-057

### FLOW-043

- **Nome:** Retirar proposta
- **Objetivo:** Desistir antes de ser aceite
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** Detalhe da proposta
- **Pré-condições:** Proposta pendente
- **Passos:** 1. Retirar. 2. Cliente avisado.
- **Componentes envolvidos:** worker_my_job_detail_screen
- **Serviços/backend envolvidos:** withdraw_proposal (sem FOR UPDATE)
- **Dados utilizados:** job_proposals
- **Resultado esperado:** superseded
- **Possíveis pontos de falha:** Corrida com accept_proposal deixa trabalho confirmado com proposta retirada
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-025

### FLOW-044

- **Nome:** Recusar pedido direto ('Não posso desta vez')
- **Objetivo:** Libertar o cliente
- **Tipo de utilizador:** Jardineiro escolhido
- **Ponto de entrada:** /worker/job/:id
- **Pré-condições:** Pedido direto waiting
- **Passos:** 1. Recusar. 2. Abre a todos ou fica parado.
- **Componentes envolvidos:** worker_job_detail_screen
- **Serviços/backend envolvidos:** decline_direct_job_request
- **Dados utilizados:** job_requests.direct_*
- **Resultado esperado:** Cliente avisado
- **Possíveis pontos de falha:** Já tem proposta pendente (recusado)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-033

### FLOW-045

- **Nome:** Os meus trabalhos (Agenda · Propostas · Histórico)
- **Objetivo:** Ver propostas e trabalhos
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/jobs
- **Pré-condições:** nenhum
- **Passos:** Abas com cartões por estado; paginação.
- **Componentes envolvidos:** WorkerJobsScreen, worker_jobs_view
- **Serviços/backend envolvidos:** get_worker_job_board (0035)
- **Dados utilizados:** nenhum
- **Resultado esperado:** Cada trabalho na aba certa
- **Possíveis pontos de falha:** Trabalho do BUG-001 aparece no Histórico em vez de agendado
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-053

### FLOW-046

- **Nome:** Iniciar trabalho (fotos de antes)
- **Objetivo:** Começar e avisar o cliente
- **Tipo de utilizador:** Jardineiro responsável
- **Ponto de entrada:** /worker/my-job/:id → Iniciar
- **Pré-condições:** confirmed, a partir de 1h antes
- **Passos:** 1. Até 3 fotos. 2. Iniciar. 3. Cliente e ajudantes avisados.
- **Componentes envolvidos:** worker_my_job_detail_screen, job_start_flow
- **Serviços/backend envolvidos:** start_job (FOR UPDATE)
- **Dados utilizados:** started_at, before_photo_paths
- **Resultado esperado:** Em curso
- **Possíveis pontos de falha:** Cedo demais; caminhos de foto de outra pessoa; iniciar 2 vezes
- **Dependências externas:** Câmara, Storage
- **Fluxos relacionados:** FLOW-048

### FLOW-047

- **Nome:** Trabalho por dias / vários dias
- **Objetivo:** Acompanhar trabalhos longos
- **Tipo de utilizador:** Jardineiro e cliente
- **Ponto de entrada:** Detalhe do trabalho
- **Pré-condições:** Proposta em dias
- **Passos:** Iniciar, 'Dia 2 de 3', marcar concluído; aviso de atraso pelo último dia previsto.
- **Componentes envolvidos:** worker_my_job_detail_view, worker_todo
- **Serviços/backend envolvidos:** job_expected_end_date, get_job_work_days
- **Dados utilizados:** job_work_days
- **Resultado esperado:** Sem noites no tempo; aviso certo
- **Possíveis pontos de falha:** Cron cancelar a meio (corrigido 0069)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-059, FLOW-090

### FLOW-048

- **Nome:** Marcar como concluído (fotos de depois)
- **Objetivo:** Pedir a confirmação ao cliente
- **Tipo de utilizador:** Jardineiro responsável
- **Ponto de entrada:** Detalhe → Marcar como concluído
- **Pré-condições:** Iniciado
- **Passos:** 1. Até 3 fotos. 2. Marcar. 3. Cliente avisado; confirmação automática às 48h.
- **Componentes envolvidos:** worker_my_job_detail_screen
- **Serviços/backend envolvidos:** mark_job_done
- **Dados utilizados:** marked_done_at, after_photo_paths
- **Resultado esperado:** awaiting_confirmation
- **Possíveis pontos de falha:** Antes de iniciar; ajudante a marcar; 2 vezes
- **Dependências externas:** Câmara, Storage
- **Fluxos relacionados:** FLOW-028, FLOW-091

### FLOW-049

- **Nome:** Avaliar cliente e ajudantes
- **Objetivo:** Fechar o ciclo de confiança
- **Tipo de utilizador:** Jardineiro responsável e ajudante
- **Ponto de entrada:** Detalhe concluído
- **Pré-condições:** completed
- **Passos:** Responsável avalia cliente e ajudantes; ajudante avalia o responsável.
- **Componentes envolvidos:** rating_sheet, helper_actions
- **Serviços/backend envolvidos:** submit_principal_rating, submit_helper_rating
- **Dados utilizados:** ratings
- **Resultado esperado:** Uma avaliação por par
- **Possíveis pontos de falha:** Avaliar quem não participou
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-074

### FLOW-050

- **Nome:** Pedir ajudantes e gerir a equipa
- **Objetivo:** Montar equipa
- **Tipo de utilizador:** Jardineiro responsável
- **Ponto de entrada:** /worker/job/:id/help-requests
- **Pré-condições:** Proposta com >1 pessoa aceite
- **Passos:** 1. Lobby de candidatos. 2. Aceitar com taxa. 3. Vagas, fechar, retirar ajudante.
- **Componentes envolvidos:** WorkerHelpRequestsLobbyScreen
- **Serviços/backend envolvidos:** accept/reject_help_candidate, update_help_request_slots, cancel_help_request, remove_help_helper
- **Dados utilizados:** help_requests, help_acceptances
- **Resultado esperado:** Equipa certa, avisos
- **Possíveis pontos de falha:** Taxa ≤0; aceitar a si próprio; dia do trabalho
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-051, FLOW-095

### FLOW-051

- **Nome:** Candidatar-se como ajudante / desistir
- **Objetivo:** Ganhar trabalho extra
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/help-requests
- **Pré-condições:** Pedido de ajuda aberto no raio
- **Passos:** 1. Ver pagamento e horário. 2. Candidatar com mensagem. 3. Desistir até à véspera.
- **Componentes envolvidos:** WorkerHelpRequestsScreen, ApplyAsHelperScreen
- **Serviços/backend envolvidos:** apply_to_help_request, withdraw_help_acceptance, get_help_requests_in_radius
- **Dados utilizados:** help_acceptances
- **Resultado esperado:** Candidatura pendente
- **Possíveis pontos de falha:** Repetida; cliente a candidatar; o próprio responsável
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-050

### FLOW-052

- **Nome:** Trabalho visto pelo ajudante
- **Objetivo:** Saber onde e quando ir
- **Tipo de utilizador:** Ajudante aceite
- **Ponto de entrada:** /worker/help/:acceptanceId
- **Pré-condições:** Candidatura aceite
- **Passos:** Data, zona, valor, WhatsApp do responsável, estado.
- **Componentes envolvidos:** WorkerHelperJobScreen, helper_job_state
- **Serviços/backend envolvidos:** get_my_help_acceptances
- **Dados utilizados:** nenhum
- **Resultado esperado:** Info certa; telefone da cliente nunca
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-050

### FLOW-053

- **Nome:** Agenda (Hoje, Semana, Mês)
- **Objetivo:** Organizar o dia
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/jobs (aba Agenda)
- **Pré-condições:** nenhum
- **Passos:** Mostra trabalhos da app, propostas, de fora da app e indisponibilidades; avisa sobreposições.
- **Componentes envolvidos:** WorkerAgendaTab, agenda_*
- **Serviços/backend envolvidos:** get_worker_agenda (máx. 62 dias)
- **Dados utilizados:** nenhum
- **Resultado esperado:** Agenda certa
- **Possíveis pontos de falha:** Intervalo grande; a combinar
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-054

### FLOW-054

- **Nome:** Agenda: adicionar, editar, apagar e séries
- **Objetivo:** Registar trabalho de fora e folgas
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/agenda/new, /:id, /:id/edit
- **Pré-condições:** nenhum
- **Passos:** 1. Formulário. 2. Recorrência. 3. Só este dia / este e os seguintes. 4. Feito, cancelar, repor, apagar.
- **Componentes envolvidos:** AgendaEntryEditorScreen, AgendaEntryDetailScreen
- **Serviços/backend envolvidos:** worker_calendar_entries/exceptions (RLS do dono), split_calendar_series, free_calendar_day
- **Dados utilizados:** nenhum
- **Resultado esperado:** Só o dono vê e mexe
- **Possíveis pontos de falha:** Cliente a criar; outro jardineiro
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-053

### FLOW-055

- **Nome:** Cartão partilhável (QR, imagem, PDF, link)
- **Objetivo:** Divulgar o jardineiro
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/card
- **Pré-condições:** Perfil completo
- **Passos:** Gera QR e imagem; PDF no Pro; partilhar link.
- **Componentes envolvidos:** WorkerShareCardScreen
- **Serviços/backend envolvidos:** worker_public_card
- **Dados utilizados:** nenhum
- **Resultado esperado:** Link /w/:id funciona
- **Possíveis pontos de falha:** Domínio por configurar; PDF no Grátis
- **Dependências externas:** share_plus
- **Fluxos relacionados:** FLOW-034

### FLOW-056

- **Nome:** Painel de ganhos (Pro)
- **Objetivo:** Ver quanto ganhou
- **Tipo de utilizador:** Jardineiro Pro
- **Ponto de entrada:** /worker/earnings
- **Pré-condições:** Plano Pro
- **Passos:** Lista por mês e totais.
- **Componentes envolvidos:** WorkerEarningsScreen, worker_earnings.dart
- **Serviços/backend envolvidos:** get_my_earnings (0067, por aplicar)
- **Dados utilizados:** nenhum
- **Resultado esperado:** Recusado no Grátis
- **Possíveis pontos de falha:** RPC não existe na BD viva até aplicar 0067
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-057

### FLOW-057

- **Nome:** Plano e limite do Grátis
- **Objetivo:** Limitar 5 trabalhos/mês
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** Enviar proposta; linha 'Plano'
- **Pré-condições:** Plano grátis
- **Passos:** 6.ª proposta no mês recusada; Pro sem limite.
- **Componentes envolvidos:** WorkerProfileScreen
- **Serviços/backend envolvidos:** trg_enforce_free_plan_limit, get_my_plan
- **Dados utilizados:** worker_plans
- **Resultado esperado:** Recusa com mensagem clara
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-042, FLOW-082

### FLOW-058

- **Nome:** Cartão frota (demo, OCR)
- **Objetivo:** Demonstração para parceiros
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/fleet-card
- **Pré-condições:** nenhum
- **Passos:** 1. Fotografar cartão. 2. OCR local. 3. Confirmar dados. 4. Pedido pending; ativação manual por SQL.
- **Componentes envolvidos:** FleetCard*Screen, fleet_card_text_extractor
- **Serviços/backend envolvidos:** worker_fleet_cards (INSERT pending)
- **Dados utilizados:** nenhum
- **Resultado esperado:** Pedido pending; foto apagada
- **Possíveis pontos de falha:** OCR falha; criar já ativo (recusado)
- **Dependências externas:** Google ML Kit
- **Fluxos relacionados:** nenhum

### FLOW-059

- **Nome:** Lembretes de início e atraso (0072)
- **Objetivo:** Não esquecer o trabalho
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** Notificação
- **Pré-condições:** Hora marcada
- **Passos:** 1h antes e 30 min depois sem Iniciar; aviso de atraso.
- **Componentes envolvidos:** notification_handler
- **Serviços/backend envolvidos:** send_start_reminders (cron */5)
- **Dados utilizados:** job_requests.start_reminder_for
- **Resultado esperado:** Um aviso de cada
- **Possíveis pontos de falha:** Sem hora marcada (não envia)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-098

### FLOW-060

- **Nome:** Início do jardineiro (dashboard)
- **Objetivo:** Ver o dia
- **Tipo de utilizador:** Jardineiro
- **Ponto de entrada:** /worker/home
- **Pré-condições:** nenhum
- **Passos:** Pendentes, agendados, próximo trabalho, oportunidades, O que falta fazer.
- **Componentes envolvidos:** WorkerDashboardScreen, TodoRow
- **Serviços/backend envolvidos:** get_worker_job_board, get_jobs_in_radius
- **Dados utilizados:** nenhum
- **Resultado esperado:** Números certos
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-045

### FLOW-070

- **Nome:** Lista de notificações (ler, filtros, limpar e desfazer)
- **Objetivo:** Ver avisos
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** /client/alerts, /notifications
- **Pré-condições:** Sessão
- **Passos:** 1. Lista por secções. 2. Marcar lida. 3. Limpar tudo com Desfazer 6 s.
- **Componentes envolvidos:** NotificationsScreen, AppNotificationsView
- **Serviços/backend envolvidos:** SELECT/UPDATE notifications, clear/restore_my_notifications
- **Dados utilizados:** notifications
- **Resultado esperado:** Só as próprias
- **Possíveis pontos de falha:** Criar notificações (recusado); mudar o dono (recusado)
- **Dependências externas:** Realtime
- **Fluxos relacionados:** FLOW-071

### FLOW-071

- **Nome:** Abrir o destino ao tocar numa notificação
- **Objetivo:** Ir direto ao assunto
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Toque na notificação (lista, aviso no topo ou push)
- **Pré-condições:** nenhum
- **Passos:** notification_handler escolhe a rota por tipo (go ou push).
- **Componentes envolvidos:** notification_handler.dart
- **Serviços/backend envolvidos:** get_job_by_id, job_proposals
- **Dados utilizados:** nenhum
- **Resultado esperado:** Ecrã certo e voltar funciona
- **Possíveis pontos de falha:** Tipo novo sem rota; ajudante sem acesso à proposta (corrigido 0073)
- **Dependências externas:** FCM
- **Fluxos relacionados:** FLOW-075

### FLOW-072

- **Nome:** Aviso no topo com a app aberta
- **Objetivo:** Ver avisos sem sair do ecrã
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Notificação nova por Realtime
- **Pré-condições:** App aberta
- **Passos:** AppToast.notification com toque para abrir.
- **Componentes envolvidos:** app.dart, AppToast
- **Serviços/backend envolvidos:** Realtime notifications
- **Dados utilizados:** nenhum
- **Resultado esperado:** Aparece uma vez, 4 s
- **Possíveis pontos de falha:** Rebuilds repetidos
- **Dependências externas:** Supabase Realtime
- **Fluxos relacionados:** FLOW-071

### FLOW-073

- **Nome:** Push FCM
- **Objetivo:** Avisar com a app fechada
- **Tipo de utilizador:** Todos (Android/iOS)
- **Ponto de entrada:** Sistema operativo
- **Pré-condições:** Firebase configurado, token registado
- **Passos:** 1. Token registado. 2. Trigger notifications_send_push chama a Edge Function. 3. FCM entrega. 4. Tokens inválidos apagados.
- **Componentes envolvidos:** PushNotificationService
- **Serviços/backend envolvidos:** register_device_token, send-push (Edge Function), pg_net, Vault
- **Dados utilizados:** device_tokens
- **Resultado esperado:** Push chega e abre o destino
- **Possíveis pontos de falha:** Permissão negada; token antigo; Edge Function sem segredo
- **Dependências externas:** Firebase, APNs, pg_net
- **Fluxos relacionados:** FLOW-071

### FLOW-074

- **Nome:** As minhas avaliações (recebidas e dadas)
- **Objetivo:** Ver reputação
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** /worker/ratings, /client/ratings
- **Pré-condições:** nenhum
- **Passos:** Duas listas com nome, foto e serviço.
- **Componentes envolvidos:** MyRatingsRoute
- **Serviços/backend envolvidos:** get_my_ratings_received/given
- **Dados utilizados:** ratings
- **Resultado esperado:** Listas certas
- **Possíveis pontos de falha:** Avaliações legíveis por anónimos (decisão)
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-030

### FLOW-075

- **Nome:** Voltar, deep links e PopScope
- **Objetivo:** Nunca ficar preso
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Botão voltar, gesto, link
- **Pré-condições:** nenhum
- **Passos:** goBackOrToRoleHome: pop ou início do papel.
- **Componentes envolvidos:** app_back_navigation.dart, app_page_transitions.dart
- **Serviços/backend envolvidos:** nenhum
- **Dados utilizados:** nenhum
- **Resultado esperado:** Volta sempre para algum lado
- **Possíveis pontos de falha:** Abrir por notificação e voltar
- **Dependências externas:** Android back, web history
- **Fluxos relacionados:** FLOW-071

### FLOW-076

- **Nome:** Contacto e suporte, Sobre, links legais
- **Objetivo:** Ajuda e documentos
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Conta
- **Pré-condições:** nenhum
- **Passos:** Abrir mailto, Termos, Política.
- **Componentes envolvidos:** AppSupportSheet, AppAboutDialog, app_legal_links.dart
- **Serviços/backend envolvidos:** nenhum
- **Dados utilizados:** nenhum
- **Resultado esperado:** Abre a página certa
- **Possíveis pontos de falha:** Sem browser (SnackBar em vez de AppToast)
- **Dependências externas:** url_launcher
- **Fluxos relacionados:** nenhum

### FLOW-077

- **Nome:** Uploads para o Storage (avatar e fotos)
- **Objetivo:** Guardar imagens
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Editar perfil, criar pedido, iniciar/concluir
- **Pré-condições:** Sessão
- **Passos:** Comprimir (800 px, 60%) e enviar para a pasta do próprio.
- **Componentes envolvidos:** JobRepository, StorageUrls
- **Serviços/backend envolvidos:** storage.objects (RLS por pasta), buckets públicos
- **Dados utilizados:** Ficheiros
- **Resultado esperado:** Só na pasta do próprio
- **Possíveis pontos de falha:** Buckets públicos: quem tiver o URL vê
- **Dependências externas:** Supabase Storage
- **Fluxos relacionados:** FLOW-012, FLOW-020

### FLOW-078

- **Nome:** Morada e GPS (Photon, Nominatim, geocoder nativo)
- **Objetivo:** Escolher a localização
- **Tipo de utilizador:** Cliente e jardineiro
- **Ponto de entrada:** Criar pedido, setup
- **Pré-condições:** Rede, permissões
- **Passos:** Sugestões ao escrever; GPS → rua mais próxima.
- **Componentes envolvidos:** GeocodingService, AddressSuggestionsList
- **Serviços/backend envolvidos:** APIs externas
- **Dados utilizados:** nenhum
- **Resultado esperado:** Morada certa
- **Possíveis pontos de falha:** Serviço externo em baixo; limite de pedidos do Nominatim
- **Dependências externas:** Photon, Nominatim, OSM tiles, geocoder do SO
- **Fluxos relacionados:** FLOW-020, FLOW-007

### FLOW-079

- **Nome:** Erros, sem rede e timeouts
- **Objetivo:** Mensagens claras
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Qualquer ação
- **Pré-condições:** nenhum
- **Passos:** friendlyError, isNetworkError, AppSystemStateScreen.
- **Componentes envolvidos:** error_utils.dart
- **Serviços/backend envolvidos:** nenhum
- **Dados utilizados:** nenhum
- **Resultado esperado:** Mensagem em português e tentar de novo
- **Possíveis pontos de falha:** Erro técnico a aparecer
- **Dependências externas:** nenhum
- **Fluxos relacionados:** todos

### FLOW-080

- **Nome:** Entrar no painel /admin (login + 2.º fator)
- **Objetivo:** Gerir a plataforma
- **Tipo de utilizador:** Admin
- **Ponto de entrada:** /admin
- **Pré-condições:** Utilizador em admin_users com TOTP
- **Passos:** 1. Login. 2. Código TOTP (aal2). 3. Painel.
- **Componentes envolvidos:** AdminGateScreen
- **Serviços/backend envolvidos:** admin_whoami, assert_verified_admin
- **Dados utilizados:** admin_users
- **Resultado esperado:** Sem 2.º fator nada abre
- **Possíveis pontos de falha:** Admin sem TOTP; não-admin
- **Dependências externas:** Supabase MFA
- **Fluxos relacionados:** FLOW-081

### FLOW-081

- **Nome:** Visão geral, lista e ficha de jardineiros
- **Objetivo:** Acompanhar números
- **Tipo de utilizador:** Admin
- **Ponto de entrada:** /admin, /admin/workers/:id
- **Pré-condições:** aal2
- **Passos:** Números, lista com pesquisa, ficha.
- **Componentes envolvidos:** AdminHomeScreen, AdminWorkerDetailScreen
- **Serviços/backend envolvidos:** admin_overview, admin_list_workers, admin_get_worker
- **Dados utilizados:** nenhum
- **Resultado esperado:** Dados certos
- **Possíveis pontos de falha:** nenhum
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-082

### FLOW-082

- **Nome:** Atribuir plano a um jardineiro
- **Objetivo:** Dar Pro/Pro+
- **Tipo de utilizador:** Admin
- **Ponto de entrada:** Ficha do jardineiro
- **Pré-condições:** aal2
- **Passos:** Escolher plano, datas, notas; fica registado.
- **Componentes envolvidos:** AdminWorkerDetailScreen
- **Serviços/backend envolvidos:** admin_set_worker_plan, admin_actions
- **Dados utilizados:** worker_plans
- **Resultado esperado:** Plano ativo e registo da ação
- **Possíveis pontos de falha:** Plano inválido
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-057

### FLOW-090

- **Nome:** Expirar pedidos e trabalhos (auto_expire_jobs)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** auto_expire_jobs (0 */3 * * *)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-020, FLOW-047

### FLOW-091

- **Nome:** Confirmação automática (48h; 7 dias com relato)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** auto_confirm_completed_jobs (15 * * * *)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-028, FLOW-029

### FLOW-092

- **Nome:** Lembretes diários (send_job_reminders)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** send_job_reminders (30 7 * * *)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-047

### FLOW-093

- **Nome:** Fim da reserva do pedido direto
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** expire_direct_job_requests (*/5)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-033

### FLOW-094

- **Nome:** Pedidos sem propostas (6h e 24h)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** process_open_job_followups (15 * * * *)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-023

### FLOW-095

- **Nome:** Prazos dos pedidos de ajuda
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** close_help_requests_on_job_day, process_help_request_deadlines
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-050

### FLOW-096

- **Nome:** Limpeza (notificações, emails bloqueados)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** cleanup_old_notifications, cleanup_deleted_account_emails
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-070, FLOW-011

### FLOW-097

- **Nome:** Dicas da época
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** send_seasonal_campaigns (0 10 * * *)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-039

### FLOW-098

- **Nome:** Lembretes de início (0072)
- **Objetivo:** Processo automático sem intervenção
- **Tipo de utilizador:** Sistema (pg_cron)
- **Ponto de entrada:** pg_cron no Supabase
- **Pré-condições:** Extensão pg_cron ativa e job agendado
- **Passos:** O cron chama a função; a função muda estados e cria notificações.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** send_start_reminders (*/5)
- **Dados utilizados:** job_requests, notifications, …
- **Resultado esperado:** Corre sem erro e só sem utilizador
- **Possíveis pontos de falha:** Cron desligado; correr com sessão (recusado)
- **Dependências externas:** pg_cron
- **Fluxos relacionados:** FLOW-059

### FLOW-099

- **Nome:** Avisar jardineiros de pedidos e ajudas novos (triggers)
- **Objetivo:** Distribuir oportunidades
- **Tipo de utilizador:** Sistema
- **Ponto de entrada:** INSERT em job_requests/help_requests
- **Pré-condições:** nenhum
- **Passos:** Trigger escolhe jardineiros pelo raio gravado e serviços.
- **Componentes envolvidos:** nenhum
- **Serviços/backend envolvidos:** notify_workers_new_job, job_candidate_workers, notify_workers_new_help_request
- **Dados utilizados:** notifications
- **Resultado esperado:** Só jardineiros no raio
- **Possíveis pontos de falha:** Raio sem limite (5000 km) recebe tudo
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-007, FLOW-020

### FLOW-100

- **Nome:** Versão web (Netlify)
- **Objetivo:** Usar no browser
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** URL público
- **Pré-condições:** Deploy manual (workflow_dispatch)
- **Passos:** Build web com --dart-define; usePathUrlStrategy; sem push.
- **Componentes envolvidos:** deploy-web.yml, web/
- **Serviços/backend envolvidos:** Mesmo Supabase
- **Dados utilizados:** nenhum
- **Resultado esperado:** Mesmo comportamento sem push e sem OCR
- **Possíveis pontos de falha:** Deploy com código à frente da BD (0067+ por aplicar)
- **Dependências externas:** Netlify
- **Fluxos relacionados:** todos

### FLOW-101

- **Nome:** Ações repetidas e concorrentes (transversal)
- **Objetivo:** Não estragar dados com toques duplos
- **Tipo de utilizador:** Todos
- **Ponto de entrada:** Qualquer ação
- **Pré-condições:** nenhum
- **Passos:** Duas sessões a fazer a mesma ação ao mesmo tempo.
- **Componentes envolvidos:** Botões com isLoading
- **Serviços/backend envolvidos:** FOR UPDATE nas RPCs
- **Dados utilizados:** nenhum
- **Resultado esperado:** Uma ganha, a outra recebe erro claro
- **Possíveis pontos de falha:** withdraw_proposal e job_photos sem bloqueio
- **Dependências externas:** nenhum
- **Fluxos relacionados:** FLOW-025, FLOW-043, FLOW-020

