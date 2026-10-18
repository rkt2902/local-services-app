/// Destaques e links do perfil do worker (migration 0051): o que ele quer
/// mostrar ao cliente além das avaliações. Tudo declarado pelo próprio, sem
/// verificação. Os limites batem com os CHECK de `worker_profiles` na 0051.
library;

const int maxWorkerHighlights = 5;
const int maxWorkerHighlightLength = 80;
const int _maxUrlLength = 300;

enum WorkerSocialLinkKind {
  instagram('instagram'),
  facebook('facebook'),
  website('website'),
  other('other');

  const WorkerSocialLinkKind(this.dbValue);
  final String dbValue;

  static WorkerSocialLinkKind? fromDb(String? value) {
    for (final kind in values) {
      if (kind.dbValue == value) return kind;
    }
    return null;
  }
}

class WorkerSocialLink {
  const WorkerSocialLink({required this.kind, required this.url});

  final WorkerSocialLinkKind kind;

  /// Sempre `https://` (normalizado por [normalizeSocialLink]).
  final String url;

  Map<String, dynamic> toJson() => {'kind': kind.dbValue, 'url': url};

  /// Ignora entradas que não são `https://` válidas: estes links são
  /// abertos fora da app, por isso nunca se confia só no que vem da BD.
  static List<WorkerSocialLink> listFromJson(Object? json) {
    if (json is! List) return const [];
    final links = <WorkerSocialLink>[];
    for (final item in json) {
      if (item is! Map) continue;
      final kind = WorkerSocialLinkKind.fromDb(item['kind'] as String?);
      final url = item['url'];
      if (kind == null || url is! String || _validHttpsUri(url) == null) {
        continue;
      }
      links.add(WorkerSocialLink(kind: kind, url: url));
    }
    return links;
  }

  /// Nome mostrado no botão do link.
  String get label => switch (kind) {
        WorkerSocialLinkKind.instagram => 'Instagram',
        WorkerSocialLinkKind.facebook => 'Facebook',
        WorkerSocialLinkKind.website => 'Site',
        WorkerSocialLinkKind.other => _labelForHost(Uri.parse(url).host),
      };
}

/// Destaques vindos da BD, já limpos (sem vazios, cortados aos limites).
List<String> highlightsFromJson(Object? json) {
  if (json is! List) return const [];
  return json
      .whereType<String>()
      .map((h) => h.trim())
      .where((h) => h.isNotEmpty && h.length <= maxWorkerHighlightLength)
      .take(maxWorkerHighlights)
      .toList();
}

/// Mensagem de erro para o que o worker escreveu no campo do link, ou null
/// se estiver bem (ou vazio, que quer dizer "sem link").
String? socialLinkError(String input, WorkerSocialLinkKind kind) {
  if (input.trim().isEmpty) return null;
  if (normalizeSocialLink(input, kind) != null) return null;
  return switch (kind) {
    WorkerSocialLinkKind.instagram =>
      'Escreve o teu @ ou o link do Instagram.',
    WorkerSocialLinkKind.facebook =>
      'Escreve o nome da página ou o link do Facebook.',
    _ => 'Link inválido. Ex.: www.ojeujardim.pt',
  };
}

/// Converte o que o worker escreveu num link `https://` seguro, ou null se
/// não der. Aceita `@nome` (Instagram/Facebook), links sem `https://` e
/// links `http://` (passam a `https://`).
String? normalizeSocialLink(String input, WorkerSocialLinkKind kind) {
  var text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;

  final isHandle = !text.contains('/') && !text.contains('.com');
  if (isHandle) {
    final handle = text.startsWith('@') ? text.substring(1) : text;
    if (!RegExp(r'^[A-Za-z0-9._-]{1,60}$').hasMatch(handle)) {
      // Pode ser um domínio (ex. "ojeujardim.pt") para site/outro.
      if (kind == WorkerSocialLinkKind.instagram ||
          kind == WorkerSocialLinkKind.facebook) {
        return null;
      }
    } else if (kind == WorkerSocialLinkKind.instagram) {
      return 'https://www.instagram.com/$handle';
    } else if (kind == WorkerSocialLinkKind.facebook) {
      return 'https://www.facebook.com/$handle';
    }
  }

  final lower = text.toLowerCase();
  if (lower.startsWith('http://')) {
    text = 'https://${text.substring(7)}';
  } else if (!lower.startsWith('https://')) {
    if (text.contains(':')) return null; // outro esquema (javascript:, ...)
    text = 'https://$text';
  }

  final uri = _validHttpsUri(text);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  final hostOk = switch (kind) {
    WorkerSocialLinkKind.instagram => _isHost(host, 'instagram.com'),
    WorkerSocialLinkKind.facebook =>
      _isHost(host, 'facebook.com') || _isHost(host, 'fb.com'),
    _ => true,
  };
  return hostOk ? text : null;
}

Uri? _validHttpsUri(String text) {
  if (text.length > _maxUrlLength || text.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  final host = uri.host;
  if (host.isEmpty || !host.contains('.') || host.startsWith('.') ||
      host.endsWith('.')) {
    return null;
  }
  return uri;
}

bool _isHost(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

String _labelForHost(String rawHost) {
  final host = rawHost.toLowerCase();
  if (_isHost(host, 'tiktok.com')) return 'TikTok';
  if (_isHost(host, 'youtube.com') || host == 'youtu.be') return 'YouTube';
  if (_isHost(host, 'linkedin.com')) return 'LinkedIn';
  if (_isHost(host, 'instagram.com')) return 'Instagram';
  if (_isHost(host, 'facebook.com')) return 'Facebook';
  if (host == 'maps.app.goo.gl' || host.startsWith('maps.google.')) {
    return 'Google Maps';
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}
