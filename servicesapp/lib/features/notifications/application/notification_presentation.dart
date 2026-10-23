import 'package:flutter/material.dart';

import '../../../core/theme/app_status_color.dart';
import '../data/notification_model.dart';
import '../data/notification_types.dart';

/// Apresentação das notificações (design A4): ícone e tom por tipo, título
/// com o trabalho, secções por dia e o filtro "Trabalhos". Funções puras,
/// partilhadas pelos dois papéis.

/// Ícone e tom de cada tipo, pela legenda do design:
/// success (proposta, lembrete do dia, concluído), waiting (candidato, nova
/// data, por responder), info (editado, trabalho feito, pedido de ajuda),
/// cancelled (cancelado) e neutral (expirado, fechado, não escolhido).
({IconData icon, AppStatusColor tone}) notificationLook(String type) =>
    switch (type) {
      NotificationType.proposalReceived => (
          icon: Icons.request_quote_outlined,
          tone: AppStatusColor.success,
        ),
      NotificationType.proposalAccepted => (
          icon: Icons.check_circle_outline_rounded,
          tone: AppStatusColor.success,
        ),
      NotificationType.jobReminder => (
          icon: Icons.event_available_outlined,
          tone: AppStatusColor.success,
        ),
      NotificationType.jobCompleted || NotificationType.helpJobCompleted => (
          icon: Icons.verified_outlined,
          tone: AppStatusColor.success,
        ),
      NotificationType.helpAccepted => (
          icon: Icons.how_to_reg_outlined,
          tone: AppStatusColor.success,
        ),
      NotificationType.helpRequestApproved ||
      NotificationType.helpRequestAutoApproved =>
        (icon: Icons.groups_outlined, tone: AppStatusColor.success),
      NotificationType.helpCandidateApplied => (
          icon: Icons.person_search_outlined,
          tone: AppStatusColor.waiting,
        ),
      NotificationType.rescheduleProposed ||
      NotificationType.rescheduleAccepted ||
      NotificationType.helpJobRescheduled =>
        (icon: Icons.edit_calendar_outlined, tone: AppStatusColor.waiting),
      NotificationType.helpRequestClosingSoon => (
          icon: Icons.schedule_rounded,
          tone: AppStatusColor.waiting,
        ),
      NotificationType.helpWithdrew => (
          icon: Icons.person_remove_outlined,
          tone: AppStatusColor.waiting,
        ),
      NotificationType.jobUpdated => (
          icon: Icons.edit_note_rounded,
          tone: AppStatusColor.info,
        ),
      NotificationType.jobMarkedDone || NotificationType.helpJobDone => (
          icon: Icons.task_alt_rounded,
          tone: AppStatusColor.info,
        ),
      NotificationType.helpRequestPendingApproval => (
          icon: Icons.group_add_outlined,
          tone: AppStatusColor.info,
        ),
      NotificationType.jobStarted || NotificationType.helpJobStarted => (
          icon: Icons.play_circle_outline_rounded,
          tone: AppStatusColor.info,
        ),
      NotificationType.newJobInRadius => (
          icon: Icons.yard_outlined,
          tone: AppStatusColor.info,
        ),
      NotificationType.jobOpportunityReminder => (
          icon: Icons.notifications_active_outlined,
          tone: AppStatusColor.waiting,
        ),
      NotificationType.jobNoProposalsYet => (
          icon: Icons.travel_explore_rounded,
          tone: AppStatusColor.waiting,
        ),
      NotificationType.seasonalTip => (
          icon: Icons.eco_outlined,
          tone: AppStatusColor.info,
        ),
      NotificationType.directJobRequest => (
          icon: Icons.assignment_ind_outlined,
          tone: AppStatusColor.info,
        ),
      NotificationType.directRequestReleased => (
          icon: Icons.groups_outlined,
          tone: AppStatusColor.neutral,
        ),
      NotificationType.helpRequestReopened ||
      NotificationType.newHelpRequestInRadius =>
        (icon: Icons.group_add_outlined, tone: AppStatusColor.info),
      NotificationType.helpRequestClosed => (
          icon: Icons.groups_outlined,
          tone: AppStatusColor.neutral,
        ),
      NotificationType.jobReopened => (
          icon: Icons.replay_rounded,
          tone: AppStatusColor.info,
        ),
      NotificationType.rescheduleRejected => (
          icon: Icons.event_note_outlined,
          tone: AppStatusColor.info,
        ),
      NotificationType.jobCancelled || NotificationType.helpJobCancelled => (
          icon: Icons.event_busy_outlined,
          tone: AppStatusColor.cancelled,
        ),
      NotificationType.helpRemoved => (
          icon: Icons.person_off_outlined,
          tone: AppStatusColor.cancelled,
        ),
      NotificationType.jobNoResponse => (
          icon: Icons.hourglass_empty_rounded,
          tone: AppStatusColor.neutral,
        ),
      NotificationType.proposalRejected || NotificationType.helpRejected => (
          icon: Icons.do_not_disturb_on_outlined,
          tone: AppStatusColor.neutral,
        ),
      NotificationType.proposalWithdrawn => (
          icon: Icons.undo_rounded,
          tone: AppStatusColor.neutral,
        ),
      _ => (icon: Icons.notifications_none_rounded, tone: AppStatusColor.info),
    };

