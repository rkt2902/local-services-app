// Edge Function `send-push` — envia uma linha de `notifications` como push
// FCM (HTTP v1) para todos os dispositivos do destinatário.
//
// Chamada pelo trigger `notifications_send_push` (migration 0041) via pg_net,
// com o header `x-webhook-secret`. Deploy SEM verificação de JWT:
//   supabase functions deploy send-push --no-verify-jwt
//
// Segredos necessários (supabase secrets set ...):
//   FCM_SERVICE_ACCOUNT  — JSON completo da service account do Firebase
//   PUSH_WEBHOOK_SECRET  — o mesmo valor guardado no Vault como
//                          `push_webhook_secret`
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem por defeito.

import { createClient } from "jsr:@supabase/supabase-js@2";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const serviceAccount: ServiceAccount = JSON.parse(
  Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}",
);
const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ── OAuth2 access token (service account → JWT RS256) ───────────────────

let cachedToken: { value: string; expiresAt: number } | null = null;

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth token error: ${await res.text()}`);
  const json = await res.json();
  cachedToken = { value: json.access_token, expiresAt: now + json.expires_in };
  return cachedToken.value;
}

// ── FCM send ────────────────────────────────────────────────────────────

interface NotificationRow {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
  related_id: string | null;
  related_type: string | null;
}

/** Devolve true se o token já não é válido e deve ser apagado. */
async function sendToToken(
  accessToken: string,
  token: string,
  n: NotificationRow,
): Promise<boolean> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: n.title, body: n.body },
          // Todos os valores de `data` têm de ser strings.
          data: {
            notification_id: n.id,
            type: n.type,
            related_id: n.related_id ?? "",
            related_type: n.related_type ?? "",
          },
          android: { priority: "high", notification: { sound: "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );
  if (res.ok) return false;

  const text = await res.text();
  console.error(`FCM error for token ${token.slice(0, 12)}…: ${res.status} ${text}`);
  // 404 UNREGISTERED = app desinstalada / token expirado.
  // 400 INVALID_ARGUMENT com token inválido também é para apagar.
  return res.status === 404 ||
    text.includes("UNREGISTERED") ||
    (res.status === 400 && text.includes("registration token"));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const { notification_id } = await req.json();
    if (!notification_id) return new Response("Missing notification_id", { status: 400 });

    const { data: notification, error } = await supabase
      .from("notifications")
      .select("id, user_id, type, title, body, related_id, related_type")
      .eq("id", notification_id)
      .maybeSingle<NotificationRow>();
    if (error) throw error;
    if (!notification) return new Response("Notification not found", { status: 404 });

    const { data: tokens, error: tokensError } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", notification.user_id);
    if (tokensError) throw tokensError;
    if (!tokens || tokens.length === 0) {
      return Response.json({ sent: 0 });
    }

    const accessToken = await getAccessToken();
    const results = await Promise.all(
      tokens.map((t) => sendToToken(accessToken, t.token, notification)),
    );

    const stale = tokens.filter((_, i) => results[i]).map((t) => t.token);
    if (stale.length > 0) {
      await supabase.from("device_tokens").delete().in("token", stale);
    }

    return Response.json({ sent: tokens.length - stale.length, removed: stale.length });
  } catch (e) {
    console.error(e);
    return new Response(String(e), { status: 500 });
  }
});
