import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Resultado da folha "Marcar como concluído": confirmado, com ou sem foto.
class MarkCompletedResult {
  const MarkCompletedResult({this.photo});

  final File? photo;
}

/// Folha de confirmação antes de `mark_job_done`. A foto é opcional e
/// serve de prova para o cliente, que continua a ter de confirmar.
/// Devolve `null` se o worker cancelar.
class MarkCompletedSheet extends StatefulWidget {
  const MarkCompletedSheet({super.key});

  static Future<MarkCompletedResult?> show(BuildContext context) {
    return showModalBottomSheet<MarkCompletedResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (_) => const MarkCompletedSheet(),
    );
  }

  @override
  State<MarkCompletedSheet> createState() => _MarkCompletedSheetState();
}

class _MarkCompletedSheetState extends State<MarkCompletedSheet> {
  File? _photo;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    setState(() => _photo = File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photo = _photo;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marcar como concluído',
              style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'O cliente vai ser avisado para confirmar. Junta uma foto do '
              'trabalho feito, se puderes.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFadeThroughSwitcher(
              switchKey: photo?.path ?? 'no-photo',
              child: photo == null
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pick(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tirar foto'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          child: Image.file(
                            photo,
                            width: AppSpacing.xl * 2,
                            height: AppSpacing.xl * 2,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Foto adicionada',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _photo = null),
                          child: const Text('Remover'),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryActionButton(
              label: photo == null ? 'Concluir sem foto' : 'Concluir com foto',
              onPressed: () => Navigator.of(context)
                  .pop(MarkCompletedResult(photo: photo)),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
