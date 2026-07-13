import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_status_color.dart';

enum StatusTimelineStepState { completed, current, future }

class StatusTimelineStepData {
  const StatusTimelineStepData({
    required this.label,
    required this.statusColor,
    required this.state,
    this.subtitle,
    this.note,
    this.noteIsWarning = false,
  });

  final String label;
  final AppStatusColor statusColor;
  final StatusTimelineStepState state;
  final String? subtitle;
  final String? note;
  final bool noteIsWarning;
}

class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.steps});

  final List<StatusTimelineStepData> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++)
          _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast});

  final StatusTimelineStepData step;
  final bool isLast;

  static const _circleSize = 24.0;
  static const _lineWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _circleSize,
            child: Column(
              children: [
                _circle(),
                if (!isLast) Expanded(child: _connector()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 16),
              child: _content(theme),
            ),
          ),
        ],
      ),
    );
  }

  // Passo concluído e atual usam sempre a cor real do estado
  // (step.statusColor) — nunca AppColors.primary automaticamente. Passo
  // futuro é o único que não representa um estado real: outline neutro fixo,
  // independentemente do statusColor recebido.
  Widget _circle() => switch (step.state) {
        StatusTimelineStepState.completed => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: step.statusColor.foreground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
        StatusTimelineStepState.current => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: step.statusColor.background,
              shape: BoxShape.circle,
              border: Border.all(color: step.statusColor.foreground, width: 2),
            ),
            child: Icon(Icons.circle,
                color: step.statusColor.foreground, size: 10),
          ),
        StatusTimelineStepState.future => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider, width: 2),
              shape: BoxShape.circle,
            ),
          ),
      };

  Widget _connector() {
    final color = switch (step.state) {
      StatusTimelineStepState.completed => step.statusColor.foreground,
      StatusTimelineStepState.current => step.statusColor.foreground,
      StatusTimelineStepState.future => AppColors.divider,
    };
    return Center(child: Container(width: _lineWidth, color: color));
  }

  Widget _content(ThemeData theme) {
    final isFuture = step.state == StatusTimelineStepState.future;
    final labelStyle = isFuture
        ? theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    final noteColor =
        step.noteIsWarning ? AppStatusColor.waiting : AppStatusColor.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step.label, style: labelStyle),
        if (step.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            step.subtitle!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (step.note != null) ...[
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: noteColor.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              step.note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: noteColor.foreground,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
