import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_controller.dart';
import '../application/auth_providers.dart';
import '../application/pending_signup_provider.dart';
import 'sign_out_flow.dart';

class ChooseRoleScreen extends ConsumerStatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  ConsumerState<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends ConsumerState<ChooseRoleScreen> {
  UserRole? _selectedRole;
  bool _submitting = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// Nome, telefone e foto já conhecidos: do registo por email (ou dos
  /// metadados do signUp, se a app fechou a meio da confirmação), ou da
  /// conta Google/Facebook. Conta social não traz telefone, e o contacto
  /// é por WhatsApp, por isso aí pede-se aqui.
  late final RegistrationIdentity _identity;

  @override
  void initState() {
    super.initState();
    _identity = RegistrationIdentity.from(
      pending: ref.read(pendingSignupProvider),
      metadata: ref.read(currentUserProvider)?.userMetadata,
    );
    _nameController.text = _identity.fullName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _selectedRole == null) return;
    if (_identity.needsContact && !_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .createProfile(
            userId: user.id,
            fullName: _identity.needsContact
                ? _nameController.text.trim()
                : _identity.fullName,
            phone: _identity.needsContact
                ? phoneForStorage(_phoneController.text)
                : _identity.phone,
            role: _selectedRole!,
            socialAvatarUrl: _identity.socialAvatarUrl,
          );
      if (!mounted) return;
      final currentState = ref.read(authControllerProvider);
      if (currentState is AuthError) return;
      ref.read(pendingSignupProvider.notifier).clear();
      // O email já está confirmado neste ponto (código em /verify-email, ou
      // confirmação desligada no Supabase). O router leva ao início do papel
      // (ou a /worker/setup) assim que sessionStatusProvider recarregar.
      context.go('/');
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
          SnackBar(content: Text(next.message), backgroundColor: AppStatusColor.cancelled.foreground),
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
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Como queres usar\na ProJardim?',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      // Sem "podes mudar mais tarde": o papel não se muda depois de
                      // escolhido (trigger prevent_profile_role_change).
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Escolhe com cuidado: não é possível mudar depois.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _RoleSelectionCard(
                        title: 'Preciso de jardinagem',
                        description:
                            'Crio pedidos e escolho o melhor jardineiro para o meu jardim.',
                        icon: Icons.person_outline_rounded,
                        selected: _selectedRole == UserRole.client,
                        onTap: () =>
                            setState(() => _selectedRole = UserRole.client),
                      ),
                      const SizedBox(height: 14),
                      _RoleSelectionCard(
                        title: 'Sou jardineiro',
                        description:
                            'Recebo pedidos, envio propostas e faço trabalhos — sozinho ou como ajudante.',
                        icon: Icons.grass_rounded,
                        selected: _selectedRole == UserRole.worker,
                        onTap: () =>
                            setState(() => _selectedRole = UserRole.worker),
                      ),
                      if (_identity.needsContact) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _ContactFields(
                          formKey: _formKey,
                          nameController: _nameController,
                          phoneController: _phoneController,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryActionButton(
                label: 'Continuar',
                isLoading: _submitting || isLoading,
                onPressed: _selectedRole == null ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.xs),
              // Saída para quem entrou na conta errada (sem isto, só
              // desinstalando ou limpando os dados do browser).
              Center(
                child: TextButton(
                  onPressed: _submitting || isLoading
                      ? null
                      : () => confirmAndSignOut(context, ref),
                  child: const Text('Não és tu? Terminar sessão'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nome, telefone e foto conhecidos quando se chega a /choose-role.
@visibleForTesting
class RegistrationIdentity {
  const RegistrationIdentity({
    required this.fullName,
    required this.phone,
    this.socialAvatarUrl,
  });

  /// Ordem: o que foi escrito no registo nesta execução, depois os
  /// metadados do utilizador (`full_name`/`phone` do signUp por email;
  /// `full_name`/`name` e `avatar_url`/`picture` do Google e do Facebook).
  factory RegistrationIdentity.from({
    required PendingSignupState pending,
    required Map<String, dynamic>? metadata,
  }) {
    final meta = metadata ?? const <String, dynamic>{};
    String? text(String key) {
      final value = meta[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return RegistrationIdentity(
      fullName: pending.fullName ?? text('full_name') ?? text('name') ?? '',
      phone: pending.phone ?? text('phone') ?? '',
      socialAvatarUrl: text('avatar_url') ?? text('picture'),
    );
  }

  final String fullName;
  final String phone;

  /// Foto da conta Google/Facebook (URL externo), para copiar para o
  /// Storage ao criar o perfil. `null` no registo por email.
  final String? socialAvatarUrl;

  /// Sem telefone (conta Google/Facebook): o ecrã pede nome e telefone.
  bool get needsContact => phone.isEmpty;
}

class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Os teus dados',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'O telemóvel é usado para o contacto por WhatsApp depois de um '
            'trabalho confirmado.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: nameController,
            label: 'Nome',
            autofillHints: const [AutofillHints.name],
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Introduz o teu nome.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: phoneController,
            label: 'Telemóvel',
            hintText: '912 345 678',
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (v) =>
                phoneValidator(v, emptyMessage: 'Introduz o telemóvel.'),
          ),
        ],
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

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: transitionDuration,
        curve: AppMotionCurve.standard,
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
