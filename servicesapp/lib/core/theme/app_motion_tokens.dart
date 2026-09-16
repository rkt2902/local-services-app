import 'package:flutter/material.dart';

/// Tokens de duração — docs/motion_spec.md secção 1.
///
/// Cobrem as durações partilhadas entre componentes. Durações
/// "assinatura" de um único componente (pulso da timeline 1.8s, shimmer
/// 1.3s, avanço da timeline 1s) ficam locais a esse componente — a
/// especificação trata-as como valores bespoke, não tokens partilhados.
abstract final class AppMotionDuration {
  const AppMotionDuration._();
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration screen = Duration(milliseconds: 300);
  static const Duration sheet = Duration(milliseconds: 450);
  static const Duration stagger = Duration(milliseconds: 120);
}

/// Tokens de curva — docs/motion_spec.md secção 2.
abstract final class AppMotionCurve {
  const AppMotionCurve._();
  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.2, 0.7, 0.3, 1);
  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve reward = Cubic(0.2, 0.8, 0.3, 1.2); // só sucesso e estrelas — nunca noutro sítio
}
