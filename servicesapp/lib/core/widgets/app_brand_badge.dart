import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppBrandBadge extends StatelessWidget {
  const AppBrandBadge({
    super.key,
    this.size = 60,
    this.iconSize = 28,
    this.backgroundColor = AppColors.primaryContainer,
    this.iconColor = AppColors.primary,
  });

  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.eco_outlined, size: iconSize, color: iconColor),
    );
  }
}
