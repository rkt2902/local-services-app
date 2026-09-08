import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';

/// N caixas de 1 dígito para códigos OTP — autofocus na primeira, avança
/// automaticamente ao preencher uma caixa, volta para trás com backspace
/// numa caixa vazia. Cola de um código completo (ex.: copiado do email)
/// distribui os dígitos pelas caixas seguintes.
///
/// Para limpar as caixas de fora (ex.: depois de um código errado), passa
/// um `key` novo (`ValueKey(algumContador)`) — força o widget a remontar
/// com estado limpo, em vez de expor um controller próprio.
class AppOtpInput extends StatefulWidget {
  const AppOtpInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChanged,
    this.autofocus = true,
    this.enabled = true,
    this.hasError = false,
  });

  final int length;

  /// Chamado exatamente quando as `length` caixas ficam preenchidas.
  final ValueChanged<String> onCompleted;

  /// Chamado a cada alteração, com o código parcial/completo até ao momento.
  final ValueChanged<String>? onChanged;

  final bool autofocus;
  final bool enabled;

  /// Tinge as caixas a vermelho (ex.: código inválido) sem limpar o
  /// conteúdo — a limpeza é feita trocando a `key` (ver doc da classe).
  final bool hasError;

  @override
  State<AppOtpInput> createState() => _AppOtpInputState();
}

class _AppOtpInputState extends State<AppOtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _notify() {
    final code = _code;
    widget.onChanged?.call(code);
    if (code.length == widget.length) {
      widget.onCompleted(code);
    }
  }

  void _distributePaste(int startIndex, String digits) {
    var i = startIndex;
    for (final digit in digits.split('')) {
      if (i >= widget.length) break;
      _controllers[i].text = digit;
      i++;
    }
    final nextEmpty = i < widget.length ? i : widget.length - 1;
    _focusNodes[nextEmpty].requestFocus();
    _notify();
  }

  void _handleChanged(int index, String value) {
    if (value.length > 1) {
      // Colar um código inteiro (ou parte dele) numa única caixa.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      _controllers[index].clear();
      _distributePaste(index, digits);
      return;
    }

    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.length; i++)
          Padding(
            padding: EdgeInsets.only(
              right: i == widget.length - 1 ? 0 : AppSpacing.xs,
            ),
            child: _OtpDigitBox(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              autofocus: widget.autofocus && i == 0,
              enabled: widget.enabled,
              isActive: _controllers[i].text.isNotEmpty,
              hasError: widget.hasError,
              isLast: i == widget.length - 1,
              onChanged: (value) => _handleChanged(i, value),
            ),
          ),
      ],
    );
  }
}

class _OtpDigitBox extends StatelessWidget {
  const _OtpDigitBox({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.enabled,
    required this.isActive,
    required this.hasError,
    required this.isLast,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final bool enabled;
  final bool isActive;
  final bool hasError;
  final bool isLast;
  final ValueChanged<String> onChanged;

  Color get _borderColor {
    if (hasError) return AppStatusColor.cancelled.foreground;
    if (isActive) return AppColors.primary;
    return AppColors.divider;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 48,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
        textAlign: TextAlign.center,
        maxLength: 1,
        // Sem LengthLimitingTextInputFormatter: precisamos de ver colas de
        // >1 dígito para as distribuir pelas caixas seguintes.
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide(color: _borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: BorderSide(
              color: hasError ? AppStatusColor.cancelled.foreground : AppColors.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
