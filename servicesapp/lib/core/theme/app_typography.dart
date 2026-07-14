import 'package:flutter/material.dart';

abstract final class AppTypography {
  const AppTypography._();

  static const TextStyle display = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const TextStyle title = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 19,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'Plus Jakarta Sans',
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
}
