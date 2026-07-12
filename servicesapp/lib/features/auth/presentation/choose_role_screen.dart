import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_controller.dart';
import '../application/auth_providers.dart';
import '../application/pending_signup_provider.dart';

class ChooseRoleScreen extends ConsumerStatefulWidget {
  const ChooseRoleScreen({super.key});

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
    final pending = ref.read(pendingSignupProvider);
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).createProfile(
        userId: user.id,
        fullName: pending.fullName ?? '',
        phone: pending.phone ?? '',
        role: _selectedRole!,
      );
      if (!mounted) return;
      final currentState = ref.read(authControllerProvider);
      if (currentState is AuthError) return;
      ref.read(pendingSignupProvider.notifier).clear();
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
    final textTheme = Theme.of(context).textTheme;
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Como quer usar\na ProJardim?',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pode mudar mais tarde nas definições.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              _RoleSelectionCard(
                title: 'Preciso de jardinagem',
                description:
                    'Crio pedidos e escolho o melhor profissional para o meu jardim.',
                icon: Icons.person_outline_rounded,
                selected: _selectedRole == UserRole.client,
                onTap: () => setState(() => _selectedRole = UserRole.client),
              ),
              const SizedBox(height: 14),
              _RoleSelectionCard(
                title: 'Sou jardineiro',
                description:
                    'Recebo pedidos, envio propostas e faço trabalhos — sozinho ou como ajudante.',
                icon: Icons.grass_rounded,
                selected: _selectedRole == UserRole.worker,
                onTap: () => setState(() => _selectedRole = UserRole.worker),
              ),
              const Spacer(),
              PrimaryActionButton(
                label: 'Continuar',
                isLoading: _submitting || isLoading,
                onPressed: _selectedRole == null ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSelectionCard extends StatelessWidget {
  const _RoleSelectionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 27,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.primary, width: 1.6),
                    color: selected
                        ? AppColors.primaryContainer
                        : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.primary)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
