import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/client_create_job_wizard_provider.dart';

const _maximumPhotos = 2;
const _maximumDescriptionLength = 500;
const _minimumDescriptionLength = 10;

/// Passo 3/4 de "Criar pedido" — descrição e fotos.
///
/// Já não publica diretamente: guarda descrição + fotos no wizard provider
/// e avança para a revisão (passo 4), que é quem publica de facto.
class ClientCreateJobDescriptionScreen extends ConsumerStatefulWidget {
  const ClientCreateJobDescriptionScreen({super.key, this.fromReview = false});

  /// `true` quando alcançado via "Editar" a partir da revisão (passo 4) —
  /// ver nota em `client_create_job_service_screen.dart`.
  final bool fromReview;

  @override
  ConsumerState<ClientCreateJobDescriptionScreen> createState() {
    return _ClientCreateJobDescriptionScreenState();
  }
}

class _ClientCreateJobDescriptionScreenState
    extends ConsumerState<ClientCreateJobDescriptionScreen> {
  late final TextEditingController _descriptionController;
  late final List<File> _photos;

  @override
  void initState() {
    super.initState();
    final wizard = ref.read(clientCreateJobWizardProvider);
    _descriptionController = TextEditingController(text: wizard.description);
    _descriptionController.addListener(_handleDescriptionChanged);
    // Cópia mutável — `wizard.photos` é `const []` por omissão, e a lista
    // local precisa de suportar add/remove enquanto o utilizador edita.
    _photos = List<File>.from(wizard.photos);
  }

  void _handleDescriptionChanged() => setState(() {});

  @override
  void dispose() {
    _descriptionController.removeListener(_handleDescriptionChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maximumPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Câmara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (!mounted || picked == null) return;
    setState(() => _photos.add(File(picked.path)));
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  bool get _canContinue =>
      _descriptionController.text.trim().length >= _minimumDescriptionLength;

  void _continue() {
    if (!_canContinue) return;

    ref.read(clientCreateJobWizardProvider.notifier).setDescriptionAndPhotos(
          description: _descriptionController.text.trim(),
          photos: _photos,
        );

    if (widget.fromReview) {
      context.pop();
    } else {
      context.push('/client/create-job/review');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final descriptionLength = _descriptionController.text.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: Text(
          'Criar pedido',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: AppStepProgress(currentStep: 3, totalSteps: 4),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: Text(
                      'Descreva o que precisa',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 1,
                    child: AppTextField(
                      controller: _descriptionController,
                      label: 'Descrição',
                      minLines: 5,
                      maxLines: 7,
                      textInputAction: TextInputAction.newline,
                      maxLength: _maximumDescriptionLength,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$descriptionLength/$_maximumDescriptionLength',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (descriptionLength > 0 &&
                      descriptionLength < _minimumDescriptionLength) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'A descrição deve ter pelo menos '
                      '$_minimumDescriptionLength caracteres.',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 2,
                    child: Text(
                      'Adicione até $_maximumPhotos fotos (opcional)',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 3,
                    child: _PhotosRow(
                      photos: _photos,
                      maximumPhotos: _maximumPhotos,
                      onAddPhoto: _addPhoto,
                      onRemovePhoto: _removePhoto,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 4,
                    child: const _PrivacyNotice(),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: PrimaryActionButton(
              label: 'Continuar',
              onPressed: _canContinue ? _continue : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotosRow extends StatelessWidget {
  const _PhotosRow({
    required this.photos,
    required this.maximumPhotos,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final List<File> photos;
  final int maximumPhotos;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (var index = 0; index < photos.length; index++)
          _PhotoPreview(
            file: photos[index],
            onRemove: () => onRemovePhoto(index),
          ),
        if (photos.length < maximumPhotos) _AddPhotoButton(onPressed: onAddPhoto),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              onPressed: onRemove,
              tooltip: 'Remover foto',
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.surface,
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.primary),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Adicionar',
                style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Só jardineiros na tua zona poderão ver o teu pedido.',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.primaryPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
