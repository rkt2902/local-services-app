import 'dart:ui' show Color;

import '../../../core/config/app_links.dart';
import '../../../core/theme/app_colors.dart';

/// Sítio do link "não quero receber" no HTML e no texto. A Edge Function
/// `send-invite` troca-o pelo link com o token deste envio (0085) e recusa
/// um email que não o tenha.
const adminInviteOptoutPlaceholder = '{{optout_url}}';

/// WhatsApp da ProJardim nos convites (o mesmo dos materiais de marketing).
const adminInviteWhatsApp = '961 651 756';

const adminInviteNameMax = 80;
const adminInviteSubjectMax = 150;
const adminInviteSignedByMax = 60;
const adminInviteFounderTermMax = 40;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Mesma regra que a `admin_invite_create` usa na BD.
bool adminInviteEmailLooksValid(String email) {
  final value = email.trim();
  return value.length <= 254 && _emailPattern.hasMatch(value);
}

/// Modelos de convite. [dbValue] é o que fica em `admin_invites.template`.
enum AdminInviteTemplate {
  founderInvite(
    'founder_invite',
    'Convite com design',
    'O convite completo, com as vantagens, o Plano Pro de fundador e o '
        'botão para criar a conta.',
  ),
  founderInvitePlain(
    'founder_invite_plain',
    'Convite só texto',
    'O mesmo convite com aspeto de email pessoal. Costuma chegar mais '
        'vezes à caixa principal.',
  ),
  founderReminder(
    'founder_reminder',
    'Lembrete',
    'Uma semana depois, para quem ainda não respondeu ao convite.',
  );

  const AdminInviteTemplate(this.dbValue, this.label, this.description);

  final String dbValue;
  final String label;
  final String description;

  static AdminInviteTemplate? fromDb(String? value) {
    for (final t in values) {
      if (t.dbValue == value) return t;
    }
    return null;
  }

  /// Assuntos sugeridos (o primeiro é o de omissão). [name] é o nome do
  /// destinatário como foi escrito.
  List<String> subjectOptions(String name) {
    final n = name.trim().isEmpty ? '[Nome]' : name.trim();
    return switch (this) {
      founderInvite || founderInvitePlain => [
        'Convite para Profissional fundador da ProJardim',
        '$n, gostávamos de o ter na ProJardim',
        'Mais trabalho na sua zona, sem pagar por contacto',
      ],
      founderReminder => [
        'Ainda tem lugar como Profissional fundador da ProJardim',
        '$n, teve oportunidade de ver o convite?',
      ],
    };
  }
}

/// O que o admin preenche no ecrã.
class AdminInviteDraft {
  const AdminInviteDraft({
    required this.template,
    required this.recipientName,
    required this.recipientEmail,
    required this.subject,
    required this.signedBy,
    this.founderTerm = '',
  });

  final AdminInviteTemplate template;
  final String recipientName;
  final String recipientEmail;
  final String subject;

  /// Quem assina ("[O seu nome]" nos textos de marketing).
  final String signedBy;

  /// Duração do Pro de fundador, ex.: "durante 12 meses". Vazio = não diz.
  final String founderTerm;

  /// Pronto a enviar: tudo o que a BD vai validar outra vez.
  bool get isComplete {
    final name = recipientName.trim();
    final subj = subject.trim();
    final signer = signedBy.trim();
    return name.length >= 2 &&
        name.length <= adminInviteNameMax &&
        adminInviteEmailLooksValid(recipientEmail) &&
        subj.length >= 3 &&
        subj.length <= adminInviteSubjectMax &&
        signer.length >= 2 &&
        signer.length <= adminInviteSignedByMax &&
        founderTerm.trim().length <= adminInviteFounderTermMax;
  }
}

/// Um convite pronto, em blocos: dá o HTML e o texto que se enviam e a
/// pré-visualização no painel, sempre a partir do mesmo conteúdo.
class AdminInviteMessage {
  const AdminInviteMessage({
    required this.template,
    required this.subject,
    required this.designed,
    required this.greeting,
    required this.paragraphs,
    required this.signOff,
    required this.signedBy,
    required this.signatureLines,
    required this.footerLines,
    required this.siteUrl,
    required this.siteLabel,
    this.kicker,
    this.heading,
    this.benefitsTitle,
    this.benefits = const [],
    this.founderTitle,
    this.founderBody,
    this.ctaLabel,
    this.ctaHint,
    this.closingParagraphs = const [],
  });

