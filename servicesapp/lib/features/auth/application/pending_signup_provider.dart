import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingSignupState {
  final String? fullName;
  final String? phone;
  const PendingSignupState({this.fullName, this.phone});
  PendingSignupState copyWith({String? fullName, String? phone}) =>
      PendingSignupState(
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
      );
}

class PendingSignupNotifier extends Notifier<PendingSignupState> {
  @override
  PendingSignupState build() => const PendingSignupState();

  void set(String fullName, String phone) =>
      state = PendingSignupState(fullName: fullName, phone: phone);

  void clear() => state = const PendingSignupState();
}

final pendingSignupProvider =
    NotifierProvider<PendingSignupNotifier, PendingSignupState>(
  PendingSignupNotifier.new,
);
