import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/onboarding_prefs_service.dart';

final onboardingPrefsServiceProvider = Provider<OnboardingPrefsService>(
  (_) => OnboardingPrefsService(),
);

class OnboardingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.read(onboardingPrefsServiceProvider).hasSeenOnboarding();
  }

  Future<void> markSeen() async {
    await ref.read(onboardingPrefsServiceProvider).markOnboardingSeen();
    state = const AsyncData(true);
  }
}

final hasSeenOnboardingProvider =
    AsyncNotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
