import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/price_labels.dart';
import '../data/direct_request_models.dart';
import '../data/job_model.dart';

// Textos do pedido direto ("Pedir de novo", design A5). Funções puras: o
// servidor decide o estado e o prazo, aqui só se escreve o que ele disse.
// Sem artigo antes do nome ("a Rui", não "ao Rui"): a app não sabe o
// género de quem tem cada nome.

/// Primeiro nome, ou [fallback] sem nome.
String firstNameOr(String fullName, String fallback) {
  final first = fullName.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? fallback : first;
}

/// Inicial para o avatar sem foto.
String initialOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty
      ? ''
      : String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// O cartão "Precisas outra vez?" só aparece com 4 ou 5 estrelas, ou ainda
/// sem avaliação.
bool showRepeatHire(RepeatHireInfo info) =>
    info.myStars == null || info.myStars! >= 4;

/// "23/10 às 14:30", na hora local.
String directDeadlineLabel(DateTime until) =>
    DateFormat("dd/MM 'às' HH:mm").format(until.toLocal());

/// "faltam 18 h" para a etiqueta do jardineiro. Só texto: a etiqueta
/// some quando o servidor muda o estado.
String directTimeLeftLabel(DateTime until, DateTime now) {
  final minutes = until.difference(now).inMinutes;
  if (minutes < 60) return 'falta menos de 1 h';
  final hours = minutes ~/ 60;
  return hours == 1 ? 'falta 1 h' : 'faltam $hours h';
}

/// "há 3 semanas" para "Os teus jardineiros".
String timeAgoLabel(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  if (days < 7) return 'há $days dias';
  if (days < 30) {
    final weeks = days ~/ 7;
    return weeks == 1 ? 'há 1 semana' : 'há $weeks semanas';
  }
  if (days < 365) {
    final months = days ~/ 30;
    return months == 1 ? 'há 1 mês' : 'há $months meses';
  }
  final years = days ~/ 365;
  return years == 1 ? 'há 1 ano' : 'há $years anos';
}

/// Faixa do detalhe do pedido aberto, do lado do cliente.
enum DirectBannerKind { waiting, released, onHold }

typedef DirectBannerTexts = ({
  DirectBannerKind kind,
  String title,
  String description,
});

/// `null` quando não há faixa: pedido normal, já não aberto, ou aberto a
/// todos pelo próprio cliente.
DirectBannerTexts? directBannerTexts(JobRequest job, {required String workerName}) {
  if (job.status != JobStatus.open) return null;
  final name = firstNameOr(workerName, 'O jardineiro');
  switch (job.directStatus) {
    case DirectRequestStatus.waiting:
      final until = job.directUntil;
      return (
        kind: DirectBannerKind.waiting,
        title: until == null
            ? 'À espera de $name'
            : 'À espera de $name até ${directDeadlineLabel(until)}',
        // Durante a reserva só o jardineiro escolhido pode propor.
        description: job.proposalCount > 0
            ? '$name já enviou proposta. Por agora só $name vê o pedido.'
            : 'Por agora só $name vê o pedido.',
      );
    case DirectRequestStatus.onHold:
      // Interruptor desligado no passo 4 (pedido pelo cartão, 0059): o
      // pedido fica parado até o cliente decidir.
      return (
        kind: DirectBannerKind.onHold,
        title: job.directHoldReason == 'declined'
            ? '$name não pode desta vez'
            : '$name não respondeu a tempo',
        description:
            'O pedido está parado. Queres mostrá-lo a outros jardineiros?',
      );
    case DirectRequestStatus.declined:
      return (
        kind: DirectBannerKind.released,
        title: '$name não pode desta vez',
        description: 'O pedido já está visível para todos os jardineiros.',
      );
    case DirectRequestStatus.expired:
      return (
        kind: DirectBannerKind.released,
        title: job.proposalCount > 0
            ? 'Passaram as 24 horas'
            : '$name não respondeu a tempo',
        description: 'O pedido já está visível para todos os jardineiros.',
      );
    case DirectRequestStatus.released:
    case null:
      return null;
  }
}

/// "Já trabalhaste com Marta a 12/09/2026, Corte de relva, 12 €/h".
String directHistoryLabel(
  DirectRequestContext context, {
  required String serviceLabel,
}) {
  final name = firstNameOr(context.clientName, 'este cliente');
  final parts = <String>[
    if (context.jobDate != null)
      DateFormat('dd/MM/yyyy').format(context.jobDate!),
    if (serviceLabel.isNotEmpty) serviceLabel,
    if (context.hourlyRate != null && context.hourlyRate! > 0)
      hourlyRateLabel(context.hourlyRate!),
  ];
  if (parts.isEmpty) return 'Já trabalhaste com $name.';
  final first = context.jobDate != null ? ' a ${parts.first}' : ', ${parts.first}';
  final rest = parts.skip(1).map((p) => ', $p').join();
  return 'Já trabalhaste com $name$first$rest.';
}

/// Botão do rodapé do cartão público: "Pedir orçamento a Rui".
String cardDirectRequestActionLabel(String workerName) =>
    'Pedir orçamento a ${firstNameOr(workerName, 'este jardineiro')}';

/// "Fora da tua área, a 12 km" no cartão do pedido pelo cartão.
String outsideAreaLabel(double distanceKm) =>
    'Fora da tua área, a ${distanceKm.round()} km';

/// Interruptor do passo 4 (A7): o texto muda com o valor.
const directReleaseOptionTitle = 'Se não puder, mostrar a outros jardineiros';

String directReleaseOptionDescription(String name, {required bool autoRelease}) =>
    autoRelease
        ? 'Se $name não puder ou não responder a tempo, o pedido fica '
            'logo visível para todos.'
        : 'Se $name não puder ou não responder a tempo, o pedido fica '
            'parado e decides tu.';
