import '../../../core/constants/enums.dart';
import '../data/job_model.dart';

/// Textos do cartão "Ainda sem propostas" (RC5, 0062) no detalhe de um
/// pedido aberto do cliente. Funções puras, testadas sem ecrã.
class NoProposalsHelpTexts {
  const NoProposalsHelpTexts({
    required this.title,
    required this.description,
    required this.widenActionLabel,
  });

  final String title;
  final String description;

  /// "Mostrar a jardineiros mais longe"; `null` quando já está no máximo.
  final String? widenActionLabel;
}

const noProposalsDateActionLabel = 'Alargar a data';
const noProposalsDescriptionActionLabel = 'Ajustar a descrição';

/// Só aparece depois do aviso das 24h (o servidor marca
/// `noProposalsNudgedAt`), com o pedido aberto a todos e sem propostas.
NoProposalsHelpTexts? noProposalsHelpTexts(JobRequest job) {
  if (job.status != JobStatus.open) return null;
  if (job.proposalCount > 0) return null;
  if (job.isDirectWaiting || job.isDirectOnHold) return null;
  if (job.noProposalsNudgedAt == null) return null;

  final extra = job.searchExtraKm;
  final canWiden = extra < JobRequest.maxSearchExtraKm;
  final reach = extra > 0
      ? 'Já mostrámos o pedido a jardineiros até $extra km mais longe. '
      : '';
  return NoProposalsHelpTexts(
    title: 'Ainda sem propostas',
    description:
        '${reach}Uma data mais flexível ou uma descrição com mais '
        'pormenores (tamanho, acesso, fotos) costuma trazer respostas.',
    widenActionLabel: canWiden ? 'Mostrar a jardineiros mais longe' : null,
  );
}

/// Aviso depois de "Mostrar a jardineiros mais longe".
String widenedSearchToast(int extraKm) =>
    'Pedido mostrado a jardineiros até $extraKm km mais longe.';
