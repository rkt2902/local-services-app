class ServiceType {
  final String id;
  final String name;
  final String slug;

  /// Nome do ícone Material guardado em `service_types.icon` (0045). A app
  /// traduz o nome com `serviceIconFor` (`core/widgets/service_icon.dart`).
  final String? icon;
  final int sortOrder;
  final String? categoryId;
  final String categoryName;
  final String? categoryIcon;
  final int categorySortOrder;

  const ServiceType({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.sortOrder = 100,
    this.categoryId,
    this.categoryName = 'Outros',
    this.categoryIcon,
    this.categorySortOrder = 100,
  });

  factory ServiceType.fromJson(Map<String, dynamic> json) {
    final category = json['service_categories'] as Map<String, dynamic>?;
    return ServiceType(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      icon: json['icon'] as String?,
      sortOrder: json['sort_order'] as int? ?? 100,
      categoryId: json['category_id'] as String?,
      categoryName: category?['name'] as String? ?? 'Outros',
      categoryIcon: category?['icon'] as String?,
      categorySortOrder: category?['sort_order'] as int? ?? 100,
    );
  }
}

/// Uma categoria (Jardinagem, Agricultura, Floresta...) com os seus tipos.
class ServiceTypeGroup {
  final String name;
  final String? icon;
  final List<ServiceType> types;

  const ServiceTypeGroup({
    required this.name,
    required this.icon,
    required this.types,
  });
}

/// Agrupa por categoria, pela ordem da lista (que já vem ordenada por
/// categoria e por `sort_order` de `WorkerRepository.fetchServiceTypes`).
List<ServiceTypeGroup> groupServiceTypes(List<ServiceType> types) {
  final groups = <String, List<ServiceType>>{};
  final firstOf = <String, ServiceType>{};
  for (final t in types) {
    final key = t.categoryId ?? t.categoryName;
    groups.putIfAbsent(key, () => []).add(t);
    firstOf.putIfAbsent(key, () => t);
  }
  return [
    for (final entry in groups.entries)
      ServiceTypeGroup(
        name: firstOf[entry.key]!.categoryName,
        icon: firstOf[entry.key]!.categoryIcon,
        types: entry.value,
      ),
  ];
}
