# ProJardim na web (e no iPhone como app instalada)

> Passo a passo de toda a configuração (Cloudflare Pages, Supabase, email, push, domínio):
> `docs/SETUP.md`. Este ficheiro explica a versão web em si.

A mesma app Flutter corre no browser (Flutter web). É o caminho para quem tem
iPhone enquanto não há conta Apple Developer: abre-se o site no Safari e
instala-se no ecrã principal, como uma app (PWA).

## 1. Correr e compilar

Na pasta `servicesapp/`:

```bash
# testar no Chrome do PC
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# compilar para alojar (sai em build/web/)
flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Os valores são os mesmos do `.vscode/launch.json`. A anon key é pública por
natureza (vai sempre dentro da app), a segurança está na RLS.

## 2. Pôr online no Cloudflare Pages (grátis)

Desde 27/11 a web está no Cloudflare Pages e é servida em `https://projardim.pt`
(antes estava no Netlify). O DNS do domínio já estava na Cloudflare, por isso
o certificado HTTPS e os registos do domínio ficam no mesmo sítio, sem
intermediários. HTTPS é obrigatório para o GPS e para instalar no iPhone.

A app usa URLs sem `#` (por exemplo `/w/<id>`). O Cloudflare Pages devolve
`index.html` em qualquer caminho que não exista, porque o build não tem
`404.html`, por isso não precisa de `_redirects`. O `web/_headers` impede que
o `index.html` e o service worker fiquem em cache antigo depois de um deploy.

### Publicar (GitHub Actions, à mão)

O workflow `.github/workflows/deploy-web.yml` compila e publica. Só corre à
mão (Actions > Deploy web > Run workflow, branch `main`), para a web não
ficar à frente de migrations por aplicar. No fim confirma que
`projardim.pt` e `projardim.pt/privacidade` respondem 200 e deixa um aviso
se não.

Configura-se uma vez:

1. Cloudflare: My Profile > API Tokens > Create Token > modelo "Edit
   Cloudflare Workers" ou um token próprio com **Account > Cloudflare Pages >
   Edit**. Copiar o token.
2. Cloudflare: na página inicial da conta, copiar o **Account ID** (coluna
   da direita em qualquer domínio, ou na barra do endereço).
3. GitHub: repo > Settings > Secrets and variables > Actions > Secrets:
   - `CLOUDFLARE_API_TOKEN` (passo 1)
   - `CLOUDFLARE_ACCOUNT_ID` (passo 2)
   - `SUPABASE_URL` e `SUPABASE_ANON_KEY` (já existiam)
4. Correr o workflow uma vez. O projeto `projardim` é criado sozinho no
   Cloudflare Pages e fica em `https://projardim.pages.dev`.
5. Cloudflare > Workers & Pages > projardim > Custom domains > Set up a
   custom domain: `projardim.pt`, e depois `www.projardim.pt`. Como o DNS
   está na mesma conta, a Cloudflare troca os registos antigos do Netlify e
   emite o certificado em poucos minutos.

Variáveis opcionais (Settings > Secrets and variables > Actions >
Variables): `APP_PUBLIC_URL` (por omissão `https://projardim.pt`; se ainda
apontar para o Netlify, o workflow ignora-a e avisa), `CLOUDFLARE_PAGES_PROJECT`
(por omissão `projardim`), `SUPPORT_EMAIL`, `FACEBOOK_LOGIN_ENABLED`,
`GOOGLE_WEB_CLIENT_ID`.

Alternativas com config já incluída, se um dia for preciso: Firebase Hosting
(`firebase.json`), Vercel (`web/vercel.json`).

### Ver no telemóvel antes de publicar

Com o PC e o telemóvel na mesma rede Wi-Fi:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=...
```

e abrir `http://<IP do PC>:8080` no telemóvel (o IP vê-se com `ipconfig`
no Windows). Serve para ver o aspeto; sem HTTPS o GPS não funciona e não dá
para instalar.

## 3. O que configurar no Supabase

Dashboard > Authentication > URL Configuration:

- **Site URL**: `https://projardim.pt`.
- **Redirect URLs**: `https://projardim.pt/**`, `https://www.projardim.pt/**`
  e, para testar no PC, `http://localhost:*/**`.

A recuperação de senha usa código de 6 dígitos (não usa link), por isso
funciona sem mais nada. Estes URLs passam a contar quando a confirmação de
email for ligada. Não é preciso mexer em CORS: a API do Supabase aceita pedidos
de qualquer origem.

## 4. Instalar no iPhone

Safari > abrir o site > botão Partilhar > "Adicionar ao ecrã principal". Abre
em ecrã inteiro, com o ícone e o nome ProJardim. No Android (Chrome) aparece a
opção "Instalar app".

## 5. O que muda na web

| Funcionalidade | Na web |
|---|---|
| Fotos (pedido, avatar, conclusão) | Funciona. No iPhone o Safari oferece câmara ou fotos. A foto é redimensionada pelo browser (1600px, qualidade 70) em vez da compressão nativa |
| GPS | Funciona com HTTPS, depois de o utilizador autorizar no browser |
| Pesquisar morada | Usa a pesquisa do OpenStreetMap (Nominatim), limitada a Portugal, em vez do geocoder do telemóvel |
| Mapa, WhatsApp, partilhar cartão | Funciona |
| Link do cartão do jardineiro | Na web aponta para o próprio site (`<site>/w/<id>`), por isso funciona logo |
| Cartão frota | Sem leitura automática (o OCR só existe em Android/iOS); os dados escrevem-se à mão |
| Notificações push | Desligadas na web. As notificações dentro da app continuam a aparecer em tempo real |

## 6. Tablet e PC

Os designs são mobile. Em ecrãs largos o conteúdo fica centrado com largura
máxima (`AppBreakpoints.contentMaxWidth`, 720) e a partir de 840 de largura (com o
lado menor de pelo menos 480, para o telemóvel deitado não contar) a bottom nav dá lugar a uma navegação lateral (`AppAdaptiveShell`). Tudo é
aplicado num só sítio (router e shells), ecrãs novos não precisam de fazer
nada. Ver `core/widgets/app_content_width.dart`.
