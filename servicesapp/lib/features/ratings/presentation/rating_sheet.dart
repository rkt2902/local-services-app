import 'package:flutter/material.dart';

import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/rating_stars_input.dart';

/// Shows a modal bottom sheet for star rating + optional comment.
/// Returns `true` if the user submitted, `null`/`false` if dismissed.
Future<bool?> showRatingSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Future<void> Function(int stars, String? comment) onSubmit,
}) async {
  final scaffold = ScaffoldMessenger.of(context);
  int selectedStars = 0;
  final commentController = TextEditingController();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      bool submitting = false;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final inset = MediaQuery.viewInsetsOf(ctx).bottom;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, inset + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: Theme.of(ctx).textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  RatingStarsInput(
                    rating: selectedStars,
                    onChanged: (value) =>
                        setSheetState(() => selectedStars = value),
                  ),
                  AnimatedSwitcher(
                    duration: MediaQuery.maybeOf(ctx)?.disableAnimations ?? false
                        ? Duration.zero
                        : AppMotionDuration.fast,
                    child: selectedStars > 0
                        ? Text(
                            _starLabel(selectedStars),
                            key: ValueKey(selectedStars),
                            textAlign: TextAlign.center,
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .primary),
                          )
                        : const SizedBox(height: 16, key: ValueKey(0)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comentário (opcional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (submitting || selectedStars == 0)
                        ? null
                        : () async {
                            setSheetState(() => submitting = true);
                            try {
                              final raw =
                                  commentController.text.trim();
                              await onSubmit(selectedStars,
                                  raw.isEmpty ? null : raw);
                              if (ctx.mounted) {
                                Navigator.pop(ctx, true);
                              }
                            } catch (e) {
                              setSheetState(
                                  () => submitting = false);
                              if (ctx.mounted) {
                                scaffold.showSnackBar(SnackBar(
                                  content: Text(friendlyError(e)),
                                  backgroundColor:
                                      Theme.of(ctx).colorScheme.error,
                                ));
                              }
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Text('Enviar avaliação'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  commentController.dispose();
  return result;
}

String _starLabel(int stars) => switch (stars) {
      1 => 'Muito mau',
      2 => 'Mau',
      3 => 'Satisfatório',
      4 => 'Bom',
      _ => 'Excelente',
    };
