import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../application/auth_controller.dart';
import '../application/auth_providers.dart';

class ChooseRoleScreen extends ConsumerStatefulWidget {
  final String fullName;
  final String phone;

  const ChooseRoleScreen({
    super.key,
    required this.fullName,
    required this.phone,
  });

  @override
  ConsumerState<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends ConsumerState<ChooseRoleScreen> {
  UserRole? _selectedRole;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting || _selectedRole == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).createProfile(
        userId: user.id,
        fullName: widget.fullName,
        phone: widget.phone,
        role: _selectedRole!,
      );
      if (!mounted) return;
      final currentState = ref.read(authControllerProvider);
      if (currentState is AuthError) return;
      // Navigate directly — don't wait for router redirect
      if (_selectedRole == UserRole.client) {
        context.go('/client/home');
      } else {
        context.go('/worker/setup');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Como queres usar a app?'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Escolhe o teu perfil', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Podes mudar de ideias mais tarde.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.person_outlined,
                title: 'Cliente',
                subtitle: 'Quero encontrar jardineiros e pedir serviços.',
                selected: _selectedRole == UserRole.client,
                onTap: () => setState(() => _selectedRole = UserRole.client),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.yard_outlined,
                title: 'Jardineiro',
                subtitle: 'Quero oferecer os meus serviços de jardinagem.',
                selected: _selectedRole == UserRole.worker,
                onTap: () => setState(() => _selectedRole = UserRole.worker),
              ),
              const Spacer(),
              FilledButton(
                onPressed: (_submitting || isLoading || _selectedRole == null) ? null : _submit,
                child: (_submitting || isLoading)
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar na app'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
