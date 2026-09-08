import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../data/fleet_card_text_extractor.dart';

/// Passo 1 — tira/escolhe uma foto do cartão, corre OCR local
/// (`FleetCardTextExtractor`) e navega para o ecrã de confirmação com os
/// campos extraídos. A foto nunca é guardada — `extract()` apaga o
/// ficheiro temporário do image_picker assim que o OCR termina, sucesso
/// ou falha, antes deste ecrã sequer navegar.
class FleetCardScanScreen extends ConsumerStatefulWidget {
  const FleetCardScanScreen({super.key});

  @override
  ConsumerState<FleetCardScanScreen> createState() => _FleetCardScanScreenState();
}

class _FleetCardScanScreenState extends ConsumerState<FleetCardScanScreen> {
  bool _processing = false;

  Future<void> _pickAndExtract(ImageSource source) async {
    if (_processing) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (!mounted || picked == null) return;

    setState(() => _processing = true);
    try {
      final extracted =
          await const FleetCardTextExtractor().extract(File(picked.path));
      if (!mounted) return;
      final params = {
        'barcode': extracted.barcodeValue ?? '',
        'cardNumber': extracted.cardNumber ?? '',
        'holderName': extracted.holderName ?? '',
        'barcodeWasRead': extracted.barcodeWasRead.toString(),
      };
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      context.push('/worker/fleet-card/confirm?$query');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _processing ? null : () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Cartão frota',
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _processing
                  ? const _ProcessingState()
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.local_gas_station_outlined,
                              color: AppColors.primary,
                              size: 46,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Fotografe o seu cartão frota',
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Tenta incluir o número do cartão e o código de '
                            'barras numa única foto, com boa luz e sem reflexos.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryActionButton(
                            label: 'Tirar foto',
                            onPressed: () => _pickAndExtract(ImageSource.camera),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _pickAndExtract(ImageSource.gallery),
                              icon: const Icon(Icons.photo_outlined, color: AppColors.primary),
                              label: Text(
                                'Escolher da galeria',
                                style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                side: const BorderSide(color: AppColors.divider),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.input),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'A foto é usada só para ler o cartão neste momento — '
                            'não é guardada nem enviada para lado nenhum.',
                            textAlign: TextAlign.center,
                            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingState extends StatelessWidget {
  const _ProcessingState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'A processar imagem...',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
