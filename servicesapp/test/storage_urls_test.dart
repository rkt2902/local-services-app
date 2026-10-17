import 'package:flutter_test/flutter_test.dart';

import 'package:servicesapp/core/config/storage_urls.dart';

void main() {
  const project = 'https://abcdefghijklmnop.supabase.co';
  const avatar =
      '$project/storage/v1/object/public/avatars/123.jpg?v=1700000000000';

  String? check(String? url) =>
      StorageUrls.trustedForProject(url, supabaseUrl: project);

  test('aceita foto do Storage do projeto', () {
    expect(check(avatar), avatar);
  });

  test('aceita o URL do projeto com / no fim', () {
    expect(
      StorageUrls.trustedForProject(avatar, supabaseUrl: '$project/'),
      avatar,
    );
  });

  test('recusa URL externo', () {
    expect(check('https://evil.example/pixel.png'), isNull);
  });

  test('recusa outro projeto Supabase', () {
    expect(
      check('https://outroprojeto.supabase.co/storage/v1/object/public/a.jpg'),
      isNull,
    );
  });

  test('recusa domínio que só começa igual', () {
    expect(
      check('$project.evil.example/storage/v1/object/public/a.jpg'),
      isNull,
    );
  });

  test('vazio ou nulo dá null', () {
    expect(check(null), isNull);
    expect(check(''), isNull);
  });

  test('sem SUPABASE_URL não aceita nada', () {
    expect(StorageUrls.trustedForProject(avatar, supabaseUrl: ''), isNull);
  });
}
