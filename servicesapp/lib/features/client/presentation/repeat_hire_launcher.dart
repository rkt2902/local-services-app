import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/data/job_model.dart';
import '../application/client_create_job_wizard_provider.dart';
import '../application/client_providers.dart';
import '../application/job_request_form.dart';
import 'widgets/direct_request_info_sheet.dart';

/// "Pedir de novo" (design A5), igual a partir do detalhe de um trabalho
/// concluído e de "Os teus jardineiros": na primeira vez explica como
/// funciona, depois abre o wizard de criar pedido com os dados de
/// [sourceJob] e o jardineiro guardado no rascunho.
Future<void> startRepeatHire(
  BuildContext context,
  WidgetRef ref, {
  required JobRequest sourceJob,
  required String workerName,
  String workerAvatarUrl = '',
}) async {
  final userId = ref.read(currentUserIdProvider);
  final prefs = ref.read(directRequestPrefsProvider);

  var infoHidden = false;
  if (userId != null) {
    try {
      infoHidden = await prefs.isInfoHidden(userId);
    } catch (_) {
      infoHidden = false;
    }
  }
  if (!context.mounted) return;

  final name = firstNameOr(workerName, 'o jardineiro');
  if (!infoHidden) {
    final confirmed = await showDirectRequestInfoSheet(
      context: context,
      data: DirectRequestInfoSheetViewData(
        titleLabel: 'Como funciona',
        descriptionLabel:
            'O pedido vai primeiro para $name, com os dados do último '
            'trabalho. Só escolhes a data. Durante 24 horas só $name vê o '
            'pedido e pode enviar proposta. Se não puder ou não responder, '
            'mostramos o pedido aos outros jardineiros da zona.',
        confirmActionLabel: 'Continuar',
        hideAgainLabel: 'Não voltar a mostrar',
      ),
      onConfirm: (doNotShowAgain) async {
        if (!doNotShowAgain || userId == null) return null;
        try {
          await prefs.hideInfo(userId);
          return null;
        } catch (_) {
          return 'Não foi possível guardar esta preferência. Tenta novamente.';
        }
      },
    );
    if (confirmed != true || !context.mounted) return;
  }

  final serviceTypes = ref.read(serviceTypesProvider).asData?.value ?? const [];
  final draft = repeatHireWizardState(
    sourceJob,
    workerName: workerName,
    workerAvatarUrl: workerAvatarUrl,
    now: DateTime.now(),
    // Catálogo ainda por carregar: assume que o serviço continua a existir.
    serviceStillOffered: serviceTypes.isEmpty ||
        serviceTypes.any((s) => s.id == sourceJob.serviceTypeId),
  );
  ref.read(clientCreateJobWizardProvider.notifier).startFrom(draft);
  context.push(repeatHireFirstRoute(draft));
}