/// "Trabalhos" = avisos sobre trabalhos em que a pessoa já está (pedidos,
/// propostas, equipas). Ficam de fora as oportunidades na zona, os
/// lembretes delas e as dicas da época.
bool isJobNotification(String type) =>
    type != NotificationType.newJobInRadius &&
    type != NotificationType.newHelpRequestInRadius &&
    type != NotificationType.helpRequestReopened &&
    type != NotificationType.jobOpportunityReminder &&
    type != NotificationType.seasonalTip;

/// A migration 0049 acrescenta " (Serviço, DD/MM)" ao fim do corpo; o design
/// põe-no no título. A app muda-o de sítio, para as antigas e as novas.
final _trailingContext = RegExp(r'\s*\(([^()]+)\)\s*$');

({String title, String body}) notificationTexts(
  AppNotification n, {
  required DateTime now,
}) {
  final texts = notificationBannerTexts(n);
  var body = texts.body;
  final ago = relativeTimeToday(n.createdAt, now);
  if (ago != null) body = body.isEmpty ? ago : '$body $ago';
  return (title: texts.title, body: body);
}

/// Como [notificationTexts], sem o "Há 10 min": para o aviso no topo de
/// uma notificação que acabou de chegar.
({String title, String body}) notificationBannerTexts(AppNotification n) {
  var title = n.title.trim();
  var body = n.body.trim();
  final match = _trailingContext.firstMatch(body);
  if (match != null) {
    body = body.substring(0, match.start).trim();
    title = '$title (${match.group(1)})';
  }
  return (title: title, body: body);
}

/// Notificação a mostrar no aviso do topo quando a lista de não lidas
/// muda com a app aberta: a mais recente das que não estavam em [before].
/// `null` no primeiro carregamento ([before] null), para não mostrar as
/// antigas ao abrir a app, ou quando nada chegou.
AppNotification? notificationForBanner(
  List<AppNotification>? before,
  List<AppNotification> after,
) {
  if (before == null) return null;
  final known = {for (final n in before) n.id};
  AppNotification? newest;
  for (final n in after) {
    if (n.read || known.contains(n.id)) continue;
    if (newest == null || n.createdAt.isAfter(newest.createdAt)) newest = n;
  }
  return newest;
}

/// "Há 10 min" / "Há 1h" para as de hoje; `null` para as de outros dias
/// (a secção já diz o dia).
String? relativeTimeToday(DateTime createdAt, DateTime now) {
  final local = createdAt.toLocal();
  if (!_sameDay(local, now)) return null;
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'Agora';
  if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
  return 'Há ${diff.inHours}h';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Secções "Hoje", "Ontem" e "Mais antigas", pela ordem recebida (a mais
/// recente primeiro). Secções vazias não aparecem.
List<({String label, List<AppNotification> items})> notificationSections(
  List<AppNotification> notifications,
  DateTime now,
) {
  final today = <AppNotification>[];
  final yesterday = <AppNotification>[];
  final older = <AppNotification>[];
  final yesterdayDate = DateTime(now.year, now.month, now.day - 1);
  for (final n in notifications) {
    final local = n.createdAt.toLocal();
    if (_sameDay(local, now)) {
      today.add(n);
    } else if (_sameDay(local, yesterdayDate)) {
      yesterday.add(n);
    } else {
      older.add(n);
    }
  }
  return [
    if (today.isNotEmpty) (label: 'Hoje', items: today),
    if (yesterday.isNotEmpty) (label: 'Ontem', items: yesterday),
    if (older.isNotEmpty) (label: 'Mais antigas', items: older),
  ];
}

/// Botão no próprio aviso. Só "Confirmar conclusão" (cliente, trabalho
/// marcado como feito) e só enquanto não foi lido: depois de aberto o
/// pedido já mostra o estado atual.
String? notificationActionLabel(AppNotification n) =>
    n.type == NotificationType.jobMarkedDone && !n.read
        ? 'Confirmar conclusão'
        : null;
