# Templates de email do Supabase Auth

Fonte dos 6 emails que o Supabase Auth envia (Authentication > Emails > Templates).
Estilo da app: fundo `#F6F8F6`, cartão branco com raio 16, código em `#EBF5E9` com
texto `#2E7D32`, botão em pílula verde. Só HTML com estilos inline (os clientes de
email ignoram `<style>` e fontes externas, por isso a fonte cai para Arial).

| Ficheiro | Template no Supabase | Usado pela app |
|---|---|---|
| `confirmation.html` | Confirm sign up | sim, código de 6 dígitos no registo |
| `recovery.html` | Reset password | sim, código de 6 dígitos na recuperação |
| `magic_link.html` | Magic link or OTP | não (preparado) |
| `email_change.html` | Change email address | não (a app não muda o email) |
| `invite.html` | Invite user | só se convidares alguém pelo painel |
| `reauthentication.html` | Reauthentication | não (preparado) |

Os assuntos estão em `subjects.json`. Para mudar o texto, edita `gen.py` e corre
`python3 gen.py` dentro desta pasta; depois copia o HTML e o assunto para o painel.

Estado a 13/11/2026: os 6 já estão colados no painel do projeto. As notificações de
segurança (password alterada, etc.) continuam desligadas.
