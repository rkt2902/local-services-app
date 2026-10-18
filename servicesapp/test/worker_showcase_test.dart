import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/worker/data/worker_showcase.dart';

void main() {
  group('normalizeSocialLink', () {
    test('Instagram aceita @nome, nome e link', () {
      const k = WorkerSocialLinkKind.instagram;
      expect(normalizeSocialLink('@o.meu_jardim', k),
          'https://www.instagram.com/o.meu_jardim');
      expect(normalizeSocialLink('ojardim', k),
          'https://www.instagram.com/ojardim');
      expect(normalizeSocialLink('instagram.com/ojardim', k),
          'https://instagram.com/ojardim');
      expect(normalizeSocialLink('http://www.instagram.com/ojardim', k),
          'https://www.instagram.com/ojardim');
    });

    test('Instagram recusa outro site', () {
      expect(
        normalizeSocialLink('https://facebook.com/x', WorkerSocialLinkKind.instagram),
        isNull,
      );
    });

    test('Facebook aceita página e fb.com', () {
      const k = WorkerSocialLinkKind.facebook;
      expect(normalizeSocialLink('ojardim', k), 'https://www.facebook.com/ojardim');
      expect(normalizeSocialLink('https://fb.com/ojardim', k), 'https://fb.com/ojardim');
      expect(normalizeSocialLink('https://m.facebook.com/ojardim', k),
          'https://m.facebook.com/ojardim');
    });

    test('site sem esquema ganha https', () {
      const k = WorkerSocialLinkKind.website;
      expect(normalizeSocialLink('www.ojardim.pt', k), 'https://www.ojardim.pt');
      expect(normalizeSocialLink('ojardim.pt/fotos', k), 'https://ojardim.pt/fotos');
    });

    test('recusa esquemas perigosos e lixo', () {
      const k = WorkerSocialLinkKind.other;
      expect(normalizeSocialLink('javascript:alert(1)', k), isNull);
      expect(normalizeSocialLink('ftp://ojardim.pt', k), isNull);
      expect(normalizeSocialLink('https://user:pw@ojardim.pt', k), isNull);
      expect(normalizeSocialLink('ojardim', k), isNull);
      expect(normalizeSocialLink('o jardim.pt', k), isNull);
      expect(normalizeSocialLink('https://${'a' * 300}.pt', k), isNull);
    });

    test('vazio quer dizer sem link e não é erro', () {
      expect(normalizeSocialLink('  ', WorkerSocialLinkKind.website), isNull);
      expect(socialLinkError('  ', WorkerSocialLinkKind.website), isNull);
      expect(socialLinkError('xx', WorkerSocialLinkKind.website), isNotNull);
    });
  });

  group('fromJson', () {
    test('ignora links que não são https ou de tipo desconhecido', () {
      final links = WorkerSocialLink.listFromJson([
        {'kind': 'instagram', 'url': 'https://www.instagram.com/a'},
        {'kind': 'website', 'url': 'javascript:alert(1)'},
        {'kind': 'other', 'url': 'http://inseguro.pt'},
        {'kind': 'pinterest', 'url': 'https://pinterest.com/a'},
        'lixo',
      ]);
      expect(links, hasLength(1));
      expect(links.single.kind, WorkerSocialLinkKind.instagram);
      expect(WorkerSocialLink.listFromJson(null), isEmpty);
    });

    test('nome do link outro vem do site', () {
      WorkerSocialLink other(String url) =>
          WorkerSocialLink(kind: WorkerSocialLinkKind.other, url: url);
      expect(other('https://www.tiktok.com/@a').label, 'TikTok');
      expect(other('https://youtu.be/x').label, 'YouTube');
      expect(other('https://maps.app.goo.gl/x').label, 'Google Maps');
      expect(other('https://www.ojardim.pt').label, 'ojardim.pt');
    });

    test('destaques limpos e no máximo 5', () {
      expect(
        highlightsFromJson([' Seguro ', '', 'a', 'b', 'c', 'd', 'e', 1]),
        ['Seguro', 'a', 'b', 'c', 'd'],
      );
      expect(highlightsFromJson(null), isEmpty);
    });
  });
}
