import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_status_color.dart';
import '../theme/app_spacing.dart';

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
    this.maxLength,
    this.prefixText,
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

  /// Quando definido, o contador nativo do Flutter é suprimido
  /// (`counterText: ''`) — os ecrãs que precisam de mostrar a contagem
  /// constroem o próprio contador (ex. client_create_job_description_screen).
  final int? maxLength;

  /// Texto fixo antes do valor (ex.: o indicativo "+351" no telemóvel).
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isMultiline = maxLines == null || maxLines! > 1;
    final effectiveKeyboardType = keyboardType ??
        (isMultiline ? TextInputType.multiline : TextInputType.text);

    return TextFormField(
      // Na web (Flutter 3.44), mostrar/esconder a senha num campo já focado
      // deixava o campo sem aceitar escrita depois de sair e voltar a ele
      // (flutter/flutter#192102, #193267). Com uma chave por estado, o campo
      // é recriado ao alternar e abre uma ligação de texto nova; o texto
      // fica, porque vive no controller.
      key: ValueKey<bool>(obscureText),
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
      maxLength: maxLength,
      onFieldSubmitted: onFieldSubmitted,
      style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        prefixStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        counterText: maxLength == null ? null : '',
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s18),
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
          borderSide: BorderSide(color: AppStatusColor.cancelled.foreground),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide:
              BorderSide(color: AppStatusColor.cancelled.foreground, width: 1.4),
        ),
      ),
    );
  }
}
