import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Dados de apresentação do formulário de edição do cliente.
///
/// A integração (client_edit_profile_screen.dart) mapeia o `ClientProfile`
/// real + o `User` da sessão Supabase para esta estrutura. Este widget não
/// consulta providers, repositories ou Supabase diretamente.
class ClientEditProfileViewData {
  const ClientEditProfileViewData({
    required this.profileId,
    required this.fullName,
    required this.phone,
    required this.email,
    this.avatarImage,
    this.isEmailConfirmed = false,
  });

  final String profileId;
  final String fullName;
  final String phone;
  final String email;

  /// `FileImage` quando há uma foto acabada de escolher (ainda não
  /// enviada) ou `NetworkImage` quando é a foto já guardada — a integração
  /// decide qual dos dois construir. `null` = sem foto.
  final ImageProvider? avatarImage;

  /// Confirmação do endereço de email, não verificação de identidade.
  ///
  /// A confirmação de email está desativada no dashboard Supabase para o
  /// MVP (ver decisions_log.md, 2026-06-05) — nenhum utilizador passa
  /// realmente por um fluxo de confirmação hoje. Este valor vem de
  /// `currentUser?.emailConfirmedAt != null`, que nalguns casos pode estar
  /// `true` só porque o Supabase marca a conta como confirmada
  /// automaticamente no `signUp` enquanto a opção está desligada — não há
  /// nenhuma verificação em vigor a confirmar isto ao vivo neste projeto.
  /// É por isso um indicador decorativo por agora, não uma garantia
  /// funcional de que o email foi de facto verificado pelo utilizador.
  final bool isEmailConfirmed;
}

class ClientEditProfileScreen extends StatefulWidget {
  const ClientEditProfileScreen({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onChangePhoto,
    required this.onSave,
    required this.onSignOut,
    this.onRetry,
  });

  /// null = perfil não encontrado / sessão já não permite
  /// resolver um perfil de cliente.
  final AsyncValue<ClientEditProfileViewData?> dataAsync;

  final VoidCallback onBack;
  final VoidCallback onChangePhoto;
  final VoidCallback onSignOut;
  final VoidCallback? onRetry;

  /// Deve devolver `true` apenas depois de o backend confirmar que as
  /// alterações foram efetivamente guardadas (upload do avatar, se houver
  /// foto nova, seguido do update de `profiles`). Em caso de erro, a
  /// integração é responsável por mostrar o próprio feedback (SnackBar) —
  /// este widget só usa o `bool` para decidir se mostra o sucesso.
  final Future<bool> Function(String fullName, String phone) onSave;

  @override
  State<ClientEditProfileScreen> createState() =>
      _ClientEditProfileScreenState();
}

class _ClientEditProfileScreenState extends State<ClientEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String? _initializedProfileId;

  bool _saving = false;
  bool _successVisible = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _initialize(ClientEditProfileViewData data) {
    if (_initializedProfileId == data.profileId) return;
    _initializedProfileId = data.profileId;

    _fullNameController.text = data.fullName;
    _phoneController.text = data.phone;
    _emailController.text = data.email;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _successTimer?.cancel();
    setState(() {
      _saving = true;
      _successVisible = false;
    });

    final confirmed = await widget.onSave(
      _fullNameController.text.trim(),
      _phoneController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _successVisible = confirmed;
    });

    if (confirmed) {
      _successTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _successVisible = false);
      });
    }
  }

  String? _fullNameValidator(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Introduz o teu nome.' : null;

  String? _phoneValidator(String? value) => (value == null || value.trim().isEmpty)
      ? 'Introduz o teu telefone.'
      : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            widget.dataAsync.when(
              loading: () => _ProfileLoading(onBack: widget.onBack),
              error: (_, _) => _ProfileLoadError(
                onBack: widget.onBack,
                onRetry: widget.onRetry,
              ),
              data: (data) {
                if (data == null) {
                  return _ProfileNotFound(onSignOut: widget.onSignOut);
                }

                _initialize(data);

                return _ProfileForm(
                  formKey: _formKey,
                  data: data,
                  fullNameController: _fullNameController,
                  phoneController: _phoneController,
                  emailController: _emailController,
                  saving: _saving,
                  fullNameValidator: _fullNameValidator,
                  phoneValidator: _phoneValidator,
                  onBack: widget.onBack,
                  onSignOut: widget.onSignOut,
                  onChangePhoto: widget.onChangePhoto,
                  onSave: _save,
                );
              },
            ),
            Positioned.fill(
              child: AppSuccessFeedback(
                visible: _successVisible,
                message: 'Alterações guardadas com sucesso.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.formKey,
    required this.data,
    required this.fullNameController,
    required this.phoneController,
    required this.emailController,
    required this.saving,
    required this.fullNameValidator,
    required this.phoneValidator,
    required this.onBack,
    required this.onSignOut,
    required this.onChangePhoto,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final ClientEditProfileViewData data;

  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;

  final bool saving;

  final String? Function(String?) fullNameValidator;
  final String? Function(String?) phoneValidator;

  final VoidCallback onBack;
  final VoidCallback onSignOut;
  final VoidCallback onChangePhoto;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileHeader(onBack: onBack, onSignOut: onSignOut),
        Expanded(
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: _PhotoSection(
                      avatarImage: data.avatarImage,
                      onChangePhoto: onChangePhoto,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child: AppTextField(
                      controller: fullNameController,
                      label: 'Nome completo *',
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: fullNameValidator,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: AppTextField(
                      controller: phoneController,
                      label: 'Telefone *',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      validator: phoneValidator,
                      suffixIcon: const Icon(
                        Icons.phone_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 3,
                    child: AppTextField(
                      controller: emailController,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      readOnly: true,
                      suffixIcon: data.isEmailConfirmed
                          ? Icon(
                              Icons.verified_user_outlined,
                              color: AppStatusColor.success.foreground,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PrimaryActionButton(
            label: saving ? 'A guardar...' : 'Guardar alterações',
            onPressed: saving ? null : onSave,
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onBack, required this.onSignOut});

  final VoidCallback onBack;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              'O meu perfil',
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: onSignOut,
            tooltip: 'Sair',
            icon: Icon(
              Icons.logout_rounded,
              color: AppStatusColor.cancelled.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({required this.avatarImage, required this.onChangePhoto});

  final ImageProvider? avatarImage;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CircleAvatar(
                  backgroundColor: AppColors.primaryContainer,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? const Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                ),
              ),
              Positioned(
                right: -2,
                bottom: 2,
                child: Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onChangePhoto,
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: AppColors.surface,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onChangePhoto,
          child: Text(
            'Alterar foto',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LoadingHeader(onBack: onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                AppSkeletonShimmer(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppSkeletonShimmer(
                  child: Container(
                    width: 110,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppSkeletonShimmer(
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'O meu perfil',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        _LoadingHeader(onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppStaggeredEntrance(
                index: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppStatusColor.cancelled.background,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.cloud_off_outlined,
                        color: AppStatusColor.cancelled.foreground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Não foi possível carregar',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Verifica a ligação e tenta novamente.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: onRetry,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                        child: Text(
                          'Tentar novamente',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileNotFound extends StatelessWidget {
  const _ProfileNotFound({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppStatusColor.neutral.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_off_outlined,
                  color: AppStatusColor.neutral.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Perfil não encontrado',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A tua sessão pode já não ser válida. Entra novamente.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryActionButton(
                label: 'Sair e voltar ao login',
                onPressed: onSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
