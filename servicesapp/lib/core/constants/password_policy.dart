/// Único sítio onde as regras de password vivem. Usado por `signup_screen.dart`
/// e pelo ecrã de nova password do fluxo de recuperação — as duas
/// superfícies onde se pode *criar* uma password têm de aplicar exatamente
/// a mesma regra (login não: valida uma password já existente, não uma
/// nova, por isso fica de fora de propósito).
library;

enum PasswordStrength { weak, medium, strong }

enum PasswordRule {
  minLength,
  hasUppercase,
  hasNumber,
}

extension PasswordRuleLabel on PasswordRule {
  String get label => switch (this) {
        PasswordRule.minLength => 'Mínimo de 8 caracteres',
        PasswordRule.hasUppercase => 'Uma letra maiúscula',
        PasswordRule.hasNumber => 'Um número',
      };
}

class PasswordPolicyResult {
  const PasswordPolicyResult({
    required this.strength,
    required this.satisfiedRules,
  });

  final PasswordStrength strength;
  final Set<PasswordRule> satisfiedRules;

  bool isSatisfied(PasswordRule rule) => satisfiedRules.contains(rule);

  /// Todas as 3 regras cumpridas — é isto, não `strength`, que deve gatear
  /// submits. `strength` é só feedback visual.
  bool get meetsAllRules => satisfiedRules.length == PasswordRule.values.length;
}

final RegExp _uppercasePattern = RegExp(r'[A-Z]');
final RegExp _numberPattern = RegExp(r'[0-9]');

PasswordPolicyResult evaluatePasswordPolicy(String password) {
  final satisfied = <PasswordRule>{};
  if (password.length >= 8) satisfied.add(PasswordRule.minLength);
  if (_uppercasePattern.hasMatch(password)) satisfied.add(PasswordRule.hasUppercase);
  if (_numberPattern.hasMatch(password)) satisfied.add(PasswordRule.hasNumber);

  final strength = switch (satisfied.length) {
    0 || 1 => PasswordStrength.weak,
    2 => PasswordStrength.medium,
    _ => PasswordStrength.strong,
  };

  return PasswordPolicyResult(strength: strength, satisfiedRules: satisfied);
}

/// Validator pronto a passar a `AppTextField.validator` — usa-se em
/// `signup_screen.dart` e no ecrã de nova password, para as duas nunca
/// divergirem. `null` = válido.
String? passwordPolicyValidator(String? value) {
  final text = value ?? '';
  if (text.isEmpty) return 'Introduza uma password.';
  if (!evaluatePasswordPolicy(text).meetsAllRules) {
    return 'A password tem de ter 8+ caracteres, uma maiúscula e um número.';
  }
  return null;
}
