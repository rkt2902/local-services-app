import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.index,
    this.size = 220,
  });

  final int index;
  final double size;

  static const _icons = [
    Icons.yard,
    Icons.receipt_long,
    Icons.verified,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IllustrationBgPainter(index: index),
        child: Center(
          child: Icon(
            _icons[index],
            size: size * 0.36,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _IllustrationBgPainter extends CustomPainter {
  const _IllustrationBgPainter({required this.index});

  final int index;

  // Three sets of decorative dot offsets — one per slide.
  // Values are fractions of the main circle radius.
  static const _decoOffsets = [
    [Offset(-0.78, 0.62), Offset(0.82, 0.70), Offset(-0.66, -0.80)],
    [Offset(0.80, -0.64), Offset(-0.88, 0.52), Offset(0.60, 0.82)],
    [Offset(-0.76, -0.68), Offset(0.86, 0.48), Offset(-0.54, 0.84)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.44;

    // Primary background circle
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = AppColors.primary.withValues(alpha: 0.10),
    );

    // Secondary offset circle — gives depth without complexity
    canvas.drawCircle(
      Offset(cx + r * 0.22, cy - r * 0.18),
      r * 0.34,
      Paint()..color = AppColors.primary.withValues(alpha: 0.07),
    );

    // Small decorative dots using the accent colour
    final dotPaint = Paint()
      ..color = AppColors.logoAccent.withValues(alpha: 0.28);
    final dotR = r * 0.11;
    for (final off in _decoOffsets[index]) {
      canvas.drawCircle(
        Offset(cx + off.dx * r, cy + off.dy * r),
        dotR,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IllustrationBgPainter old) =>
      old.index != index;
}
