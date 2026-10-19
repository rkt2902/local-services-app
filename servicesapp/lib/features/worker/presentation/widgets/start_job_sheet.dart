import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import 'work_photos_strip.dart';

/// Folha "Iniciar o trabalho agora?" (design 6b). Fotos de "antes"
/// opcionais. [onStart] faz o upload e chama `start_job`; devolve `true` só
/// depois de a BD confirmar, e aí a folha fecha com `true`. Com `false` a
/// folha fica aberta (o erro já foi mostrado por quem chamou).
class StartJobSheet extends StatefulWidget {
  const StartJobSheet({
    super.key,
    required this.clientName,
    required this.onStart,
  });

  final String clientName;
  final Future<bool> Function(List<XFile> photos) onStart;

  static Future<bool> show(
    BuildContext context, {
    required String clientName,
    required Future<bool> Function(List<XFile> photos) onStart,
  }) async {
    final started = await AppSheet.show<bool>(
      context,
      builder: (_) => StartJobSheet(clientName: clientName, onStart: onStart),
    );
    return started ?? false;
  }

  @override
  State<StartJobSheet> createState() => _StartJobSheetState();
}

class _StartJobSheetState extends State<StartJobSheet> {
  List<XFile> _photos = const [];
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    final ok = await widget.onStart(_photos);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final who = widget.clientName.trim().isEmpty
        ? 'O cliente'
        : widget.clientName.trim();

    return AppSheet(
      title: 'Iniciar o trabalho agora?',
      isSubmitting: _starting,
      onClose: () => Navigator.of(context).pop(false),
      primaryActionLabel: 'Iniciar trabalho',
      primaryActionIcon: Icons.play_arrow_rounded,
      onPrimaryAction: _start,
      secondaryActionLabel: 'Agora não',
      onSecondaryAction: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$who recebe um aviso de que começaste. O tempo de trabalho '
            'começa a contar.',
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            TextSpan(
              text: 'Fotos do "antes"',
              style:
                  textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              children: [
                TextSpan(
                  text: ' · opcional',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          WorkPhotosStrip(
            photos: _photos,
            enabled: !_starting,
            onChanged: (photos) => setState(() => _photos = photos),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Protegem-te em caso de reclamação.',
            style:
                textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
