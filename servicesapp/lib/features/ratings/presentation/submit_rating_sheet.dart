import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/rating_stars_input.dart';
import '../../../core/widgets/app_toast.dart';

/// Shows a modal bottom sheet for star rating + optional comment.
/// Returns `true` if the user submitted, `null`/`false` if dismissed.
///
/// Segue o padrão T4 já estabelecido no projeto para submissões (ver
/// decisions_log.md, "pop → go → snackBar → invalidate"): a sheet fecha-se
/// a si própria e mostra a confirmação — o caller só invalida os
/// providers relevantes depois de `showSubmitRatingSheet` devolver `true`, nunca
/// antes. Isto também evita invalidar um provider que o ecrã por trás da
/// sheet ainda esteja a observar em pleno fecho da modal.
Future<bool?> showSubmitRatingSheet({
  required BuildContext context,
  required String title,
  required String successMessage,
  String? subtitle,
  required Future<void> Function(int stars, String? comment) onSubmit,
}) async {
  final toast = AppToast.of(context);
  final result = await AppSheet.show<bool>(
    context,
    builder: (_) => _SubmitRatingSheet(
      title: title,
      subtitle: subtitle,
      onSubmit: onSubmit,
    ),
  );

  if (result == true && context.mounted) {
    toast.show(successMessage);
  }

  return result;
}

/// Estado próprio (e não um `StatefulBuilder`): o controlador do comentário
/// só é libertado quando a folha sai da árvore, depois da animação de
/// fecho, e não logo que `AppSheet.show` devolve.
class _SubmitRatingSheet extends StatefulWidget {
  const _SubmitRatingSheet({
    required this.title,
    required this.onSubmit,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Future<void> Function(int stars, String? comment) onSubmit;

  @override
  State<_SubmitRatingSheet> createState() => _SubmitRatingSheetState();
}

class _SubmitRatingSheetState extends State<_SubmitRatingSheet> {
  final _commentController = TextEditingController();
  int _stars = 0;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final raw = _commentController.text.trim();
      await widget.onSubmit(_stars, raw.isEmpty ? null : raw);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Erro dentro da folha: um aviso ficava escondido por trás.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final subtitle = widget.subtitle;

    return AppSheet(
      title: widget.title,
      onClose: () => Navigator.pop(context),
      isSubmitting: _submitting,
      primaryActionLabel: 'Enviar avaliação',
      onPrimaryAction: _stars == 0 ? null : _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null)
            Text(
              subtitle,
              style: textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                RatingStarsInput(
                  rating: _stars,
                  onChanged: (value) => setState(() => _stars = value),
                ),
                const SizedBox(height: AppSpacing.xs),
                AnimatedSwitcher(
                  duration:
                      disableAnimations ? Duration.zero : AppMotionDuration.fast,
                  child: Text(
                    _stars > 0
                        ? _starLabel(_stars)
                        : 'Toca nas estrelas para dar a nota',
                    key: ValueKey(_stars),
                    textAlign: TextAlign.center,
                    style: _stars > 0
                        ? textTheme.titleSmall
                            ?.copyWith(color: AppColors.primary)
                        : textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _commentController,
            label: 'Comentário (opcional)',
            hintText: 'Como correu o trabalho?',
            minLines: 3,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorText!,
              style: textTheme.bodySmall?.copyWith(
                color: AppStatusColor.cancelled.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _starLabel(int stars) => switch (stars) {
      1 => 'Muito mau',
      2 => 'Mau',
      3 => 'Satisfatório',
      4 => 'Bom',
      _ => 'Excelente',
    };
