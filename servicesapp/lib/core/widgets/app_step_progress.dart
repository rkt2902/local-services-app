import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';

class AppStepProgress extends StatelessWidget {
  const AppStepProgress({
    required this.currentStep,
    required this.totalSteps,
    super.key,
  }) : assert(currentStep >= 1),
       assert(totalSteps >= 1),
       assert(currentStep <= totalSteps);

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Row(
      children: [
        for (var index = 1; index <= totalSteps; index++) ...[
          _StepNode(
            step: index,
            currentStep: currentStep,
            textTheme: textTheme,
          ),
          if (index < totalSteps)
            Expanded(
              child: _AnimatedConnector(
                active: index < currentStep,
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
              ),
            ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.step,
    required this.currentStep,
    required this.textTheme,
  });

  final int step;
  final int currentStep;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final completed = step < currentStep;
    final current = step == currentStep;
    final active = completed || current;

    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? AppColors.primary
            : AppColors.background,
        border: Border.all(
          color: active
              ? AppColors.primary
              : AppColors.divider,
        ),
      ),
      child: completed
          ? const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.surface,
            )
          : Text(
              '$step',
              style: textTheme.labelMedium?.copyWith(
                color: current
                    ? AppColors.surface
                    : AppColors.textSecondary,
              ),
            ),
    );
  }
}

class _AnimatedConnector extends StatelessWidget {
  const _AnimatedConnector({
    required this.active,
    required this.duration,
  });

  final bool active;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
      ),
      color: AppColors.divider,
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: duration,
        curve: Curves.easeOutCubic,
        widthFactor: active ? 1 : 0,
        child: Container(
          color: AppColors.primary,
        ),
      ),
    );
  }
}
