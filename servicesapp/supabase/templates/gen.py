import json,os
BASE='''<!DOCTYPE html>
<html lang="pt"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ProJardim</title></head>
<body style="margin:0;padding:0;background:#F6F8F6;">
<div style="display:none;max-height:0;overflow:hidden;">{preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F8F6;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;font-family:'Plus Jakarta Sans',Arial,Helvetica,sans-serif;color:#1A1C1A;">
<tr><td style="padding:0 8px 16px;font-size:22px;font-weight:800;color:#2E7D32;">Pro<span style="color:#1A1C1A;">Jardim</span></td></tr>
<tr><td style="background:#FFFFFF;border:1px solid #E6EBE7;border-radius:16px;padding:32px 24px;">
<h1 style="margin:0 0 12px;font-size:22px;line-height:1.3;font-weight:700;color:#1A1C1A;">{title}</h1>
<p style="margin:0 0 24px;font-size:15px;line-height:1.55;color:#5F6B62;">{intro}</p>
{main}
<p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:#5F6B62;">{note}</p>
</td></tr>
<tr><td style="padding:16px 8px 0;font-size:12px;line-height:1.5;color:#5F6B62;text-align:center;">ProJardim, jardineiros de confiança perto de ti.<br>Dúvidas? Escreve para <a href="mailto:suporte@projardim.pt" style="color:#2E7D32;text-decoration:none;">suporte@projardim.pt</a></td></tr>
</table></td></tr></table></body></html>
'''
CODE='''<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#EBF5E9;border-radius:12px;padding:20px 12px;">
<div style="font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#5F6B62;margin-bottom:6px;">O teu código</div>
<div style="font-size:32px;font-weight:800;letter-spacing:8px;color:#2E7D32;font-family:'Courier New',monospace;">{{ .Token }}</div>
</td></tr></table>'''
BTN='''<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr><td align="center" style="background:#2E7D32;border-radius:999px;">
<a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:700;color:#FFFFFF;text-decoration:none;">{label}</a>
</td></tr></table>'''
T={
 'confirmation':dict(subject='Confirma o teu email no ProJardim',preheader='O teu código de confirmação está aqui dentro.',title='Bem-vindo ao ProJardim',intro='Falta só confirmar o teu email. Escreve este código na app:',main=CODE,note='O código expira dentro de 1 hora. Se não criaste uma conta no ProJardim, podes ignorar este email.'),
 'recovery':dict(subject='Recuperar a palavra-passe do ProJardim',preheader='Usa este código para escolher uma palavra-passe nova.',title='Recuperar a palavra-passe',intro='Recebemos um pedido para mudar a palavra-passe da tua conta. Escreve este código na app:',main=CODE,note='O código expira dentro de 1 hora. Se não pediste isto, ignora este email: a tua palavra-passe continua igual.'),
 'magic_link':dict(subject='O teu código de acesso ao ProJardim',preheader='Entra no ProJardim com este código.',title='Entrar no ProJardim',intro='Escreve este código na app para entrares na tua conta:',main=CODE,note='O código expira dentro de 1 hora. Se não tentaste entrar, ignora este email.'),
 'email_change':dict(subject='Confirma o teu novo email no ProJardim',preheader='Confirma a mudança de email da tua conta.',title='Confirmar o novo email',intro='Pediste para mudar o email da tua conta de {{ .Email }} para {{ .NewEmail }}. Escreve este código na app para confirmar:',main=CODE,note='Se não pediste esta mudança, ignora este email e escreve-nos para suporte@projardim.pt.'),
 'invite':dict(subject='Foste convidado para o ProJardim',preheader='Aceita o convite e cria a tua conta.',title='Foste convidado',intro='Alguém convidou-te para usar o ProJardim. Carrega no botão para aceitar e criar a tua conta:',main=BTN.replace('{label}','Aceitar convite'),note='Se não estavas à espera deste convite, podes ignorar este email.'),
 'reauthentication':dict(subject='Código de confirmação do ProJardim',preheader='Confirma que és tu com este código.',title='Confirmar que és tu',intro='Para concluir esta ação na tua conta, escreve este código na app:',main=CODE,note='O código expira em poucos minutos. Se não estás a fazer nada na app, ignora este email.'),
}
meta={}
for k,v in T.items():
    html=BASE
    for f in ['preheader','title','intro','main','note']:
        html=html.replace('{'+f+'}',v[f])
    open(f'{k}.html','w').write(html)
    meta[k]=v['subject']
open('subjects.json','w').write(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