  final AdminInviteTemplate template;
  final String subject;

  /// `true`: topo verde, vantagens, caixa dourada e botão. `false`: aspeto
  /// de email pessoal, só texto.
  final bool designed;
  final String? kicker;
  final String? heading;
  final String greeting;
  final List<String> paragraphs;
  final String? benefitsTitle;
  final List<String> benefits;
  final String? founderTitle;
  final String? founderBody;
  final String? ctaLabel;
  final String? ctaHint;
  final List<String> closingParagraphs;
  final String signOff;
  final String signedBy;
  final List<String> signatureLines;

  /// Rodapé; a última frase termina com o link "não quero receber".
  final List<String> footerLines;
  final String siteUrl;
  final String siteLabel;

  static const optoutLabel = 'Não quero receber mais emails';

  /// HTML do email. Com [optoutUrl] por omissão leva o marcador que a Edge
  /// Function troca.
  String toHtml({String optoutUrl = adminInviteOptoutPlaceholder}) =>
      designed ? _designedHtml(optoutUrl) : _plainHtml(optoutUrl);

  /// Versão só texto (vai sempre junto com o HTML).
  String toText({String optoutUrl = adminInviteOptoutPlaceholder}) {
    final out = StringBuffer()
      ..writeln(greeting)
      ..writeln();
    for (final p in paragraphs) {
      out
        ..writeln(p)
        ..writeln();
    }
    if (benefits.isNotEmpty) {
      if (benefitsTitle != null) out.writeln('$benefitsTitle:');
      for (final b in benefits) {
        out.writeln('- $b');
      }
      out.writeln();
    }
    if (founderTitle != null) {
      out
        ..writeln(founderTitle)
        ..writeln(founderBody ?? '')
        ..writeln();
    }
    if (ctaLabel != null) {
      out
        ..writeln('$ctaLabel: $siteUrl')
        ..writeln();
    }
    for (final p in closingParagraphs) {
      out
        ..writeln(p)
        ..writeln();
    }
    out
      ..writeln(signOff)
      ..writeln(signedBy);
    for (final line in signatureLines) {
      out.writeln(line);
    }
    out
      ..writeln()
      ..writeln('--');
    for (final line in footerLines) {
      out.writeln(line);
    }
    out.write('$optoutLabel: $optoutUrl');
    return out.toString();
  }

