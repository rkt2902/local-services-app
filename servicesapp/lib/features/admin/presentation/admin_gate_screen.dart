import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_brand_badge.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_otp_input.dart';
import '../../../core/widgets/app_system_state_screen.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../auth/application/auth_providers.dart';
import '../application/admin_providers.dart';
import '../data/admin_repository.dart';
import 'admin_home_screen.dart';

/// Entrada do painel (`/admin`). Decide o passo pelo estado da sessão:
/// sem sessão → login; conta normal → "Sem acesso"; administrador sem o
/// segundo fator → app autenticadora; tudo certo → o painel.
///
/// Isto é só a interface: quem decide o acesso são as RPCs `admin_*`
/// (migration 0060), que recusam tudo sem `admin_users` + aal2.
class AdminGateScreen extends ConsumerWidget {
  const AdminGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const _AdminLoginView();

    final accessAsync = ref.watch(adminAccessProvider);
    return accessAsync.when(
      loading: () => const _AdminLoadingView(),
      error: (error, _) => AppSystemStateScreen(
        icon: Icons.cloud_off_rounded,
        iconBackground: AppStatusColor.cancelled.background,
        iconForeground: AppStatusColor.cancelled.foreground,
        title: 'Não foi possível confirmar o acesso',
        message: friendlyError(error),
        primaryActionLabel: 'Tentar novamente',
        onPrimaryAction: () => ref.invalidate(adminAccessProvider),
        secondaryActionLabel: 'Terminar sessão',
        onSecondaryAction: () => ref.read(adminRepositoryProvider).signOut(),
      ),
      data: (access) {
        if (access == null) return const _AdminLoginView();
        if (!access.isAdmin) {
          return AppSystemStateScreen(
            icon: Icons.lock_outline_rounded,
            iconBackground: AppStatusColor.neutral.background,
            iconForeground: AppStatusColor.neutral.foreground,
            title: 'Sem acesso',
            message: 'Esta conta não tem acesso à administração.',
            primaryActionLabel: 'Terminar sessão',
            onPrimaryAction: () =>
                ref.read(adminRepositoryProvider).signOut(),
          );
        }
        if (!access.hasMfa) return const _AdminMfaView();
        return const AdminHomeScreen();
      },
    );
  }
}

class _AdminLoadingView extends StatelessWidget {
  const _AdminLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

/// Moldura comum aos passos de entrada: marca, título e conteúdo.
class _AdminEntryFrame extends StatelessWidget {
  const _AdminEntryFrame({
    required this.title,
    required this.message,
    required this.children,
  });

  final String title;
  final String message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppStaggeredEntrance(index: 0, child: AppBrandBadge()),
              const SizedBox(height: AppSpacing.lg),
              AppStaggeredEntrance(
                index: 1,
                child: Text(
                  title,
                  style: textTheme.displaySmall
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppStaggeredEntrance(
                index: 2,
                child: Text(
                  message,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppStaggeredEntrance(
                index: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminLoginView extends ConsumerStatefulWidget {
  const _AdminLoginView();

  @override
  ConsumerState<_AdminLoginView> createState() => _AdminLoginViewState();
}

class _AdminLoginViewState extends ConsumerState<_AdminLoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final toast = AppToast.of(context);
    try {
      await ref.read(adminRepositoryProvider).signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminEntryFrame(
      title: 'Administração',
      message: 'Acesso reservado. Entra com a conta de administrador.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _emailController,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Escreve o email.' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _passwordController,
                label: 'Palavra-passe',
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Escreve a palavra-passe.' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? 'Mostrar palavra-passe'
                      : 'Esconder palavra-passe',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryActionButton(
          label: 'Entrar',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Segundo fator: inscreve a app autenticadora na primeira vez, depois
/// pede só o código de 6 dígitos.
class _AdminMfaView extends ConsumerStatefulWidget {
  const _AdminMfaView();

  @override
  ConsumerState<_AdminMfaView> createState() => _AdminMfaViewState();
}

class _AdminMfaViewState extends ConsumerState<_AdminMfaView> {
  bool _loading = true;
  bool _verifying = false;
  bool _codeError = false;
  String? _loadError;
  String? _factorId;
  AdminTotpEnrollment? _enrollment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repository = ref.read(adminRepositoryProvider);
    try {
      final factorId = await repository.verifiedTotpFactorId();
      final enrollment =
          factorId == null ? await repository.enrollTotp() : null;
      if (!mounted) return;
      setState(() {
        _factorId = factorId ?? enrollment!.factorId;
        _enrollment = enrollment;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _verify(String code) async {
    final factorId = _factorId;
    if (factorId == null || _verifying) return;
    setState(() {
      _verifying = true;
      _codeError = false;
    });
    final toast = AppToast.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .verifyTotp(factorId: factorId, code: code);
      ref.invalidate(adminAccessProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _codeError = true);
      toast.error('Código errado ou fora de prazo. Tenta o código seguinte.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final signOut = TextButton(
      onPressed: () => ref.read(adminRepositoryProvider).signOut(),
      child: const Text('Terminar sessão'),
    );

    if (_loading) return const _AdminLoadingView();
    if (_loadError != null) {
      return _AdminEntryFrame(
        title: 'Segundo passo',
        message: _loadError!,
        children: [
          PrimaryActionButton(label: 'Tentar novamente', onPressed: _load),
          const SizedBox(height: AppSpacing.sm),
          signOut,
        ],
      );
    }

    final enrollment = _enrollment;
    final codeInput = AppOtpInput(
      onCompleted: _verify,
      enabled: !_verifying,
      hasError: _codeError,
    );

    if (enrollment == null) {
      return _AdminEntryFrame(
        title: 'Código de acesso',
        message: 'Escreve o código de 6 dígitos da tua app autenticadora.',
        children: [codeInput, const SizedBox(height: AppSpacing.lg), signOut],
      );
    }

    return _AdminEntryFrame(
      title: 'Proteger o acesso',
      message: 'Lê este código com uma app autenticadora (Google '
          'Authenticator, Microsoft Authenticator ou outra) e escreve o '
          'código de 6 dígitos que ela mostrar. A partir daí pedimos '
          'sempre esse código.',
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.divider),
            ),
            child: QrImageView(
              data: enrollment.uri,
              size: 200,
              backgroundColor: AppColors.surface,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No telemóvel, sem ler o código? Copia a chave:',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        TextButton.icon(
          onPressed: () async {
            final toast = AppToast.of(context);
            await Clipboard.setData(ClipboardData(text: enrollment.secret));
            toast.show('Chave copiada.');
          },
          icon: const Icon(Icons.copy_rounded),
          label: Text(
            enrollment.secret,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        codeInput,
        const SizedBox(height: AppSpacing.lg),
        signOut,
      ],
    );
  }
}
