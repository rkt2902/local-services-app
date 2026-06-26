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

class ClientProfileScreen extends ConsumerStatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends ConsumerState<ClientProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  File? _newAvatar;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _initFields(ClientProfile profile) {
    if (_initialized) return;
    _nameController.text = profile.fullName;
    _phoneController.text = profile.phone;
    _initialized = true;
  }

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

  Future<void> _save(ClientProfile profile) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(clientRepositoryProvider);
      final user = ref.read(currentUserProvider)!;
      String? avatarUrl = profile.avatarUrl;
      if (_newAvatar != null) {
        avatarUrl = await repo.uploadAvatar(user.id, _newAvatar!);
      }
      await repo.updateProfile(
        user.id,
        profile.copyWith(
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          avatarUrl: avatarUrl,
        ),
      );
      ref.invalidate(clientProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil atualizado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(clientProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('O meu perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              final router = GoRouter.of(context);
              await ref.read(authControllerProvider.notifier).signOut();
              if (!mounted) return;
              router.go('/');
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Perfil não encontrado.'));
          }
          _initFields(profile);
          final avatarProvider = _newAvatar != null
              ? FileImage(_newAvatar!) as ImageProvider
              : (profile.avatarUrl != null
                  ? NetworkImage(profile.avatarUrl!)
                  : null);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: avatarProvider,
                      child: avatarProvider == null
                          ? Icon(Icons.person,
                              size: 48, color: theme.colorScheme.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Alterar foto'),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduz o teu nome.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduz o teu telefone.'
                        : null,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(profile),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar alterações'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
