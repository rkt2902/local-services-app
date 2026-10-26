import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../jobs/application/job_providers.dart';
import '../application/agenda_providers.dart';
import 'agenda_day_presenter.dart';
import 'agenda_day_preview_presenter.dart';
import 'agenda_day_preview_view_data.dart';
import 'widgets/agenda_day_preview_sheet.dart';

/// Abre a folha "Ver o dia" (A8F) por cima de um formulário. O formulário
/// fica montado por baixo: mudar de dia aqui não lhe mexe, e fechar de
/// qualquer forma (botão, tocar fora, puxar para baixo) devolve-o igual.
Future<void> showAgendaDayPreview(
  BuildContext context, {
  required DateTime day,
  AgendaDayPreviewGhost? ghost,
}) {
  return AppSheet.show<void>(
    context,
    builder: (_) => AgendaDayPreview(day: day, ghost: ghost),
  );
}

/// Lê o mês do dia à vista (a mesma chave do Hoje, por isso vem da cache) e
/// passa o dia já montado à folha.
class AgendaDayPreview extends ConsumerStatefulWidget {
  const AgendaDayPreview({required this.day, this.ghost, super.key});

  final DateTime day;
  final AgendaDayPreviewGhost? ghost;

  @override
  ConsumerState<AgendaDayPreview> createState() => _AgendaDayPreviewState();
}

class _AgendaDayPreviewState extends ConsumerState<AgendaDayPreview> {
  late DateTime _day = DateUtils.dateOnly(widget.day);

  void _move(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final range = agendaMonthRange(_day);
    final month = ref.watch(agendaRangeProvider(range));
    final serviceTypes =
        ref.watch(serviceTypesProvider).asData?.value ?? const <ServiceType>[];
    final entries = month.asData?.value;

    return AgendaDayPreviewSheet(
      dayLabel: agendaDayLabel(_day, now),
      data: entries == null
          ? null
          : buildAgendaDayPreview(
              day: _day,
              entries: entries,
              ghost: widget.ghost,
              serviceTypes: serviceTypes,
              now: now,
            ),
      errorMessage: entries == null && month.hasError
          ? friendlyError(month.error!)
          : null,
      onRetry: () => ref.invalidate(agendaRangeProvider(range)),
      onPreviousDay: () => _move(-1),
      onNextDay: () => _move(1),
      onClose: () => Navigator.pop(context),
    );
  }
}
