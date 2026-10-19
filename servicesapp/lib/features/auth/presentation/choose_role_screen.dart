import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/widgets/app_motion.dart';
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
      await ref.read(authControllerProvider.notifier).createProfile(
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
          SnackBar(
              content: Text(next.message),
              backgroundColor: AppStatusColor.cancelled.foreground),
        );
      }
    });

    final busy = _submitting || isLoading;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: Text(
                        'Como queres usar a ProJardim?',
                        style: textTheme.displaySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // Sem "podes mudar mais tarde": o papel não se muda depois
                    // de escolhido (trigger prevent_profile_role_change).
                    const SizedBox(height: AppSpacing.xs),
                    const AppStaggeredEntrance(index: 1, child: _RoleWarning()),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: _RoleSelectionCard(
                        title: 'Preciso de jardinagem',
                        description: 'Publica pedidos e recebe propostas',
                        icon: Icons.home_work_outlined,
                        selected: _selectedRole == UserRole.client,
                        onTap: busy
                            ? null
                            : () => setState(
                                  () => _selectedRole = UserRole.client,
                                ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 3,
                      child: _RoleSelectionCard(
                        title: 'Sou jardineiro',
                        description: 'Encontra trabalho perto de ti',
                        icon: Icons.yard_outlined,
                        selected: _selectedRole == UserRole.worker,
                        onTap: busy
                            ? null
                            : () => setState(
                                  () => _selectedRole = UserRole.worker,
                                ),
                      ),
                    ),
                    if (_identity.needsContact) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 4,
                        child: _ContactFields(
                          formKey: _formKey,
                          nameController: _nameController,
                          phoneController: _phoneController,
                          role: _selectedRole,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: PrimaryActionButton(
                label: 'Continuar',
                isLoading: busy,
                onPressed: _selectedRole == null ? null : _submit,
              ),
            ),
            // Saída para quem entrou na conta errada (sem isto, só
            // desinstalando ou limpando os dados do browser).
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Não és tu?',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed:
                        busy ? null : () => confirmAndSignOut(context, ref),
                    child: Text(
                      'Terminar sessão',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.primaryPressed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso a âmbar: o papel não se muda depois de escolhido.
class _RoleWarning extends StatelessWidget {
  const _RoleWarning();

  @override
  Widget build(BuildContext context) {
    final color = AppStatusColor.waiting.foreground;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded,
            size: AppSizes.inlineIcon, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Escolhe com cuidado: não é possível mudar depois.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
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

/// Para quê o telemóvel, dito do lado de quem vai contactar.
@visibleForTesting
String phoneUsageHint(UserRole? role) => switch (role) {
      UserRole.client =>
        'Usamos o teu número para o jardineiro te contactar por WhatsApp.',
      UserRole.worker =>
        'Usamos o teu número para o cliente te contactar por WhatsApp.',
      null => 'Usamos o teu número só para o contacto por WhatsApp.',
    };

class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.role,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final UserRole? role;

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
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: nameController,
            label: 'Nome',
            autofillHints: const [AutofillHints.name],
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Introduz o teu nome.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          // O "+351" é só uma ajuda visual: quem escreve outro indicativo
          // (+44...) continua a ser aceite por phoneValidator.
          AppTextField(
            controller: phoneController,
            label: 'Telemóvel',
            hintText: '912 345 678',
            prefixText: '+351 ',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            validator: (v) =>
                phoneValidator(v, emptyMessage: 'Introduz o telemóvel.'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            phoneUsageHint(role),
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: AppMotionCurve.standard,
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryContainer : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.actionIconBox,
                height: AppSizes.actionIconBox,
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  icon,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  size: AppSizes.rowIcon,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
