import 'package:flutter/material.dart';

import '../../features/worker/data/service_type_model.dart';

/// Ícone genérico para tipos sem ícone ou com um nome desconhecido.
const IconData kDefaultServiceIcon = Icons.yard_outlined;

/// Nomes guardados em `service_types.icon` / `service_categories.icon`
/// (migration 0045). O Flutter não carrega ícones por nome, por isso cada
/// nome usado na BD tem de estar aqui; um nome novo sem entrada mostra o
/// ícone genérico em vez de partir.
const Map<String, IconData> _serviceIcons = {
  'agriculture': Icons.agriculture_outlined,
  'carpenter': Icons.carpenter_outlined,
  'cleaning_services': Icons.cleaning_services_outlined,
  'compost': Icons.compost_outlined,
  'content_cut': Icons.content_cut_outlined,
  'delete_sweep': Icons.delete_sweep_outlined,
  'eco': Icons.eco_outlined,
  'energy_savings_leaf': Icons.energy_savings_leaf_outlined,
  'fence': Icons.fence_outlined,
  'filter_vintage': Icons.filter_vintage_outlined,
  'fireplace': Icons.fireplace_outlined,
  'forest': Icons.forest_outlined,
  'grain': Icons.grain_outlined,
  'grass': Icons.grass_outlined,
  'handyman': Icons.handyman_outlined,
  'landscape': Icons.landscape_outlined,
  'local_fire_department': Icons.local_fire_department_outlined,
  'local_florist': Icons.local_florist_outlined,
  'nature': Icons.nature_outlined,
  'park': Icons.park_outlined,
  'pest_control': Icons.pest_control_outlined,
  'recycling': Icons.recycling_outlined,
  'science': Icons.science_outlined,
  'shopping_basket': Icons.shopping_basket_outlined,
  'spa': Icons.spa_outlined,
  'terrain': Icons.terrain_outlined,
  'texture': Icons.texture_outlined,
  'water': Icons.water_outlined,
  'water_drop': Icons.water_drop_outlined,
  'wine_bar': Icons.wine_bar_outlined,
  'yard': Icons.yard_outlined,
};

IconData serviceIconFor(String? name) =>
    _serviceIcons[name] ?? kDefaultServiceIcon;

/// Ícone do tipo de serviço de um pedido, a partir da lista de
/// `serviceTypesProvider`. Genérico enquanto a lista carrega.
IconData serviceTypeIconFor(List<ServiceType> types, String? serviceTypeId) {
  for (final t in types) {
    if (t.id == serviceTypeId) return serviceIconFor(t.icon);
  }
  return kDefaultServiceIcon;
}
