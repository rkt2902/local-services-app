// Edge Function `send-invite` — envia um convite por email (painel de
// admin, /admin/convites, migration 0085) pela API transacional do Brevo.
//
// A app (só o admin, com segundo fator) manda o email já montado a partir
// dos modelos de `admin_invite_templates.dart`, com o marcador
// {{optout_url}} no sítio do link "não quero receber". Esta função:
//   1. regista o envio com o JWT do admin (`admin_invite_create`, que
//      verifica admin + segundo fator, o email, quem pediu para não
//      receber, repetidos e o limite diário) e recebe o token;
//   2. troca o marcador pelo link real e envia pelo Brevo;
//   3. marca o resultado (`admin_invite_finish`).
// A chave do Brevo nunca vai para a app.
//
// Deploy COM verificação de JWT (o normal):
//   supabase functions deploy send-invite
//
// Segredos (supabase secrets set ...):
//   BREVO_API_KEY       — obrigatório. Brevo > SMTP & API > API Keys.
//   INVITE_FROM_EMAIL   — opcional, por omissão suporte@projardim.pt
//                         (tem de estar no domínio autenticado no Brevo).
//   INVITE_FROM_NAME    — opcional, por omissão ProJardim.
//   INVITE_REPLY_TO     — opcional, por omissão igual ao INVITE_FROM_EMAIL.
//   INVITE_OPTOUT_URL   — opcional, por omissão
//                         https://projardim.pt/sem-convites
// SUPABASE_URL e SUPABASE_ANON_KEY já existem por defeito.

import { createClient } from "jsr:@supabase/supabase-js@2";

const OPTOUT_PLACEHOLDER = "{{optout_url}}";
const TEMPLATES = new Set([
  "founder_invite",
  "founder_invite_plain",
  "founder_reminder",
]);

const brevoKey = Deno.env.get("BREVO_API_KEY") ?? "";
const fromEmail = Deno.env.get("INVITE_FROM_EMAIL") ?? "suporte@projardim.pt";
const fromName = Deno.env.get("INVITE_FROM_NAME") ?? "ProJardim";
const replyTo = Deno.env.get("INVITE_REPLY_TO") ?? fromEmail;
const optoutBase = (Deno.env.get("INVITE_OPTOUT_URL") ??
  "https://projardim.pt/sem-convites").replace(/\/+$/, "");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface InviteRequest {
  template?: string;
  recipientName?: string;
  recipientEmail?: string;
  subject?: string;
  html?: string;
  text?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Método não suportado." });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { error: "Sem sessão." });
  }

  let body: InviteRequest;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Pedido inválido." });
  }
  const template = body.template ?? "";
  const name = (body.recipientName ?? "").trim();
  const email = (body.recipientEmail ?? "").trim().toLowerCase();
  const subject = (body.subject ?? "").trim();
  const html = body.html ?? "";
  const text = body.text ?? "";

  if (!TEMPLATES.has(template)) return json(400, { error: "Modelo de email inválido." });
  if (!html.includes(OPTOUT_PLACEHOLDER) || !text.includes(OPTOUT_PLACEHOLDER)) {
    // Todos os emails têm de levar o link para deixar de receber.
    return json(400, { error: "O email tem de incluir o link para deixar de receber." });
  }
  if (html.length > 60000 || text.length > 6000) {
    return json(400, { error: "O email é demasiado longo." });
  }
  if (!brevoKey) {
    // Antes de registar: sem chave não se gasta o envio do dia.
    return json(503, {
      error: "O envio de emails ainda não está configurado (falta o BREVO_API_KEY).",
    });
  }

  // Cliente com o JWT do admin: auth.uid() e o segundo fator vêm dele.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: created, error: createError } = await supabase.rpc(
    "admin_invite_create",
    {
      p_template: template,
      p_recipient_name: name,
      p_recipient_email: email,
      p_subject: subject,
      p_body_text: text.replaceAll(OPTOUT_PLACEHOLDER, optoutBase),
    },
  );
  if (createError) {
    const status = createError.code === "42501" ? 403 : 400;
    return json(status, { error: createError.message });
  }
  const row = Array.isArray(created) ? created[0] : created;
  if (!row?.id || !row?.optout_token) {
    return json(500, { error: "Não foi possível registar o envio." });
  }

  const optoutUrl = `${optoutBase}?t=${row.optout_token}`;
  let ok = false;
  let messageId: string | null = null;
  let errorText: string | null = null;
  try {
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "api-key": brevoKey,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        sender: { name: fromName, email: fromEmail },
        to: [{ email, name }],
        replyTo: { email: replyTo, name: fromName },
        subject,
        htmlContent: html.replaceAll(OPTOUT_PLACEHOLDER, optoutUrl),
        textContent: text.replaceAll(OPTOUT_PLACEHOLDER, optoutUrl),
        headers: {
          "List-Unsubscribe":
            `<mailto:${replyTo}?subject=N%C3%A3o%20quero%20receber>, <${optoutUrl}>`,
        },
        tags: ["convite", template],
      }),
    });
    const payload = await res.json().catch(() => ({}));
    if (res.ok) {
      ok = true;
      messageId = typeof payload.messageId === "string" ? payload.messageId : null;
    } else {
      errorText = `Brevo ${res.status}: ${payload.message ?? res.statusText}`;
    }
  } catch (e) {
    errorText = `Sem ligação ao Brevo: ${e instanceof Error ? e.message : String(e)}`;
  }

  const { error: finishError } = await supabase.rpc("admin_invite_finish", {
    p_id: row.id,
    p_ok: ok,
    p_provider_message_id: messageId,
    p_error: errorText,
  });
  if (finishError) console.error("admin_invite_finish", finishError.message);

  if (!ok) return json(502, { id: row.id, status: "failed", error: errorText });
  return json(200, { id: row.id, status: "sent" });
});
