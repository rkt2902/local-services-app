import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Contorno tracejado arredondado (proposta enviada, A1/A2). O Flutter não
/// tem `BorderStyle.dashed`, por isso é desenhado à mão.
class AgendaDashedBorder extends StatelessWidget {
  const AgendaDashedBorder({
    required this.child,
    required this.radius,
    this.color = AppColors.textMuted,
    this.strokeWidth = 1.5,
    super.key,
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(
        radius: radius,
        color: color,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  final double radius;
  final Color color;
  final double strokeWidth;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Riscas diagonais a 135° do "Indisponível", com contraste baixo para não
/// competir com os trabalhos.
class AgendaStripes extends StatelessWidget {
  const AgendaStripes({
    required this.child,
    required this.radius,
    this.stripeWidth = 9,
    this.background = AppColors.agendaNeutralSurface,
    this.stripe = AppColors.agendaStripe,
    super.key,
  });

  final Widget child;
  final double radius;
  final double stripeWidth;
  final Color background;
  final Color stripe;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _StripesPainter(
          stripeWidth: stripeWidth,
          background: background,
          stripe: stripe,
        ),
        child: child,
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter({
    required this.stripeWidth,
    required this.background,
    required this.stripe,
  });

  final double stripeWidth;
  final Color background;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;
    final step = stripeWidth * 2 * math.sqrt2;
    // Linhas a descer da esquerda para a direita (135°), a cobrir a caixa.
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) =>
      old.stripeWidth != stripeWidth ||
      old.background != background ||
      old.stripe != stripe;
}
