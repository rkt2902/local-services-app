import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/picked_photo.dart';

/// Máximo de fotos de "antes" e de "depois" (CHECK da migration 0052).
const int maxWorkPhotos = 3;

/// Fila de miniaturas com o quadrado "Adicionar" no fim, usada nas folhas
/// "Iniciar trabalho" (fotos de antes) e "Terminou o trabalho?" (fotos de
/// depois). Tocar numa miniatura remove-a.
class WorkPhotosStrip extends StatelessWidget {
  const WorkPhotosStrip({
    super.key,
    required this.photos,
    required this.onChanged,
    this.enabled = true,
  });

  final List<XFile> photos;
  final ValueChanged<List<XFile>> onChanged;
  final bool enabled;

  static const double _tileSize = AppSpacing.xl * 2;

  Future<void> _add(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeria'),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: webPickMaxWidth,
      imageQuality: webPickImageQuality,
    );
    if (picked == null) return;
    onChanged([...photos, picked]);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (var i = 0; i < photos.length; i++)
          Semantics(
            button: true,
            label: 'Remover foto ${i + 1}',
            child: GestureDetector(
              onTap: enabled
                  ? () => onChanged([...photos]..removeAt(i))
                  : null,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    child: Image(
                      image: pickedPhotoImage(photos[i]),
                      width: _tileSize,
                      height: _tileSize,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.xxs,
                    right: AppSpacing.xxs,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: AppSpacing.md,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (photos.length < maxWorkPhotos)
          Semantics(
            button: true,
            label: 'Adicionar foto',
            child: InkWell(
              onTap: enabled ? () => _add(context) : null,
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: Container(
                width: _tileSize,
                height: _tileSize,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Adicionar',
                      style: textTheme.labelMedium
                          ?.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
