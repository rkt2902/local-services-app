# ProJardim na web (e no iPhone como app instalada)

> Passo a passo de toda a configuração (Netlify, Supabase, email, push, domínio):
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

## 2. Pôr online no Netlify (grátis)

O Netlify dá HTTPS, que é obrigatório para o GPS e para instalar no iPhone.
A app usa URLs sem `#` (por exemplo `/w/<id>`); o ficheiro `web/_redirects`
já faz o Netlify devolver `index.html` em qualquer caminho.

### Primeira vez (à mão, uns minutos)

1. Criar conta em netlify.com ("Sign up with GitHub").
2. No PC, em `servicesapp/`: `flutter build web --release` com as
   `--dart-define` do `.vscode/launch.json` (ver secção 1).
3. Abrir app.netlify.com/drop e arrastar a pasta `build/web`. Em segundos
   dá um endereço do tipo `https://nome-aleatorio.netlify.app`.
4. Site configuration > Change site name > `projardim` (fica
   `https://projardim.netlify.app`, se o nome estiver livre).
5. Abrir esse endereço no telemóvel.

### Automático a cada push para `main`

O workflow `.github/workflows/deploy-web.yml` compila e publica sozinho.
Configura-se uma vez:

1. Netlify: avatar > User settings > Applications > Personal access tokens >
   New access token. Copiar o token.
2. Netlify: no site > Site configuration > Site details > copiar o
   **Site ID**.
3. GitHub: repo > Settings > Secrets and variables > Actions > New
   repository secret, criar 4:
   - `NETLIFY_AUTH_TOKEN` (passo 1)
   - `NETLIFY_SITE_ID` (passo 2)
   - `SUPABASE_URL` e `SUPABASE_ANON_KEY` (os mesmos do `launch.json`)
4. A partir daí cada merge no `main` que mexa em `servicesapp/` publica a
   versão nova. Para publicar sem esperar: Actions > Deploy web > Run
   workflow. Se faltar algum secret o workflow para logo e diz qual.

Alternativas com config já incluída, se um dia for preciso: Firebase Hosting
(`firebase.json`), Vercel (`web/vercel.json`), Cloudflare Pages
(`web/_redirects`).

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

- **Site URL**: o endereço do Netlify, por exemplo `https://projardim.netlify.app`.
- **Redirect URLs**: adicionar `https://projardim.netlify.app/**` e, para
  testar no PC, `http://localhost:*/**`.

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
máxima (`AppBreakpoints.contentMaxWidth`, 640) e a partir de 840 de largura a
bottom nav dá lugar a uma navegação lateral (`AppAdaptiveShell`). Tudo é
aplicado num só sítio (router e shells), ecrãs novos não precisam de fazer
nada. Ver `core/widgets/app_content_width.dart`.
