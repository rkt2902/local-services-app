import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../auth/application/auth_providers.dart';
import '../application/fleet_card_providers.dart';

/// Passo de confirmação — recebe os 3 campos já extraídos por OCR
/// (`fleet_card_scan_screen.dart`) via query params, deixa o worker
/// corrigir/preencher, e faz o INSERT em `worker_fleet_cards`.
///
/// Não há `cardId`: ao contrário do ecrã de referência (pensado para
/// reutilização futura entre "criar" e "editar"), este fluxo nunca edita
/// um cartão existente — a RLS bloqueia UPDATE de propósito (migration
/// 0037), por isso "tentar novamente" depois de um `rejected` é sempre um
/// INSERT novo, nunca uma edição. Um `cardId` sintético não teria nenhum
/// consumidor real; omiti-lo por completo em vez de inventar um valor
/// (`'new'`) sem uso.
class FleetCardConfirmDataScreen extends ConsumerStatefulWidget {
  const FleetCardConfirmDataScreen({
    super.key,
    required this.initialBarcodeNumber,
    required this.initialCustomerCardNumber,
    required this.initialCardHolderName,
    required this.barcodeWasRead,
  });

  final String initialBarcodeNumber;
  final String initialCustomerCardNumber;
  final String initialCardHolderName;

  /// `true` quando o OCR conseguiu ler o código de barras — determina o
  /// banner mostrado e se o campo do código de barras arranca com foco.
  final bool barcodeWasRead;

  @override
  ConsumerState<FleetCardConfirmDataScreen> createState() =>
      _FleetCardConfirmDataScreenState();
}

class _FleetCardConfirmDataScreenState
    extends ConsumerState<FleetCardConfirmDataScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _customerCardNumberController;
  late final TextEditingController _cardHolderNameController;

  bool _saving = false;
  bool _successVisible = false;
  Timer? _successTimer;

  @override
  void initState() {
    super.initState();
    _barcodeController = TextEditingController(text: widget.initialBarcodeNumber);
    _customerCardNumberController =
        TextEditingController(text: widget.initialCustomerCardNumber);
    _cardHolderNameController =
        TextEditingController(text: widget.initialCardHolderName);
    _barcodeController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _barcodeController.removeListener(_onFieldChanged);
    _barcodeController.dispose();
    _customerCardNumberController.dispose();
    _cardHolderNameController.dispose();
    _successTimer?.cancel();
    super.dispose();
  }

  bool get _hasRequiredBarcode => _barcodeController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving || !_hasRequiredBarcode) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _saving = true;
      _successVisible = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fleetCardRepositoryProvider).createFleetCard(
            workerId: user.id,
            barcodeValue: _barcodeController.text.trim(),
            cardNumber: _customerCardNumberController.text.trim(),
            holderName: _cardHolderNameController.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(myFleetCardProvider);

      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      setState(() {
        _saving = false;
        _successVisible = true;
      });

      _successTimer?.cancel();
      _successTimer = Timer(
        disableAnimations
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 1100),
        () {
          if (!mounted) return;
          // Passo 4: depois do INSERT (sempre 'pending'), aterra no estado
          // "Pendente" do ecrã principal — go, não push, para não deixar
          // o formulário no stack.
          context.go('/worker/fleet-card');
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _hasRequiredBarcode && !_saving;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(onBack: () => context.pop()),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppStaggeredEntrance(
                            index: 0,
                            child: AppFadeThroughSwitcher(
                              switchKey: widget.barcodeWasRead,
                              duration: const Duration(milliseconds: 180),
                              child: widget.barcodeWasRead
                                  ? const _DetectedDataInfo(key: ValueKey('detected'))
                                  : const _BarcodeUnreadWarning(key: ValueKey('unread')),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppStaggeredEntrance(
                            index: 1,
                            child: _DataField(
                              label: 'Número do código de barras',
                              requirementLabel: 'Obrigatório',
                              controller: _barcodeController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Introduz o número do código de barras.'
                                  : null,
                              supportingText:
                                  'É este o número que a bomba de combustível lê.',
                              autofocus: !widget.barcodeWasRead,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppStaggeredEntrance(
                            index: 2,
                            child: _DataField(
                              label: 'Número de cliente/cartão',
                              requirementLabel: 'Opcional',
                              controller: _customerCardNumberController,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppStaggeredEntrance(
                            index: 3,
                            child: _DataField(
                              label: 'Nome no cartão',
                              requirementLabel: 'Opcional',
                              controller: _cardHolderNameController,
                              keyboardType: TextInputType.name,
                              textInputAction: TextInputAction.done,
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
                    label: 'Guardar cartão',
                    isLoading: _saving,
                    onPressed: canSave ? _save : null,
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: AppSuccessFeedback(
                visible: _successVisible,
                message: 'Cartão guardado com sucesso.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
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
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              'Confirmar dados',
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectedDataInfo extends StatelessWidget {
  const _DetectedDataInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Preenchemos o que conseguimos ler do cartão. ',
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: 'Confirma se os dados estão corretos.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeUnreadWarning extends StatelessWidget {
  const _BarcodeUnreadWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppStatusColor.waiting.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppStatusColor.waiting.foreground),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppStatusColor.waiting.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Não conseguimos ler o código de barras. ',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppStatusColor.waiting.foreground),
                  ),
                  TextSpan(
                    text: 'Escreve-o à mão para continuar.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppStatusColor.waiting.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataField extends StatelessWidget {
  const _DataField({
    required this.label,
    required this.requirementLabel,
    required this.controller,
    required this.keyboardType,
    required this.textInputAction,
    this.validator,
    this.supportingText,
    this.autofocus = false,
  });

  final String label;
  final String requirementLabel;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final String? supportingText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isRequired = requirementLabel == 'Obrigatório';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              requirementLabel,
              style: textTheme.labelMedium?.copyWith(
                color: isRequired
                    ? AppStatusColor.waiting.foreground
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            suffixIcon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide(color: AppStatusColor.cancelled.foreground),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide(color: AppStatusColor.cancelled.foreground),
            ),
          ),
        ),
        if (supportingText != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            supportingText!,
            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
