import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../data/admin_partner_models.dart';

/// Ponto de uma gasolineira no mapa: círculo com a bomba, na cor do
/// estado (parceira, em conversa, terminada).
class AdminPartnerMarker extends StatelessWidget {
  const AdminPartnerMarker({
    required this.status,
    this.selected = false,
    super.key,
  });

  final AdminPartnerStatus status;
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
      child: const Icon(
        Icons.local_gas_station_rounded,
        size: AppSizes.adminPartnerMarkerIcon,
        color: AppColors.surface,
      ),
    );
  }
}
