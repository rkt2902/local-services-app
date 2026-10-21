import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';

/// Aviso curto no topo do ecrã, em vez da SnackBar do Material (que fica
/// sempre em baixo, por cima dos botões de ação e da bottom nav).
///
/// Uso igual ao do `ScaffoldMessenger`: guardar o handle ANTES de navegar
/// ou de um `await` (regra T4: navegar → aviso → invalidar), e mostrar
/// depois, mesmo que o ecrã de origem já tenha saído:
///
/// ```dart
/// final toast = AppToast.of(context);
/// router.go('/client/jobs');
/// toast.show('Pedido cancelado.');
/// ```
///
/// Vive no `Overlay` do navigator raiz, por isso sobrevive a `go`/`pop` e
/// fica por cima de diálogos e folhas. Um aviso novo substitui o anterior.
///
/// [notification] é a mesma peça com título, para as notificações que
/// chegam com a app aberta (o push do sistema não aparece nesse caso).
class AppToast {
  AppToast._(this._overlay);

  final OverlayState _overlay;

  static OverlayEntry? _current;

  static AppToast of(BuildContext context) =>
      AppToast._(Overlay.of(context, rootOverlay: true));

  static AppToast? maybeOf(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    return overlay == null ? null : AppToast._(overlay);
  }

  /// Confirmação ou informação (verde).
  void show(String message) => _show(
        message: message,
        icon: Icons.check_circle_outline_rounded,
        color: AppStatusColor.success,
      );

  /// Falha (vermelho).
  void error(String message) => _show(
        message: message,
        icon: Icons.error_outline_rounded,
        color: AppStatusColor.cancelled,
      );

  /// Notificação que chega com a app aberta: título, texto e o ícone/tom
  /// do tipo (`notificationLook`). Tocar chama [onTap] e fecha o aviso.
  void notification({
    required String title,
    required String body,
    required IconData icon,
    required AppStatusColor color,
    VoidCallback? onTap,
  }) =>
      _show(
        title: title,
        message: body,
        icon: icon,
        color: color,
        onTap: onTap,
      );

  void _show({
    String? title,
    required String message,
    required IconData icon,
    required AppStatusColor color,
    VoidCallback? onTap,
  }) {
    if (!_overlay.mounted) return;
    _removeCurrent();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastHost(
        key: UniqueKey(),
        title: title,
        message: message,
        icon: icon,
        color: color,
        onTap: onTap,
        onDismissed: () {
          if (_current == entry) _removeCurrent();
        },
      ),
    );
    _current = entry;
    _overlay.insert(entry);
  }

  static void _removeCurrent() {
    final entry = _current;
    _current = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

/// Tempo visível, igual ao default da SnackBar que substitui.
const _visibleFor = Duration(seconds: 4);

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    super.key,
    this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.onTap,
    required this.onDismissed,
  });

  final String? title;
  final String message;
  final IconData icon;
  final AppStatusColor color;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotionDuration.screen,
    reverseDuration: AppMotionDuration.fast,
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.status == AnimationStatus.dismissed && !_closing) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      _timer ??= Timer(_visibleFor, _close);
    }
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _controller.reverse();
    }
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurve.emphasized,
      reverseCurve: AppMotionCurve.exit,
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.dialogMaxWidth,
              ),
              child: FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.6),
                    end: Offset.zero,
                  ).animate(curved),
                  child: Dismissible(
                    key: const ValueKey('app-toast'),
                    direction: DismissDirection.up,
                    onDismissed: (_) {
                      _closing = true;
                      _timer?.cancel();
                      widget.onDismissed();
                    },
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () {
                            widget.onTap?.call();
                            _close();
                          },
                          borderRadius:
                              BorderRadius.circular(AppRadius.card),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              border: Border.all(color: AppColors.divider),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.textPrimary
                                      .withValues(alpha: 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  widget.icon,
                                  color: widget.color.foreground,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: widget.title == null
                                      ? Text(
                                          widget.message,
                                          style: textTheme.bodyMedium
                                              ?.copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.title!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.titleSmall
                                                  ?.copyWith(
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xxs,
                                            ),
                                            Text(
                                              widget.message,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                color:
                                                    AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                                if (widget.onTap != null) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
