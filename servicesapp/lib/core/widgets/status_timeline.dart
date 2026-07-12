import 'package:flutter/material.dart';
import '../theme/app_status_color.dart';

enum TimelineStepState { done, current, future, cancelled }

class TimelineStep {
  const TimelineStep({
    required this.label,
    required this.state,
    this.subtitle,
    this.note,
    this.noteIsWarning = false,
  });

  final String label;
  final TimelineStepState state;
  final String? subtitle;
  final String? note;
  final bool noteIsWarning;
}

class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.steps});

  final List<TimelineStep> steps;

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

  final TimelineStep step;
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
                _circle(theme),
                if (!isLast) Expanded(child: _connector(theme)),
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

  Widget _circle(ThemeData theme) => switch (step.state) {
        TimelineStepState.done => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: AppStatusColor.success.foreground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
        TimelineStepState.current => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.circle,
                color: theme.colorScheme.onPrimary, size: 10),
          ),
        TimelineStepState.future => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              border: Border.all(
                  color: theme.colorScheme.outlineVariant, width: 2),
              shape: BoxShape.circle,
            ),
          ),
        TimelineStepState.cancelled => Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: AppStatusColor.cancelled.foreground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 14),
          ),
      };

  Widget _connector(ThemeData theme) {
    final color = switch (step.state) {
      TimelineStepState.done => AppStatusColor.success.foreground,
      TimelineStepState.current => theme.colorScheme.primary,
      TimelineStepState.future || TimelineStepState.cancelled =>
        theme.colorScheme.outlineVariant,
    };
    return Center(child: Container(width: _lineWidth, color: color));
  }

  Widget _content(ThemeData theme) {
    final labelStyle = switch (step.state) {
      TimelineStepState.done ||
      TimelineStepState.current ||
      TimelineStepState.cancelled =>
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      TimelineStepState.future => theme.textTheme.bodyMedium
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    };

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
              color: step.noteIsWarning
                  ? Colors.orange.shade50
                  : theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              step.note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: step.noteIsWarning
                    ? Colors.orange.shade800
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
