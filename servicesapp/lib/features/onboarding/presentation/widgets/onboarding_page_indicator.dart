import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion_tokens.dart';

class OnboardingPageIndicator extends StatelessWidget {
  const OnboardingPageIndicator({
    super.key,
    required this.currentPage,
    required this.pageCount,
    this.activeColor = AppColors.primary,
    this.inactiveColor = const Color(0xFFD7E5D0),
  });

  final int currentPage;
  final int pageCount;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (i) {
        final isActive = i == currentPage;
        return AnimatedContainer(
          duration: transitionDuration,
          curve: AppMotionCurve.standard,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
