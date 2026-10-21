# ProJardim: configuração que só tu podes fazer

Guia único, por ordem. Cada passo tem o que fazer, como confirmar que ficou bem e a frase
para dizeres ao Claude quando acabares. Marca as caixas à medida que avanças.

Estado de partida (17/10/2026): migrations até à 0046 aplicadas, 0047, 0048 e 0049 por aplicar (passos 0.1 a 0.3); código da versão web,
do push FCM e do domínio por `--dart-define` já está no `main`. Nada daqui mexe em código.

Ordem recomendada e porquê:

1. Netlify e secrets do GitHub (o site fica online, tudo o resto aponta para ele)
2. Supabase: Site URL e Redirect URLs
3. Email: SMTP Brevo e template de recuperação com o código
4. Firebase e push
5. Domínio real (quando o comprares; até lá o `netlify.app` serve)
6. Testes manuais que ficaram pendentes
7. Login com Google e Facebook (depende do passo 2; pode ser feito logo a seguir)

Uma coisa que **não** é para fazer ainda, explicada no fim: os app links.

---

## 0. Antes de começar

- [ ] Ter à mão o `SUPABASE_URL` e a `SUPABASE_ANON_KEY` (os mesmos do
      `.vscode/launch.json`; também em Supabase > Project Settings > API).
