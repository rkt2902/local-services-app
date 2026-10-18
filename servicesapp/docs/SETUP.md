# ProJardim: configuração que só tu podes fazer

Guia único, por ordem. Cada passo tem o que fazer, como confirmar que ficou bem e a frase
para dizeres ao Claude quando acabares. Marca as caixas à medida que avanças.

Estado de partida (17/10/2026): migrations até à 0046 aplicadas, 0047 e 0048 por aplicar (passos 0.1 e 0.2); código da versão web,
do push FCM e do domínio por `--dart-define` já está no `main`. Nada daqui mexe em código.

Ordem recomendada e porquê:

1. Netlify e secrets do GitHub (o site fica online, tudo o resto aponta para ele)
2. Supabase: Site URL e Redirect URLs
3. Email: SMTP Brevo e template de recuperação com o código
4. Firebase e push
5. Domínio real (quando o comprares; até lá o `netlify.app` serve)
6. Testes manuais que ficaram pendentes

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

**Diz ao Claude:** "0047 e 0048 aplicadas".

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
  - `SUPPORT_EMAIL`: o email que aparece em "Contacto & suporte". Sem ela fica
    `suporte@projardim.pt`. Só a cries quando esse email existir de verdade (passo 5).
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

Isto não muda nada visível hoje: a recuperação de senha e a confirmação de email são
por código, não por link. Fica certo para quando algum email tiver links.

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
- [ ] Conta > Contacto & suporte mostra o email novo.
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

## Não ligar ainda

### App links (abrir `https://<domínio>/w/...` diretamente na app instalada)

Precisa do domínio final e da impressão digital SHA-256 da chave com que assinas a app
Android (para o ficheiro `/.well-known/assetlinks.json`). Hoje o link abre no browser, o
que já funciona. Pede ao Claude depois do passo 5.
