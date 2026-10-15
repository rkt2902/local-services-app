# Notificações push (FCM)

Grátis: Firebase Cloud Messaging não tem custo, e a Edge Function cabe no
plano gratuito do Supabase.

## Como funciona

1. Todas as notificações da app já são linhas novas em `notifications`
   (criadas pelas funções SQL de negócio).
2. O trigger `notifications_send_push` (migration `0040`) chama a Edge
   Function `send-push` via `pg_net`, só se o destinatário tiver algum
   dispositivo registado.
3. A Edge Function lê os tokens em `device_tokens` e envia para o FCM
   (API HTTP v1). Tokens inválidos são apagados automaticamente.
4. Na app, `PushNotificationService` regista o token do dispositivo ao
   entrar e remove-o no logout. Tocar no push abre o mesmo ecrã que tocar
   na notificação dentro da app (`NotificationHandler`).

Com a app aberta o push não aparece no sistema (o badge in-app já atualiza
em tempo real). Sem os ficheiros do Firebase a app continua a funcionar,
só sem push.

## Passos de configuração (uma vez)

### 1. Projeto Firebase
1. https://console.firebase.google.com → Adicionar projeto (Analytics é
   opcional).
2. Adicionar app **Android** com o package `com.example.servicesapp`
   (ou o definitivo, se mudares o `applicationId`). Descarregar
   `google-services.json` para `android/app/google-services.json`.
3. Adicionar app **iOS** com o bundle id do Runner. Descarregar
   `GoogleService-Info.plist` e arrastá-lo no Xcode para `Runner/`
   (marcar "Copy items if needed" e o target Runner).

### 2. iOS (só se fores publicar em iPhone)
- Precisa de conta Apple Developer paga (99 €/ano) — é a única parte não
  gratuita, e é da Apple, não do Firebase.
- Xcode → Runner → Signing & Capabilities → **+ Push Notifications**.
- Apple Developer → Keys → criar chave APNs (.p8) → Firebase → Definições
  do projeto → Cloud Messaging → carregar a chave APNs.

### 3. Service account para enviar
Firebase → Definições do projeto → Contas de serviço → **Gerar nova chave
privada**. Fica um ficheiro JSON. Não o commitar.

### 4. Edge Function
Com a [Supabase CLI](https://supabase.com/docs/guides/cli), na pasta
`servicesapp/`:

```bash
supabase link --project-ref <PROJECT_REF>
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat caminho/para/service-account.json)"
supabase secrets set PUSH_WEBHOOK_SECRET=<SEGREDO_ALEATORIO>
supabase functions deploy send-push --no-verify-jwt
```

`<SEGREDO_ALEATORIO>`: qualquer string longa, por exemplo
`openssl rand -hex 32`.

### 5. Base de dados (SQL Editor)
1. Database → Extensions → ativar **pg_net**.
2. Guardar os segredos no Vault (o mesmo segredo do passo 4):
   ```sql
   select vault.create_secret(
     'https://<PROJECT_REF>.supabase.co/functions/v1/send-push',
     'push_function_url');
   select vault.create_secret('<SEGREDO_ALEATORIO>', 'push_webhook_secret');
   ```
3. Correr `supabase/migrations/0040_push_notifications.sql`.

### 6. Testar
1. `flutter run` num telemóvel real (Android: emulador com Google Play
   também serve), fazer login e aceitar a permissão de notificações.
2. Confirmar que apareceu uma linha em `device_tokens`.
3. Fechar a app e, no SQL Editor:
   ```sql
   insert into notifications (user_id, type, title, body)
   values ('<USER_ID>', 'job_no_response', 'Teste', 'Olá do ProJardim');
   ```
4. Se não chegar: Edge Functions → send-push → Logs, e
   `select * from net._http_response order by created desc limit 5;`.
