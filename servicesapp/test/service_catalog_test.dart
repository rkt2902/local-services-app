import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:servicesapp/core/widgets/service_icon.dart';
import 'package:servicesapp/features/worker/data/service_type_model.dart';

void main() {
  test('todos os ícones da migration 0045 têm ícone próprio na app', () {
    final sql = File(
      'supabase/migrations/0045_service_catalog.sql',
    ).readAsStringSync();
    // Linhas do VALUES: ('categoria', 'slug', 'Nome', 'icone', ordem)
    final rows = RegExp(
      r"\('[a-z_]+',\s*'[a-z_]+',\s*'[^']+',\s*'([a-z_]+)',\s*\d+\)",
    ).allMatches(sql).map((m) => m.group(1)!).toList();
    // Só as linhas dos tipos têm 5 valores (as das categorias têm 4).
    expect(rows.length, 33);
    for (final name in rows) {
      if (name == 'yard') continue; // é o próprio ícone genérico
      expect(serviceIconFor(name), isNot(kDefaultServiceIcon), reason: name);
    }
  });

  test('nome desconhecido ou nulo usa o ícone genérico', () {
    expect(serviceIconFor(null), kDefaultServiceIcon);
    expect(serviceIconFor('nao_existe'), kDefaultServiceIcon);
    expect(serviceIconFor('forest'), Icons.forest_outlined);
  });

  test('fromJson lê categoria e ícone, e funciona sem eles', () {
    final t = ServiceType.fromJson({
      'id': 'a',
      'name': 'Abate de árvores',
      'slug': 'tree_felling',
      'icon': 'carpenter',
      'sort_order': 4,
      'category_id': 'c3',
      'service_categories': {
        'name': 'Floresta',
        'icon': 'forest',
        'sort_order': 3,
      },
    });
    expect(t.categoryName, 'Floresta');
    expect(t.sortOrder, 4);

    final old = ServiceType.fromJson({
      'id': 'b',
      'name': 'Poda',
      'slug': 'pruning',
    });
    expect(old.icon, isNull);
    expect(old.categoryName, 'Outros');
  });

  test('groupServiceTypes agrupa por categoria pela ordem recebida', () {
    const types = [
      ServiceType(
        id: '1',
        name: 'Corte de relva',
        slug: 'a',
        categoryId: 'g',
        categoryName: 'Jardinagem',
      ),
      ServiceType(
        id: '2',
        name: 'Poda',
        slug: 'b',
        categoryId: 'g',
        categoryName: 'Jardinagem',
      ),
      ServiceType(
        id: '3',
        name: 'Vindima',
        slug: 'c',
        categoryId: 'a',
        categoryName: 'Agricultura',
      ),
    ];
    final groups = groupServiceTypes(types);
    expect(groups.map((g) => g.name), ['Jardinagem', 'Agricultura']);
    expect(groups.first.types.length, 2);
  });
}