  String _designedHtml(String optoutUrl) {
    final font = "'Plus Jakarta Sans',Arial,Helvetica,sans-serif";
    final primary = cssHex(AppColors.primary);
    final text = cssHex(AppColors.textPrimary);
    final muted = cssHex(AppColors.textSecondary);
    final divider = cssHex(AppColors.divider);
    final b = StringBuffer()
      ..write('<!doctype html><html lang="pt-PT"><head><meta charset="utf-8">')
      ..write(
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
      )
      ..write('<title>${_esc(subject)}</title></head>')
      ..write(
        '<body style="margin:0;padding:0;background:${cssHex(AppColors.background)};">',
      )
      ..write(
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'border="0" style="background:${cssHex(AppColors.background)};">'
        '<tr><td align="center" style="padding:24px 12px;">',
      )
      ..write(
        '<table role="presentation" width="600" cellpadding="0" cellspacing="0" '
        'border="0" style="width:100%;max-width:600px;background:'
        '${cssHex(AppColors.surface)};border-radius:16px;border:1px solid $divider;'
        'font-family:$font;color:$text;">',
      )
      // topo
      ..write(
        '<tr><td style="background:$primary;border-radius:16px 16px 0 0;'
        'padding:28px 32px 30px;">'
        '<div style="font-size:20px;font-weight:800;color:${cssHex(AppColors.surface)};'
        'letter-spacing:-0.3px;">ProJardim</div>',
      );
    if (kicker != null) {
      b.write(
        '<div style="font-size:12px;font-weight:700;color:'
        '${cssHex(AppColors.onPrimaryMuted)};letter-spacing:1.5px;'
        'text-transform:uppercase;margin-top:22px;">${_esc(kicker!)}</div>',
      );
    }
    if (heading != null) {
      b.write(
        '<div style="font-size:26px;line-height:32px;font-weight:800;color:'
        '${cssHex(AppColors.surface)};margin-top:8px;">${_esc(heading!)}</div>',
      );
    }
    b
      ..write('</td></tr>')
      // texto
      ..write(
        '<tr><td style="padding:28px 32px 8px;font-size:15px;line-height:24px;'
        'color:$text;">',
      )
      ..write('<p style="margin:0 0 14px;">${_esc(greeting)}</p>');
    for (final p in paragraphs) {
      b.write('<p style="margin:0 0 14px;">${_esc(p)}</p>');
    }
    b.write('</td></tr>');
    if (benefits.isNotEmpty) {
      b.write(
        '<tr><td style="padding:4px 32px 4px;">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'border="0" style="background:${cssHex(AppColors.primaryContainer)};'
        'border-radius:12px;">',
      );
      if (benefitsTitle != null) {
        b.write(
          '<tr><td style="padding:18px 20px 6px;font-size:13px;font-weight:800;'
          'color:${cssHex(AppColors.primaryPressed)};letter-spacing:1px;'
          'text-transform:uppercase;">${_esc(benefitsTitle!)}</td></tr>',
        );
      }
      b.write(
        '<tr><td style="padding:0 20px 16px;font-size:14.5px;line-height:22px;'
        'color:$text;">',
      );
      for (final item in benefits) {
        b.write(
          '<div style="padding:5px 0;"><span style="color:$primary;'
          'font-weight:800;">&#10003;</span>&nbsp; ${_esc(item)}</div>',
        );
      }
      b.write('</td></tr></table></td></tr>');
    }
    if (founderTitle != null) {
      b.write(
        '<tr><td style="padding:16px 32px 4px;">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'border="0" style="background:${cssHex(AppColors.founderSurface)};'
        'border:1px solid ${cssHex(AppColors.founderBorder)};border-radius:12px;">'
        '<tr><td style="padding:16px 20px;font-size:14.5px;line-height:22px;'
        'color:${cssHex(AppColors.founderText)};">'
        '<b style="font-size:15.5px;color:${cssHex(AppColors.founderTitle)};">'
        '${_esc(founderTitle!)}</b><br>${_esc(founderBody ?? '')}'
        '</td></tr></table></td></tr>',
      );
    }
    if (ctaLabel != null) {
      final url = _esc(siteUrl);
      b.write(
        '<tr><td align="center" style="padding:26px 32px 6px;">'
        '<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>'
        '<td style="background:$primary;border-radius:12px;">'
        '<a href="$url" style="display:inline-block;padding:14px 30px;font-size:16px;'
        'font-weight:800;color:${cssHex(AppColors.surface)};text-decoration:none;'
        'font-family:$font;">${_esc(ctaLabel!)}</a></td></tr></table>',
      );
      if (ctaHint != null) {
        b.write(
          '<div style="font-size:13px;color:$muted;margin-top:10px;">'
          '${_linkSite(_esc(ctaHint!), primary)}</div>',
        );
      }
      b.write('</td></tr>');
    }
    b.write(
      '<tr><td style="padding:20px 32px 8px;font-size:15px;line-height:24px;'
      'color:$text;">',
    );
    for (final p in closingParagraphs) {
      b.write('<p style="margin:0 0 14px;">${_esc(p)}</p>');
    }
    b
      ..write('<p style="margin:0 0 4px;">${_esc(signOff)}</p>')
      ..write(
        '<p style="margin:0;font-weight:700;">${_esc(signedBy)}'
        '<br><span style="font-weight:400;color:$muted;">ProJardim</span></p>',
      )
      ..write('</td></tr>')
      // rodapé
      ..write(
        '<tr><td style="padding:22px 32px 26px;border-top:1px solid $divider;'
        'font-size:12px;line-height:18px;color:$muted;">',
      )
      ..write(_footerHtml(optoutUrl, muted))
      ..write('</td></tr></table></td></tr></table></body></html>');
    return b.toString();
  }

