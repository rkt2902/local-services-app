class ServiceType {
  final String id;
  final String name;
  final String slug;

  const ServiceType({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory ServiceType.fromJson(Map<String, dynamic> json) => ServiceType(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
      );
}
