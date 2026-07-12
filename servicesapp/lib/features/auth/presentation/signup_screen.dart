import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/auth_controller.dart';
import '../application/pending_signup_provider.dart';

enum _PasswordStrength { weak, medium, good }

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  _PasswordStrength get _passwordStrength {
    final value = _passwordController.text;
    int score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) || RegExp(r'[0-9]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'[!@#\$&*~%^()_\-+=,.?":{}|<>]').hasMatch(value)) score++;
    if (score <= 1) return _PasswordStrength.weak;
    if (score == 2) return _PasswordStrength.medium;
    return _PasswordStrength.good;
  }

  String _strengthLabel(_PasswordStrength s) => switch (s) {
        _PasswordStrength.weak => 'Fraca',
        _PasswordStrength.medium => 'Média',
        _PasswordStrength.good => 'Boa',
      };

  int _strengthBars(_PasswordStrength s) => switch (s) {
        _PasswordStrength.weak => 1,
        _PasswordStrength.medium => 2,
        _PasswordStrength.good => 3,
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_acceptedTerms) return;
    await ref.read(authControllerProvider.notifier).signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
    );
    if (!mounted) return;
    final currentState = ref.read(authControllerProvider);
    if (currentState is! AuthSuccess) return;
    ref.read(pendingSignupProvider.notifier).set(
      _nameController.text.trim(),
      _phoneController.text.trim(),
    );
    context.go('/choose-role');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;
    final strength = _passwordStrength;
    final activeBars = _strengthBars(strength);

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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text(
                    'Criar conta',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      AppTextField(
                        controller: _nameController,
                        label: 'Nome completo',
                        autofillHints: const [AutofillHints.name],
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Introduza o nome completo.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _emailController,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          if (text.isEmpty) return 'Introduza o email.';
                          if (!text.contains('@')) return 'Email inválido.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _phoneController,
                        label: 'Telemóvel',
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Introduza o telemóvel.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Introduza uma password.';
                          if ((v ?? '').length < 6) return 'Mínimo 6 caracteres.';
                          return null;
                        },
                      ),
                      if (_passwordController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: List.generate(3, (i) {
                                  final active = i < activeBars;
                                  return Expanded(
                                    child: Container(
                                      height: 5,
                                      margin: EdgeInsets.only(
                                          right: i == 2 ? 0 : 6),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? AppStatusColor.success.foreground
                                            : AppStatusColor.success.background,
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.pill),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _strengthLabel(strength),
                              style: textTheme.labelLarge?.copyWith(
                                color: AppStatusColor.success.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (v) =>
                                setState(() => _acceptedTerms = v ?? false),
                            side: const BorderSide(color: AppColors.primary),
                            activeColor: AppColors.primary,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 11),
                              child: RichText(
                                text: TextSpan(
                                  style: textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Aceito os '),
                                    TextSpan(
                                      text: 'Termos',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: AppColors.primaryPressed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const TextSpan(text: ' e a '),
                                    TextSpan(
                                      text: 'Política de Privacidade',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: AppColors.primaryPressed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
              child: PrimaryActionButton(
                label: 'Criar conta',
                isLoading: isLoading,
                onPressed: _acceptedTerms ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
