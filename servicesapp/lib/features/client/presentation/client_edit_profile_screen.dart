import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../../core/utils/error_utils.dart';
import '../application/client_providers.dart';
import '../data/client_profile_model.dart';
import 'widgets/client_edit_profile_view.dart' as view;

/// Formulário de edição de nome/telefone/avatar do cliente — extraído do
/// antigo `ClientProfileScreen` quando este passou a ser um ecrã de resumo
/// (`ClientAccountScreen`). Acedido via "Definições" na conta do cliente.
///
/// Wrapper que liga os providers reais ao componente apresentacional em
/// widgets/client_edit_profile_view.dart — este ficheiro é o único que fala
/// com Supabase; o widget de apresentação não sabe que Riverpod existe.
class ClientEditProfileScreen extends ConsumerStatefulWidget {
  const ClientEditProfileScreen({super.key});

  @override
  ConsumerState<ClientEditProfileScreen> createState() =>
      _ClientEditProfileScreenState();
}

class _ClientEditProfileScreenState
    extends ConsumerState<ClientEditProfileScreen> {
  File? _newAvatar;

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Câmara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 400,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _newAvatar = File(picked.path));
  }

  /// Upload do avatar (só se houver `_newAvatar` novo) + update de
  /// nome/telefone. Devolve `true` só depois de o repository confirmar —
  /// `ClientEditProfileScreen` (view) só mostra o `AppSuccessFeedback`
  /// quando recebe `true`.
  Future<bool> _save(ClientProfile profile, String fullName, String phone) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(clientRepositoryProvider);
      final user = ref.read(currentUserProvider)!;
      String? avatarUrl = profile.avatarUrl;
      if (_newAvatar != null) {
        avatarUrl = await repo.uploadAvatar(user.id, _newAvatar!);
      }
      await repo.updateProfile(
        user.id,
        profile.copyWith(fullName: fullName, phone: phone, avatarUrl: avatarUrl),
      );
      ref.invalidate(clientProfileProvider);
      return true;
    } catch (e) {
      if (mounted) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(clientProfileProvider);
    final user = ref.watch(currentUserProvider);

    final dataAsync = profileAsync.whenData((profile) {
      if (profile == null) return null;
      final avatarImage = _newAvatar != null
          ? FileImage(_newAvatar!) as ImageProvider
          : (profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null);
      return view.ClientEditProfileViewData(
        profileId: profile.id,
        fullName: profile.fullName,
        phone: profile.phone,
        email: user?.email ?? '',
        avatarImage: avatarImage,
        // Confirmação de email desativada no projeto — ver doc comment em
        // ClientEditProfileViewData.isEmailConfirmed. Indicador decorativo.
        isEmailConfirmed: user?.emailConfirmedAt != null,
      );
    });

    return view.ClientEditProfileScreen(
      dataAsync: dataAsync,
      onBack: () => context.pop(),
      onChangePhoto: _pickAvatar,
      onSignOut: _signOut,
      onRetry: () => ref.invalidate(clientProfileProvider),
      onSave: (fullName, phone) {
        final profile = profileAsync.value;
        if (profile == null) return Future.value(false);
        return _save(profile, fullName, phone);
      },
    );
  }
}