- [ ] Ter o Flutter a correr no PC (`flutter doctor` sem erros em Android e Chrome).
- [ ] Supabase CLI instalada (só para o passo 4): `npm i -g supabase` ou
      [instruções](https://supabase.com/docs/guides/cli). **Corre sempre os comandos
      `supabase` de dentro de `servicesapp/`**, nunca da raiz, senão cria uma pasta
      `supabase/` duplicada.

### 0.1 Migration por aplicar: 0047

- [ ] Supabase > SQL Editor: colar o conteúdo de
      `supabase/migrations/0047_candidate_message.sql` e correr. Pode correr-se mais do
      que uma vez sem erro.
- [ ] Testar: num pedido de ajuda teu com candidatos, o candidato que escreveu uma
      mensagem ao candidatar-se tem um bloco "Mensagem" no cartão do lobby. Quem não
      escreveu nada aparece como antes.

### 0.2 Migration por aplicar: 0048 (depois da 0047)

- [ ] SQL Editor: colar `supabase/migrations/0048_worker_helper_flow_fixes.sql` e
      correr. Também pode correr-se mais do que uma vez.
- [ ] Testar com dois jardineiros (A responsável, B ajudante):
  - B candidata-se a um pedido de ajuda de A: A recebe "Novo candidato a ajudante" e,
    ao tocar, abre a equipa.
  - A recusa B; B pode voltar a candidatar-se se a vaga reabrir. B também consegue
    retirar uma candidatura pendente.
  - A aceita B: no cartão de B na equipa aparece "Falar por WhatsApp".
  - A pede ajudantes: o cliente recebe "Pedido de ajudantes" e não dá para pedir
    outra vez enquanto esse estiver à espera.
  - O cliente cancela um pedido com propostas pendentes: cada jardineiro recebe
    "Pedido cancelado". Na aba Trabalhos, "Histórico" mostra-o como "Cancelado".

### 0.3 Migration por aplicar: 0049 (depois da 0048)

- [ ] SQL Editor: colar `supabase/migrations/0049_pending_decisions.sql` e correr.
- [ ] Testar:
  - Conta > Eliminar conta com um trabalho em curso: recusa com a explicação. Sem
    trabalho em curso: sai da app e o login com essa conta deixa de funcionar.
  - Cliente edita um pedido aberto com propostas: os jardineiros recebem "Pedido
    alterado".
  - Jardineiro responsável, na equipa: alterar vagas, fechar o pedido de ajuda, retirar
    um ajudante (o ajudante é avisado).
  - Os avisos passam a dizer o serviço e a data, por exemplo "(Corte de relva, 21/10)".
  - Num trabalho com a data já passada, remarcar passa a funcionar.
  - No SQL Editor: `SELECT send_job_reminders(); SELECT auto_expire_jobs(); SELECT
    auto_confirm_completed_jobs();` correm sem erro.

**Diz ao Claude:** "0047, 0048 e 0049 aplicadas".

### 0.4 Migration por aplicar: 0051 (depois da 0049)

- [ ] SQL Editor: colar `supabase/migrations/0051_worker_showcase.sql` e correr. Pode
      correr-se mais do que uma vez. (A 0050, se existir, é de outra tarefa e não depende
      desta.)
- [ ] Testar:
  - Jardineiro: Editar perfil > Destaques e redes sociais. Adicionar 2 destaques, pôr
    `@nome` no Instagram e `www.site.pt` no site, guardar: os campos passam a links
    completos `https://`. "Ver como o cliente vê" abre o cartão com tudo.
  - Um link inválido (ex. `ola` no site, ou um link do Facebook no campo Instagram)
    mostra erro e não grava.
  - Cliente: nas propostas recebidas, tocar no jardineiro abre o perfil com "Sobre",
    "Em destaque", os botões das redes e as avaliações. Cada botão abre fora da app.

**Diz ao Claude:** "0051 aplicada".

### 0.5 Migration por aplicar: 0052 (depois da 0049 e da 0051)

- [ ] SQL Editor: colar `supabase/migrations/0052_job_start_flow.sql` e correr. Pode
      correr-se mais do que uma vez. As consultas de verificação estão no fim do ficheiro.
- [ ] Testar:
  - Jardineiro, trabalho marcado para hoje: "Iniciar trabalho" só fica ativo 1h antes da
    hora. Iniciar com 1 foto de antes: aparece o temporizador e o cliente recebe "O
    trabalho começou".
  - "Marcar como concluído" com fotos de depois: o cliente vê o tempo registado e as
    fotos de antes e depois, e o aviso diz que fica confirmado em 48 horas.
  - `SELECT auto_confirm_completed_jobs();` corre sem erro e
    `SELECT schedule FROM cron.job WHERE jobname = 'auto-confirm-completed-jobs';` dá
    `15 * * * *`.

**Diz ao Claude:** "0052 aplicada".

### 0.6 Migration por aplicar: 0053 (depois da 0048 e da 0052)

- [ ] SQL Editor: colar `supabase/migrations/0053_worker_jobs_board_cards.sql` e correr.
      Pode correr-se mais do que uma vez.
- [ ] Testar, como jardineiro, em Trabalhos:
  - Cada cartão tem o ícone do serviço e só a localidade ("Cascais").
  - Um trabalho iniciado aparece como "Em curso"; um marcado como concluído diz "Feito a
    dd/MM · confirma automaticamente em Nh".
  - No Histórico, os cartões ficam agrupados por mês e um cancelado diz "cancelado pelo
    cliente" ou "cancelaste".

**Diz ao Claude:** "0053 aplicada".

### 0.7 Migration por aplicar: 0054 (depois da 0053)

- [ ] SQL Editor: colar `supabase/migrations/0054_help_requests_job_day_and_alerts.sql` e
      correr. Pode correr-se mais do que uma vez. Cria o cron
      `close-help-requests-on-job-day` (de hora a hora).
- [ ] Se o push já estiver configurado (passo do FCM mais abaixo), voltar a fazer deploy da
      função para as notificações usarem o ícone e a cor da app:
      `supabase functions deploy send-push --no-verify-jwt` (de dentro de `servicesapp/`).
- [ ] Testar:
  - Jardineiro com o serviço do pedido, dentro do raio, recebe "Novo pedido perto de ti";
    um que só faz outros serviços não recebe.
  - Pedido de ajuda aprovado pelo cliente: os jardineiros da zona recebem "Pedido de ajuda
    perto de ti" e o toque abre a candidatura.
  - No dia do trabalho o pedido de ajuda desaparece da descoberta e o responsável já não vê
    "Preciso de ajudantes".
  - O cartão "Equipa" mostra a foto dos ajudantes aceites.

**Diz ao Claude:** "0054 aplicada".

### 0.8 Migration por aplicar: 0055 (depois da 0054)

- [ ] SQL Editor: colar `supabase/migrations/0055_team_flow_improvements.sql` e correr. Pode
      correr-se mais do que uma vez. Junta a coluna `help_requests.eve_reminder_sent_at` e cria
      o cron `process-help-request-deadlines` (de hora a hora).
- [ ] Testar:
  - O cliente vê no pedido agendado o cartão "Equipa" com o nome e a foto dos ajudantes.
  - No dia do trabalho o ajudante já não vê "Desistir"; o responsável retira-o e a vaga não
    volta a abrir.
  - Pedido de ajudantes sem resposta do cliente fica aprovado 24h depois.
  - Na véspera, depois das 18h, o responsável com vagas ou candidatos recebe "O pedido de
    ajudantes fecha hoje".
  - Ao iniciar o trabalho, os ajudantes recebem "O trabalho começou".

**Diz ao Claude:** "0055 aplicada".

---

## 1. Netlify e deploy automático

Detalhe extra em `docs/web.md`, secção 2.

### 1.1 Primeiro deploy (à mão)

- [ ] Criar conta em netlify.com com "Sign up with GitHub".
- [ ] No PC, em `servicesapp/`:
      ```bash
      flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
      ```
- [ ] Abrir app.netlify.com/drop e arrastar a pasta `build/web`.
- [ ] Site configuration > Change site name > `projardim` (fica
      `https://projardim.netlify.app`; se estiver ocupado, escolhe outro e usa esse
      endereço em todo o resto deste guia).

### 1.2 Secrets e variáveis no GitHub

- [ ] Netlify: avatar > User settings > Applications > Personal access tokens > New
      access token. Copiar.
- [ ] Netlify: no site > Site configuration > Site details > copiar o **Site ID**.
- [ ] GitHub: repo > Settings > Secrets and variables > Actions > **Secrets** > New
      repository secret, criar os 4:
  - [ ] `NETLIFY_AUTH_TOKEN`
  - [ ] `NETLIFY_SITE_ID`
  - [ ] `SUPABASE_URL`
  - [ ] `SUPABASE_ANON_KEY`
- [ ] Opcional, no mesmo sítio mas no separador **Variables** (não são secretas):
  - `SUPPORT_EMAIL`: o email que aparece em "Contacto e suporte". Sem ela fica
    `projardim26@gmail.com`. Só a mudes quando houver um email no domínio (passo 5).
  - Os Termos e a Política de Privacidade abrem as versões publicadas no Google Docs.
    Quando houver site, mudam com `--dart-define=TERMS_URL=...` e
    `--dart-define=PRIVACY_POLICY_URL=...` (ou o valor por omissão em
    `core/config/app_links.dart`).
  - `APP_PUBLIC_URL`: deixa vazia por agora. Na web a app já usa o próprio endereço.
    Só se define no passo 5.

### Testar

- [ ] GitHub > Actions > Deploy web > Run workflow. Fica verde em poucos minutos. Se
      faltar um secret, o primeiro passo falha e diz qual.
- [ ] Abrir `https://projardim.netlify.app` no telemóvel, fazer login com uma conta de
      teste.
- [ ] Recarregar a página dentro de um ecrã interno (por exemplo um pedido). Tem de voltar
      ao mesmo ecrã, não dar 404.
- [ ] iPhone: Safari > Partilhar > Adicionar ao ecrã principal. Abre em ecrã inteiro.
- [ ] No jardineiro: Conta > cartão partilhável. O link tem de começar por
      `https://projardim.netlify.app/w/` e abrir o cartão numa janela anónima.

**Diz ao Claude:** "Netlify feito, o site está em `<endereço>` e o deploy automático
ficou verde."

---

## 2. Supabase: URLs de autenticação

Supabase > Authentication > URL Configuration.

- [ ] **Site URL**: `https://projardim.netlify.app`
- [ ] **Redirect URLs**, adicionar:
  - `https://projardim.netlify.app/**`
  - `http://localhost:*/**` (para testar no PC com `flutter run -d chrome`)

A recuperação de senha e a confirmação de email são por código, não por link, mas o
login com Google e Facebook (passo 7) volta para estes endereços.

**Diz ao Claude:** "URLs do Supabase configurados."

---

## 3. Email: SMTP próprio (Brevo) e recuperação de senha

Sem SMTP próprio o Supabase só envia uns poucos emails por hora e só para membros da
equipa do projeto. Para utilizadores reais é obrigatório.

### 3.1 Brevo

- [ ] Criar conta grátis em brevo.com (300 emails por dia no plano grátis).
- [ ] Senders, Domains & Dedicated IPs > Senders > adicionar o remetente. Até haver
      domínio próprio, usa o teu Gmail como remetente (vai para spam mais vezes; melhora
      no passo 5 com o domínio autenticado).
- [ ] SMTP & API > SMTP > anotar **servidor** (`smtp-relay.brevo.com`), **porta** (587),
      **login** e gerar uma **SMTP key** (é a password).

### 3.2 Supabase

- [ ] Authentication > Emails > SMTP Settings > Enable Custom SMTP:
  - Sender email: o remetente do 3.1
  - Sender name: `ProJardim`
  - Host `smtp-relay.brevo.com`, porta `587`, username = login Brevo, password = SMTP key
- [ ] Authentication > Rate Limits: confirmar o limite de emails por hora (com SMTP
      próprio começa em 30 por hora; chega para testes, sobe quando houver utilizadores).
- [ ] Authentication > Providers > Email: confirmar que **Email OTP Length** é **6**
      (a app tem 6 caixas para o código).
- [ ] Authentication > Emails > Templates > **Reset Password**. A app usa o código de 6
      dígitos, não o link. Assunto e corpo:

      Assunto: `O teu código ProJardim`

      ```html
      <h2>Recuperar a palavra-passe</h2>
      <p>Usa este código na app ProJardim para escolher uma palavra-passe nova:</p>
      <p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>
      <p>O código expira dentro de 1 hora. Se não pediste isto, ignora este email.</p>
      ```

### Testar

Testa no site do Netlify (build de release), porque em debug a app aceita qualquer
código e o teste não prova nada.

- [ ] Login > "Esqueci-me da palavra-passe" > email de uma conta de teste.
- [ ] Chega um email do teu remetente com 6 dígitos (ver também o spam).
- [ ] Código certo deixa escolher password nova; login com a nova funciona.
- [ ] Código errado mostra erro, não avança.
- [ ] Em Brevo > Transactional > Logs aparece o envio.

**Diz ao Claude:** "SMTP Brevo ligado e o reset de senha por código funciona em release."

### 3.3 Confirmação de email por código

A app já trata isto: com a opção ligada, o registo pede o código de 6 dígitos que chega
por email antes de escolher o papel; quem tentar entrar sem ter confirmado recebe um
código novo e vai para o mesmo ecrã. Com a opção desligada tudo funciona como hoje.
Só liga depois de o 3.2 estar a funcionar (sem SMTP os emails não chegam).

- [ ] Authentication > Emails > Templates > **Confirm signup**:

      Assunto: `Confirma o teu email no ProJardim`

      ```html
      <h2>Bem-vindo ao ProJardim</h2>
      <p>Usa este código na app para confirmar o teu email:</p>
      <p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>
      <p>Se não criaste uma conta, ignora este email.</p>
      ```
- [ ] Authentication > Providers > Email > ligar **Confirm email** e guardar.

Os utilizadores que já existem não são afetados (a migration 0036 marcou-os todos como
confirmados).

### Testar (no site do Netlify)

- [ ] Registar uma conta nova com um email teu. A app mostra "Confirme o seu email" e
      chega um email com 6 dígitos.
- [ ] Código errado mostra erro; código certo leva a "Escolher papel" e depois ao início.
- [ ] Registar outra conta, fechar a app antes de pôr o código, voltar e fazer login com
      essa conta. Vai para o ecrã do código e chega um código novo.
- [ ] "Reenviar código" só fica ativo ao fim de 60 segundos e manda um email novo.
- [ ] Entrar com uma conta antiga continua igual.

**Diz ao Claude:** "Confirmação de email ligada, o registo com código funciona."

---

## 4. Firebase e notificações push

O código está feito (ver `docs/push_notifications.md` para como funciona). A migration
0041 já está aplicada, por isso o `pg_net` já está ativo. Falta: projeto Firebase, ficheiro
da app Android, deploy da Edge Function e 2 segredos no Vault.

Só Android. iOS precisa de Mac e de conta Apple Developer paga; quem tem iPhone usa a web,
onde o push está desligado (as notificações dentro da app continuam em tempo real).

### 4.1 Projeto Firebase

- [ ] console.firebase.google.com > Adicionar projeto `ProJardim` (Analytics pode ficar
      desligado).
- [ ] Adicionar app **Android**, package `pt.projardim.app`.
- [ ] Descarregar `google-services.json` para `servicesapp/android/app/google-services.json`.
      O ficheiro está no `.gitignore`, não vai para o GitHub.

### 4.2 Service account

- [ ] Firebase > Definições do projeto > Contas de serviço > **Gerar nova chave privada**.
- [ ] Guardar o JSON fora do repositório (por exemplo `Documentos/projardim-secrets/`).
      Nunca o commitar.

### 4.3 Edge Function

No terminal, dentro de `servicesapp/`:

```bash
supabase login
supabase link --project-ref twpflvcoyeiysnychkom
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat CAMINHO/para/a-chave.json)"
supabase secrets set PUSH_WEBHOOK_SECRET=UM_SEGREDO_LONGO
supabase functions deploy send-push --no-verify-jwt
```

- [ ] `UM_SEGREDO_LONGO`: qualquer texto aleatório comprido. No Git Bash:
      `openssl rand -hex 32`. Guarda-o, vais usá-lo no 4.4.
- [ ] No Windows (PowerShell) o `$(cat ...)` não funciona. Usa o Git Bash, ou cola o
      conteúdo do JSON em Supabase > Edge Functions > Secrets > `FCM_SERVICE_ACCOUNT`.
- [ ] Supabase > Edge Functions mostra `send-push` como deployed.

### 4.4 Segredos no Vault (SQL Editor)

```sql
select vault.create_secret(
  'https://twpflvcoyeiysnychkom.supabase.co/functions/v1/send-push',
  'push_function_url');
select vault.create_secret('UM_SEGREDO_LONGO', 'push_webhook_secret');
```

- [ ] O segundo valor é exatamente o mesmo do 4.3.
- [ ] Se der erro de nome já existente, já tinhas criado antes; atualiza com
      `select vault.update_secret((select id from vault.secrets where name = 'push_webhook_secret'), 'UM_SEGREDO_LONGO');`
      (igual para `push_function_url`).

### Testar

- [ ] `flutter run` num telemóvel Android real (ou emulador com Google Play), login,
      aceitar a permissão de notificações.
- [ ] SQL Editor: `select user_id, platform, created_at from device_tokens;` mostra uma
      linha tua.
- [ ] Fechar a app (não só minimizar) e correr, com o teu id:
      ```sql
      insert into notifications (user_id, type, title, body)
      values ('<O_TEU_USER_ID>', 'job_reminder', 'Teste', 'Olá do ProJardim');
      ```
- [ ] O push chega. Tocar abre a app no ecrã certo.
- [ ] Teste real: com 2 contas, criar um pedido perto do jardineiro com a app dele
      fechada. Chega "novo pedido".
- [ ] Se não chegar: Supabase > Edge Functions > send-push > Logs, e
      `select * from net._http_response order by created desc limit 5;`

**Diz ao Claude:** "Push configurado. O teste por SQL chegou: sim/não. Logs: ..."

---

## 5. Domínio real (quando decidires comprar)

Até aqui tudo funciona com `projardim.netlify.app`. Faz isto só quando tiveres o domínio.

### 5.1 Comprar e ligar ao Netlify

- [ ] Comprar o domínio (`.pt` num registrar como PTisp, Amen ou Dominios.pt).
- [ ] Netlify > Domain management > Add a domain > seguir as instruções de DNS (mais
      simples: usar os nameservers do Netlify). O HTTPS ativa-se sozinho.

### 5.2 Apontar a app para o domínio

- [ ] Supabase > Authentication > URL Configuration: **Site URL** passa a
      `https://<domínio>` e adicionar `https://<domínio>/**` às Redirect URLs (deixa a do
      netlify.app também).
- [ ] GitHub > Settings > Secrets and variables > Actions > Variables: criar
      `APP_PUBLIC_URL` = `https://<domínio>` (sem `/` no fim).
- [ ] No `.vscode/launch.json`, acrescentar aos `args` das configurações Android:
      `"--dart-define=APP_PUBLIC_URL=https://<domínio>"`. Assim o QR do cartão do
      jardineiro nas apps Android aponta para o site real (hoje aponta para o
      placeholder `projardim.pt`).
- [ ] Correr Actions > Deploy web > Run workflow.

### 5.3 Email com o domínio

- [ ] Criar a caixa de suporte (por exemplo Zoho Mail grátis, ou reencaminhamento grátis
      com ImprovMX para o teu Gmail).
- [ ] Brevo > Senders, Domains > Domains > adicionar o domínio e pôr no DNS os registos
      que o Brevo pede (DKIM, SPF, DMARC). Depois trocar o remetente no Supabase (3.2)
      para `nao-responder@<domínio>`.
- [ ] GitHub Variables: `SUPPORT_EMAIL` = `suporte@<domínio>`; no `launch.json`,
      `"--dart-define=SUPPORT_EMAIL=suporte@<domínio>"`.

### Testar

- [ ] `https://<domínio>` abre a app com cadeado.
- [ ] Cartão do jardineiro (web e Android): o link começa por `https://<domínio>/w/` e
      abre numa janela anónima.
- [ ] Conta > Contacto e suporte mostra o email novo.
- [ ] Reset de senha: o email chega do domínio novo e não vai para spam.

**Diz ao Claude:** "Domínio `<domínio>` ligado ao Netlify, variáveis criadas. Agora
quero os app links." (é o próximo passo de código, ver abaixo).

### Fotos de perfil (avatar_url)

Já não precisa de nada. A app só mostra fotos que venham do Storage do próprio projeto
Supabase (`core/config/storage_urls.dart`), com base no `SUPABASE_URL`. Se um dia o
projeto mudar de URL, basta o `SUPABASE_URL` novo.

---

## 6. Testes manuais pendentes

Coisas que ficaram para testar num telemóvel real (o ambiente do Claude não tem Android).

- [ ] Android: mudar a foto de perfil (cliente e jardineiro). Aparece logo e depois de
      reabrir a app.
- [ ] Android: criar pedido com 2 fotos. O jardineiro vê as 2.
- [ ] Android: rodar o ecrã a meio de criar um pedido e a meio de editar o perfil. Nada
      se perde.
- [ ] Concluir no dia com foto (0046): antes do dia o botão não deixa; no dia deixa, com
      foto opcional; o cliente vê a foto.
- [ ] Lembretes (0046): no dia de um trabalho confirmado chega `job_reminder` de manhã.
- [ ] Pedido aberto com data fixa passada desaparece das oportunidades.
- [ ] Erros: password errada, email já registado, modo avião em vários ecrãs. Mensagens
      em português, sem textos técnicos.
- [ ] Faixa amarela e preta de overflow em alguma aba principal (Início, Pedidos,
      Trabalhos, Conta) num telemóvel pequeno? Se vires, screenshot e qual ecrã. Não
      consegui reproduzir o overflow de 3px sem dispositivo.

**Diz ao Claude:** a lista do que falhou, com screenshots.

---

## 7. Login com Google e Facebook

O código já está feito: botões "Continuar com Google" e "Continuar com Facebook" no
login e no registo, na web e nas apps. Quem entra pela primeira vez escolhe o papel e
escreve só o telemóvel (o nome já vem preenchido da conta e a foto é copiada para o
Storage). Enquanto um provider não estiver ligado no Supabase, o botão dele dá erro.
Nada disto precisa de migration.

Vais precisar do URL de callback do Supabase, que é sempre
`https://twpflvcoyeiysnychkom.supabase.co/auth/v1/callback` (também aparece em
Supabase > Authentication > Sign In / Providers, dentro do Google ou do Facebook, em
"Callback URL").

### 7.1 Supabase: Redirect URL das apps

- [ ] Supabase > Authentication > URL Configuration > Redirect URLs, adicionar
      `pt.projardim.app://login-callback` (é por aqui que o Android e o iPhone voltam à
      app). As da web já ficaram no passo 2.

### 7.2 Google

1. [ ] [console.cloud.google.com](https://console.cloud.google.com) > criar um projeto
       "ProJardim" (ou usar o do Firebase, se já o criaste no passo 4).
2. [ ] Google Auth Platform (ou APIs & Services > OAuth consent screen) > Get started:
       nome da app "ProJardim", email de suporte o teu, público **External**, contacto o
       teu email.
3. [ ] Em **Branding**, Authorized domains: `supabase.co` e `netlify.app` (e o domínio
       real quando o tiveres). Não carregues logótipo por agora: com logótipo o Google
       pede verificação manual, que demora semanas.
4. [ ] Em **Data access**, deixa só os scopes por omissão (`email`, `profile`,
       `openid`). São os únicos que a app usa e não pedem verificação.
5. [ ] Em **Clients** > Create client > tipo **Web application**, nome "Supabase".
       Authorized redirect URIs: o URL de callback do Supabase (acima). Guarda o
       **Client ID** e o **Client secret**. Não é preciso criar clientes Android nem iOS:
       a app usa a página de login do Google no browser, o que serve para tudo.
6. [ ] Em **Audience**, carrega em **Publish app** (passa de Testing a In production).
       Sem isto só entram as contas que adicionares como test users.
7. [ ] Supabase > Authentication > Sign In / Providers > **Google**: ligar, colar o
       Client ID e o Client secret, guardar.

### 7.3 Facebook

1. [ ] [developers.facebook.com](https://developers.facebook.com) > My Apps > Create
       App. Caso de uso **Authenticate and request data from users with Facebook
       Login**, tipo **Consumer** se perguntar. Nome "ProJardim".
2. [ ] Use cases > Facebook Login > Customize > **Permissions**: confirmar que `email`
       e `public_profile` estão adicionadas (não precisam de revisão da Meta).
3. [ ] Use cases > Facebook Login > **Settings**: em Valid OAuth Redirect URIs pôr o URL
       de callback do Supabase. Guardar.
4. [ ] App settings > Basic: guardar o **App ID** e o **App Secret**. Preencher também
       Privacy Policy URL, User data deletion (pode ser um URL com instruções, por
       exemplo uma página que diga para usar Conta > Eliminar conta ou escrever para o
       suporte) e categoria. Sem isto a Meta não deixa pôr a app em Live.
5. [ ] Pôr a app em **Live** (interruptor App Mode no topo, ou Publish). Enquanto
       estiver em Development só entram as contas com papel na app (tu e os testers
       que adicionares em App roles).
6. [ ] Supabase > Authentication > Sign In / Providers > **Facebook**: ligar, App ID
       no campo Client ID, App Secret no Client Secret, guardar.

Nota: para pôr a app em Live a Meta pede uma página de Política de Privacidade real e a
verificação de negócio, que não aceita `netlify.app` e precisa de empresa ou atividade
registada com domínio próprio. Até lá deixa o Facebook em Development (só tu e os
testers em App roles) e liga só o Google.

### 7.4 Mostrar o botão do Facebook

O botão "Continuar com Facebook" está **escondido por omissão**, porque com a app da Meta
em Development quem não é tester recebe um erro. Quando a app estiver em Live:

- [ ] GitHub > Settings > Secrets and variables > Actions > **Variables** > New
      repository variable: `FACEBOOK_LOGIN_ENABLED` = `true`. Correr Actions > Deploy
      web > Run workflow.
- [ ] Nas apps (e para testares como tester antes do Live), juntar
      `--dart-define=FACEBOOK_LOGIN_ENABLED=true` aos `args` do `.vscode/launch.json`.

### Testar

- [ ] Web (site do Netlify): Continuar com Google, conta que nunca usaste na app. Vai
      para "Como quer usar a ProJardim?", com o nome já escrito e o campo do
      telemóvel vazio. Escolher papel, escrever o telemóvel, Continuar. Entra no início
      do papel e a foto da conta Google aparece no perfil.
- [ ] Repetir com o Facebook (na web e no Android), com o botão ligado (7.4).
- [ ] Android: Continuar com Google abre o browser e, depois de escolher a conta, volta
      sozinho à app já com sessão.
- [ ] Sair e voltar a entrar com o mesmo Google: vai direto para o início, sem pedir o
      papel outra vez.
- [ ] Conta antiga criada por email e password: entrar com o Google do mesmo email. Deve
      entrar na mesma conta (o Supabase junta as duas pelo email).
- [ ] Na web, se a foto não aparecer (o browser pode bloquear o download da foto do
      Facebook), a conta fica criada na mesma, sem foto. Diz-me se acontecer.
- [ ] Cancelar a meio (fechar a página do Google): a app fica no login, sem erro.

**Diz ao Claude:** "Google ligado (e Facebook: sim/não). Testei na web e no Android:
o que falhou foi ..."

---

## Não ligar ainda

### App links (abrir `https://<domínio>/w/...` diretamente na app instalada)

Precisa do domínio final e da impressão digital SHA-256 da chave com que assinas a app
Android (para o ficheiro `/.well-known/assetlinks.json`). Hoje o link abre no browser, o
que já funciona. Pede ao Claude depois do passo 5.
