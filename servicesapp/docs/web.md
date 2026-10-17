# ProJardim na web (e no iPhone como app instalada)

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

## 2. Onde alojar de graça

Todas estas opções dão HTTPS, que é obrigatório para o GPS e para instalar no
iPhone. A app usa URLs sem `#` (por exemplo `/w/<id>`), por isso o alojamento
tem de devolver `index.html` para qualquer caminho. Os ficheiros para isso já
estão no repo.

| Serviço | Como | Config já incluída |
|---|---|---|
| **Netlify** (recomendado, o mais simples) | app.netlify.com > Add new site > Deploy manually > arrastar a pasta `build/web` | `web/_redirects` (vai para `build/web` sozinho) |
| Firebase Hosting | `npm i -g firebase-tools`, `firebase login`, `firebase init hosting` (escolher o projeto, responder "não" a reescrever o index.html), `firebase deploy` | `firebase.json` em `servicesapp/` |
| Vercel | `npm i -g vercel`, `cd build/web`, `vercel --prod` | `web/vercel.json` |
| Cloudflare Pages | Upload direto da pasta `build/web` | `web/_redirects` (mesmo formato do Netlify) |
| GitHub Pages | Não recomendado: não faz o reencaminhamento para `index.html` (recarregar numa página interna dá 404) e obriga a `--base-href /nome-do-repo/` | nenhuma |

Depois de cada alteração: `flutter build web ...` outra vez e voltar a publicar
(no Netlify, arrastar a pasta nova para "Deploys").

## 3. O que configurar no Supabase

Dashboard > Authentication > URL Configuration:

- **Site URL**: o endereço final, por exemplo `https://projardim.netlify.app`.
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
