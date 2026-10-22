import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/direct_request_auth_context.dart';
import '../../worker/application/worker_providers.dart';
import '../application/client_create_job_wizard_provider.dart';
import '../application/job_request_form.dart';

/// "Pedir orçamento a Rui" no cartão público (A7): abre o wizard de criar
/// pedido no passo 1, com o pedido a ir primeiro para este jardineiro.
/// Mesmo mecanismo do "Pedir de novo" (0057); o servidor marca a origem
/// `public_card` e valida o jardineiro.
void startCardDirectRequest(
  BuildContext context,
  WidgetRef ref, {
  required String workerId,
  required String workerName,
  String workerAvatarUrl = '',
  String? visitId,
}) {
  // Liga a visita (QR/link) a esta conta. Não bloqueia: falhar aqui só
  // tira um número às estatísticas.
  if (visitId != null) {
    unawaited(ref.read(workerRepositoryProvider).claimCardVisit(visitId));
  }
  final current = ref.read(clientCreateJobWizardProvider);
  final draft = cardRequestWizardState(
    current,
    workerId: workerId,
    workerName: workerName,
    workerAvatarUrl: workerAvatarUrl,
    visitId: visitId,
  );
  ref.read(clientCreateJobWizardProvider.notifier).startFrom(draft);
  context.push('/client/create-job');
}

/// Depois de entrar ou criar conta a partir do cartão: volta ao pedido para
/// aquele jardineiro, uma vez só. `false` se não havia nada pendente.
Future<bool> resumePendingCardRequest(
  BuildContext context,
  WidgetRef ref,
) async {
  DirectRequestAuthContext? pending;
  try {
    pending = await ref.read(directRequestAuthProvider.notifier).take();
  } catch (_) {
    pending = null;
  }
  if (pending == null || !pending.isFresh(DateTime.now())) return false;
  if (!context.mounted) return false;
  startCardDirectRequest(
    context,
    ref,
    workerId: pending.workerId,
    workerName: pending.workerName,
    workerAvatarUrl: pending.workerAvatarUrl,
    visitId: pending.visitId,
  );
  return true;
}
