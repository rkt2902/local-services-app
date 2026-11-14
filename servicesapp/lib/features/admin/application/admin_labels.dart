import 'package:intl/intl.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_status_color.dart';
import '../data/admin_support_models.dart';

/// "83%" (arredondado) ou "—" sem base.
String adminPercentLabel(int part, int total) {
  if (total <= 0) return '—';
  return '${(part * 100 / total).round()}%';
}

/// "3,5 h" ou "—".
String adminHoursLabel(double? hours) {
  if (hours == null) return '—';
  return '${NumberFormat('0.#', 'pt_PT').format(hours)} h';
}

/// "1 250 €".
String adminEuroLabel(double value) =>
    '${NumberFormat.decimalPattern('pt_PT').format(value.round())} €';

/// "4,8" ou "—".
String adminRatingLabel(double? rating) {
  if (rating == null) return '—';
  return NumberFormat('0.0', 'pt_PT').format(rating);
}

/// "hoje", "ontem", "há 5 dias", "há 3 meses" ou "nunca".
String adminRelativeDateLabel(DateTime? date, {DateTime? now}) {
  if (date == null) return 'nunca';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final local = date.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  if (days < 60) return 'há $days dias';
  return 'há ${(days / 30).floor()} meses';
}

/// "22/10/2026" ou "—".
String adminDateLabel(DateTime? date) =>
    date == null ? '—' : DateFormat('dd/MM/yyyy').format(date);

const _monthShortNames = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `2026-10` → "out".
String adminMonthShortLabel(String yearMonth) {
  final parts = yearMonth.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return yearMonth;
  return _monthShortNames[month - 1];
}

/// Tom do selo do plano no painel.
AppStatusColor adminTierStatusColor(WorkerPlanTier tier) => switch (tier) {
  WorkerPlanTier.free => AppStatusColor.neutral,
  WorkerPlanTier.pro => AppStatusColor.success,
  WorkerPlanTier.proPlus => AppStatusColor.info,
};

// ── Suporte, fase A ───────────────────────────────────────────────

/// Id curto como aparece nos emails de suporte: "#4f8f1350".
String adminShortId(String id) => '#${id.length > 8 ? id.substring(0, 8) : id}';

/// "13/11/2026 20:14" (hora deste computador, que é a de Portugal).
String adminDateTimeLabel(DateTime? date) =>
    date == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());

/// Tempo que falta até [target]: "faltam 3 h", "faltam 2 dias",
/// "passou há 5 h". `null` sem data.
String? adminCountdownLabel(DateTime? target, {DateTime? now}) {
  if (target == null) return null;
  final diff = target.difference(now ?? DateTime.now());
  final abs = diff.abs();
  final text = abs.inHours < 1
      ? '${abs.inMinutes} min'
      : abs.inHours < 48
      ? '${abs.inHours} h'
      : '${abs.inDays} dias';
  return diff.isNegative ? 'passou há $text' : 'faltam $text';
}

/// "18:00" a partir de "18:00:00".
String adminTimeLabel(String? time) {
  if (time == null || time.length < 5) return time ?? '';
  return time.substring(0, 5);
}

/// Quem fez um evento da linha do tempo.
String adminActorLabel(AdminActorKind kind, String? name) {
  final role = switch (kind) {
    AdminActorKind.client => 'Cliente',
    AdminActorKind.worker => 'Jardineiro',
    AdminActorKind.helper => 'Ajudante',
    AdminActorKind.admin => 'Admin',
    AdminActorKind.system => 'Sistema',
    AdminActorKind.user => 'Utilizador',
  };
  if (name == null || kind == AdminActorKind.system) return role;
  return '$role · $name';
}

