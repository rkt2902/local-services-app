import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    required this.label,
    super.key,
    this.hintText,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.suffixIcon,
    this.readOnly = false,
    this.onTap,
    this.validator,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;

  /// Se omitido, é escolhido automaticamente: `TextInputType.multiline`
  /// quando o campo aceita mais de uma linha (`maxLines == null` ou `> 1`),
  /// senão `TextInputType.text`. Passar um valor explícito continua a
  /// ganhar sempre — isto só cobre o caso não especificado.
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isMultiline = maxLines == null || maxLines! > 1;
    final effectiveKeyboardType = keyboardType ??
        (isMultiline ? TextInputType.multiline : TextInputType.text);

    return TextFormField(
      controller: controller,
      keyboardType: effectiveKeyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      readOnly: readOnly,
      onTap: onTap,
      validator: validator,
      autofillHints: autofillHints,
      maxLines: maxLines,
      minLines: minLines,
      onFieldSubmitted: onFieldSubmitted,
      style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle:
            textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
      ),
    );
  }
}