  String _plainHtml(String optoutUrl) {
    final text = cssHex(AppColors.textPrimary);
    final muted = cssHex(AppColors.textSecondary);
    final b = StringBuffer()
      ..write('<!doctype html><html lang="pt-PT"><head><meta charset="utf-8">')
      ..write('<title>${_esc(subject)}</title></head>')
      ..write(
        '<body style="margin:0;padding:16px;font-family:Arial,Helvetica,sans-serif;'
        'font-size:15px;line-height:23px;color:$text;">',
      )
      ..write('<p style="margin:0 0 14px;">${_esc(greeting)}</p>');
    for (final p in paragraphs) {
      b.write('<p style="margin:0 0 14px;">${_linkSite(_esc(p), text)}</p>');
    }
    b
      ..write('<p style="margin:0 0 2px;">${_esc(signOff)}</p>')
      ..write('<p style="margin:0 0 20px;">${_esc(signedBy)}');
    for (final line in signatureLines) {
      b.write('<br>${_linkSite(_esc(line), text)}');
    }
    b
      ..write('</p>')
      ..write(
        '<p style="margin:0;font-size:12px;line-height:18px;color:$muted;">',
      )
      ..write(_footerHtml(optoutUrl, muted, includeContacts: false))
      ..write('</p></body></html>');
    return b.toString();
  }

  String _footerHtml(
    String optoutUrl,
    String color, {
    bool includeContacts = true,
  }) {
    final lines = includeContacts ? footerLines : footerLines.skip(1);
    final link =
        '<a href="${_esc(optoutUrl)}" style="color:$color;'
        'text-decoration:underline;">$optoutLabel</a>.';
    return [...lines.map(_esc), link].join('<br>');
  }

  /// Torna "projardim.pt" (sozinho no texto) num link para o site.
  String _linkSite(String escaped, String color) => escaped.replaceFirst(
    RegExp(r'(?<![@\w.])' + RegExp.escape(siteLabel) + r'(?![\w])'),
    '<a href="${_esc(siteUrl)}" style="color:$color;font-weight:700;'
    'text-decoration:none;">$siteLabel</a>',
  );
}

