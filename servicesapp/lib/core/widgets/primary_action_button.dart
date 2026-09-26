import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_radius.dart';

class PrimaryActionButton extends StatefulWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;

  @override
  State<PrimaryActionButton> createState() => _PrimaryActionButtonState();
}

// Feedback de toque (docs/motion_spec.md §3, "Botão primário": ripple M3 +
// scale(0.96) enquanto premido, tokens `instant · standard`) — sempre ativo,
// mesmo com reduced motion: é a categoria "Feedback de toque" do §5, que a
// spec lista em "Animar sempre", não nas exceções de redução de movimento.
class _PrimaryActionButtonState extends State<PrimaryActionButton> {
  static const double _pressedScale = 0.96;

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bool disabled = widget.onPressed == null || widget.isLoading;

    // Listener em vez de GestureDetector: só observa eventos de ponteiro
    // crus, sem entrar na arena de gestos — o tap do FilledButton continua a
    // ser o único reconhecedor de toque, sem risco de competição/perda de
    // eventos nos ~30 sítios que usam este botão.
    return Listener(
      onPointerDown: disabled ? null : (_) => _setPressed(true),
      onPointerUp: disabled ? null : (_) => _setPressed(false),
      onPointerCancel: disabled ? null : (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !disabled ? _pressedScale : 1,
        duration: AppMotionDuration.instant,
        curve: AppMotionCurve.standard,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: FilledButton(
            onPressed: disabled ? null : widget.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.textSecondary.withValues(alpha: 0.4),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              textStyle: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
              ),
            ),
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(widget.label),
          ),
        ),
      ),
    );
  }
}