/// Texto de um evento de `job_events` (ou ação de admin).
String adminJobEventLabel(String type, Map<String, dynamic> data) {
  final day = data['day'];
  return switch (type) {
    'created' =>
      data['reopened_from'] != null
          ? 'Pedido reaberto'
          : (data['direct'] == true ? 'Pedido direto criado' : 'Pedido criado'),
    'proposal_sent' => 'Proposta enviada',
    'proposal_rejected' => 'Proposta recusada',
    'proposal_withdrawn' => 'Proposta retirada',
    'proposal_closed' => 'Proposta fechada',
    'accepted' => 'Proposta aceite',
    'started' => 'Trabalho iniciado',
    'day_started' => 'Dia ${day ?? ''} começado',
    'day_ended' => 'Dia ${day ?? ''} terminado',
    'marked_done' => 'Marcado como concluído',
    'completed' => 'Confirmado como concluído',
    'cancelled' => 'Cancelado',
    'expired' => 'Expirou sem resposta',
    'status_changed' => 'Estado mudou de ${data['from']} para ${data['to']}',
    'date_changed' => 'Data marcada mudou',
    'reschedule_pending' => 'Pedido de remarcação',
    'reschedule_accepted' => 'Remarcação aceite',
    'reschedule_rejected' => 'Remarcação recusada',
    'search_widened' => 'Mostrado mais longe (+${data['extra_km']} km)',
    'direct_waiting' => 'Reserva de 24 horas ao jardineiro',
    'direct_declined' => 'Jardineiro recusou o pedido direto',
    'direct_expired' => 'Reserva de 24 horas acabou',
    'direct_released' => 'Pedido direto aberto a todos',
    'direct_on_hold' => 'Pedido direto à espera da cliente',
    'photos_before' => 'Fotos de antes (${data['count']})',
    'photos_after' => 'Fotos de depois (${data['count']})',
    'reported' => 'Problema reportado',
    'rated' => 'Avaliação (${data['stars']} ★)',
    'help_requested' => 'Pedido de ajuda (${data['slots']} vagas)',
    'help_open' => 'Pedido de ajuda aberto',
    'help_filled' => 'Equipa completa',
    'help_cancelled' => 'Pedido de ajuda cancelado',
    'help_pending_approval' => 'Pedido de ajuda à espera da cliente',
    'admin_view_job_photos' => 'Admin viu as fotos',
    'admin_reveal_address' => 'Admin viu a morada',
    _ => type.startsWith('admin_') ? 'Admin: ${type.substring(6)}' : type,
  };
}

/// Estado de uma proposta na ficha do pedido.
(String, AppStatusColor) adminProposalStatus(String status, bool accepted) {
  if (accepted) return ('Aceite', AppStatusColor.success);
  return switch (status) {
    'pending' => ('Pendente', AppStatusColor.waiting),
    'accepted' => ('Aceite', AppStatusColor.success),
    'rejected' => ('Recusada', AppStatusColor.cancelled),
    'superseded' => ('Fechada ou retirada', AppStatusColor.neutral),
    _ => (status, AppStatusColor.neutral),
  };
}

/// Estado de um pedido de ajuda ou de uma candidatura.
(String, AppStatusColor) adminHelpStatus(String status) => switch (status) {
  'pending_approval' => ('À espera da cliente', AppStatusColor.waiting),
  'open' => ('Aberto', AppStatusColor.info),
  'filled' => ('Completo', AppStatusColor.success),
  'pending' => ('Candidato', AppStatusColor.waiting),
  'accepted' => ('Aceite', AppStatusColor.success),
  'rejected' => ('Recusado', AppStatusColor.cancelled),
  'cancelled' => ('Cancelado', AppStatusColor.neutral),
  _ => (status, AppStatusColor.neutral),
};

/// Ação no histórico de admin de uma ficha.
String adminHistoryActionLabel(String action) => switch (action) {
  'reveal_phone' => 'Telefone revelado',
  'reveal_address' => 'Morada revelada',
  'set_worker_plan' => 'Plano alterado',
  'view_worker' => 'Ficha aberta',
  _ => action,
};
