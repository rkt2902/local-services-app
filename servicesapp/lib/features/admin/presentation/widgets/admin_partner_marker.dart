import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../data/admin_partner_models.dart';

/// Ponto de um parceiro no mapa: círculo com o ícone do tipo (bomba,
/// flor, ferramenta…), na cor do estado (parceiro, em conversa, terminado).
class AdminPartnerMarker extends StatelessWidget {
  const AdminPartnerMarker({
    required this.status,
    this.kind = PartnerKind.fuelStation,
    this.selected = false,
    super.key,
  });

  final AdminPartnerStatus status;
  final PartnerKind kind;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tone = status.tone;
    return Container(
      width: AppSizes.adminPartnerMarker,
      height: AppSizes.adminPartnerMarker,
      decoration: BoxDecoration(
        color: tone.foreground,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.textPrimary : AppColors.surface,
          width: AppSizes.adminMapDotBorder,
        ),
      ),
      child: Icon(
        kind.icon,
        size: AppSizes.adminPartnerMarkerIcon,
        color: AppColors.surface,
      ),
    );
  }
}