/// `#RRGGBB` de uma cor do design system, para o HTML do email.
String cssHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _esc(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Monta o convite a partir do que o admin preencheu.
AdminInviteMessage buildAdminInvite(
  AdminInviteDraft draft, {
  String? siteUrl,
  String? supportEmail,
}) {
  final url = siteUrl ?? AppLinks.emailSiteUrl;
  final label = Uri.tryParse(url)?.host.isNotEmpty == true
      ? Uri.parse(url).host
      : url;
  final support = supportEmail ?? AppLinks.supportEmail;
  final name = draft.recipientName.trim().isEmpty
      ? '[Nome]'
      : draft.recipientName.trim();
  final signer = draft.signedBy.trim().isEmpty
      ? '[O seu nome]'
      : draft.signedBy.trim();
  final term = draft.founderTerm.trim();
  final pro = term.isEmpty ? 'o Plano Pro grátis' : 'o Plano Pro grátis $term';
  final greeting = 'Bom dia, $name.';
  final subject = draft.subject.trim();
  final footerContacts =
      'ProJardim · $label · $support · WhatsApp $adminInviteWhatsApp';
  const why =
      'Recebeu este email porque achamos que a ProJardim pode ser útil ao '
      'seu trabalho. Se não quiser receber mais mensagens nossas, basta '
      'responder com "não" ou usar o link:';
  final plainSignature = [
    'ProJardim · $label',
    'WhatsApp $adminInviteWhatsApp · $support',
  ];

  switch (draft.template) {
    case AdminInviteTemplate.founderInvite:
      return AdminInviteMessage(
        template: draft.template,
        subject: subject,
        designed: true,
        kicker: 'Convite · Profissional fundador',
        heading: 'Mais trabalho na sua zona, sem pagar por cada contacto.',
        greeting: greeting,
        paragraphs: const [
          'Estamos a lançar a ProJardim, uma app que liga clientes a '
              'Profissionais de jardim, terrenos, agricultura e floresta. O '
              'cliente publica o que precisa, os Profissionais da zona recebem '
              'o aviso e enviam a sua proposta. Depois, tudo se combina pelo '
              'WhatsApp, como já faz hoje.',
          'Antes de abrirmos ao público, queremos contar com um pequeno grupo '
              'de Profissionais fundadores. Gostávamos muito que fizesse parte '
              'dele.',
        ],
        benefitsTitle: 'O que a ProJardim oferece',
        benefits: const [
          'Pedidos de clientes perto de si, dos serviços que escolher',
          'Sem pagar por contacto e sem comissões sobre o trabalho',
          'Propostas por hora, valor fechado ou por dias',
          'Agenda, pedidos de ajudantes e avaliações dos clientes',
          'Cartão com QR para os clientes que já tem lhe pedirem trabalho '
              'pela app',
        ],
        founderTitle: 'Como fundador, tem $pro.',
        founderBody:
            'Trabalhos sem limite, selo Pro no perfil, cartão em PDF e painel '
            'de ganhos. Em troca, pedimos apenas que use a app e nos diga o '
            'que falta.',
        ctaLabel: 'Criar a minha conta',
        ctaHint: 'Ou abra $label no telemóvel e escolha "Profissional".',
        closingParagraphs: [
          'Depois de criar a conta, basta responder a este email ou enviar '
              'uma mensagem para o WhatsApp $adminInviteWhatsApp para '
              'ativarmos o plano de fundador. Se preferir, também lhe podemos '
              'mostrar a app pessoalmente ou numa chamada rápida.',
        ],
        signOff: 'Com os melhores cumprimentos,',
        signedBy: signer,
        signatureLines: const ['ProJardim'],
        footerLines: [footerContacts, why],
        siteUrl: url,
        siteLabel: label,
      );
    case AdminInviteTemplate.founderInvitePlain:
      return AdminInviteMessage(
        template: draft.template,
        subject: subject,
        designed: false,
        greeting: greeting,
        paragraphs: [
          'Estamos a lançar a ProJardim, uma app que liga clientes a '
              'Profissionais de jardim, terrenos, agricultura e floresta. O '
              'cliente publica o que precisa, os Profissionais da zona recebem '
              'o aviso e enviam a sua proposta. Depois, tudo se combina pelo '
              'WhatsApp.',
          'Não se paga por contacto nem há comissões sobre o trabalho. O '
              'Profissional escolhe se cobra por hora, por valor fechado ou '
              'por dias, e tem ainda agenda, pedidos de ajudantes, avaliações '
              'e um cartão com QR para os clientes que já tem.',
          'Antes de abrirmos ao público, queremos um pequeno grupo de '
              'Profissionais fundadores, com $pro. Gostávamos muito que '
              'fizesse parte dele.',
          'Pode criar a conta em $label e escolher "Profissional". Depois '
              'basta responder a este email ou enviar mensagem para o '
              'WhatsApp $adminInviteWhatsApp para ativarmos o plano de '
              'fundador.',
        ],
        signOff: 'Com os melhores cumprimentos,',
        signedBy: signer,
        signatureLines: plainSignature,
        footerLines: [footerContacts, why],
        siteUrl: url,
        siteLabel: label,
      );
    case AdminInviteTemplate.founderReminder:
      return AdminInviteMessage(
        template: draft.template,
        subject: subject,
        designed: false,
        greeting: greeting,
        paragraphs: [
          'Escrevo só para saber se teve oportunidade de ver o convite para a '
              'ProJardim. Ainda temos lugar no grupo de Profissionais '
              'fundadores, com $pro.',
          'Se for mais fácil, podemos mostrar a app em 10 minutos, '
              'pessoalmente ou por chamada. A conta cria-se em $label, '
              'escolhendo "Profissional".',
        ],
        signOff: 'Obrigado,',
        signedBy: signer,
        signatureLines: plainSignature,
        footerLines: [footerContacts, why],
        siteUrl: url,
        siteLabel: label,
      );
  }
}
