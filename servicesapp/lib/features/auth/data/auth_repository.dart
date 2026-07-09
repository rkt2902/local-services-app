import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/enums.dart';

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone},
    );
  }

  Future<void> createProfile({
    required String userId,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'phone': phone,
      'role': role.value,
    });
  }

  Future<({String fullName, String phone})?> fetchNameAndPhone(
      String userId) async {
    final data = await _client
        .from('profiles')
        .select('full_name, phone')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return (
      fullName: data['full_name'] as String,
      phone: data['phone'] as String? ?? '',
    );
  }

  Future<UserRole?> fetchUserRole(String userId) async {
    final data = await _client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserRole.fromString(data['role'] as String);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
