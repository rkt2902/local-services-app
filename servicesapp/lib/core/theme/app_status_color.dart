import 'package:flutter/material.dart';

enum AppStatusColor {
  waiting,
  success,
  inProgress,
  cancelled;

  Color get background {
    switch (this) {
      case AppStatusColor.waiting:
        return const Color(0xFFFCEFD8);
      case AppStatusColor.success:
        return const Color(0xFFE1F0DC);
      case AppStatusColor.inProgress:
        return const Color(0xFFE1E9F7);
      case AppStatusColor.cancelled:
        return const Color(0xFFF8E1E1);
    }
  }

  Color get foreground {
    switch (this) {
      case AppStatusColor.waiting:
        return const Color(0xFFB27A13);
      case AppStatusColor.success:
        return const Color(0xFF2E7D32);
      case AppStatusColor.inProgress:
        return const Color(0xFF4D6FB7);
      case AppStatusColor.cancelled:
        return const Color(0xFFC0392B);
    }
  }
}
