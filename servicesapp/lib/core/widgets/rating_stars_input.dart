import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion_tokens.dart';

/// Input de 5 estrelas partilhado (docs/motion_spec.md §3, "Estrelas de
/// avaliação", tokens `fast · reward`).
///
/// Substitui as duas implementações anteriores e não partilhadas
/// (`client_rate_worker_screen.dart` e `rating_sheet.dart`), que tinham
/// comportamento inconsistente entre si.
///
/// - Ao aparecer: as 5 estrelas surgem uma a uma, 100ms de intervalo —
///   valor bespoke da spec (não é `AppMotionDuration.stagger`, que é 120ms e
///   partilhado com a cascata de listas; este intervalo é específico deste
///   componente, como o pulso da timeline ou o shimmer têm os seus próprios
///   valores locais).
/// - Ao tocar: só a estrela efetivamente tocada faz pop — as restantes cujo
///   estado de seleção muda como efeito colateral (ex.: tocar na 5ª estrela
///   quando a nota era 2) não animam, só atualizam a cor/ícone.
class RatingStarsInput extends StatefulWidget {
  const RatingStarsInput({
    required this.rating,
    required this.onChanged,
    super.key,
    this.playEntrance = true,
    this.semanticsLabel,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  /// Quando `false`, as estrelas aparecem já no estado final, sem a
  /// sequência de entrada — para reaproveitar o widget em contextos onde a
  /// entrada em cascata não faz sentido (ex.: dentro de uma lista que já
  /// tem a sua própria animação de entrada).
  final bool playEntrance;

  final String? semanticsLabel;

  @override
  State<RatingStarsInput> createState() => _RatingStarsInputState();
}

class _RatingStarsInputState extends State<RatingStarsInput> {
  // Intervalo entre estrelas na entrada — valor bespoke do spec, não um
  // token partilhado (ver doc do widget acima).
  static const Duration _entranceStagger = Duration(milliseconds: 100);

  int? _justTappedIndex;
  Timer? _clearTappedTimer;
  bool _disableAnimations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  void _handleTap(int index) {
    _clearTappedTimer?.cancel();
    setState(() => _justTappedIndex = index);
    widget.onChanged(index);
    // Limpa depois de dar tempo ao pop de correr — não fica "preso" a
    // repetir o pop se o mesmo índice for tocado outra vez de seguida.
    _clearTappedTimer = Timer(AppMotionDuration.fast, () {
      if (mounted) setState(() => _justTappedIndex = null);
    });
  }

  @override
  void dispose() {
    _clearTappedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel ?? 'Avaliação de ${widget.rating} em 5 estrelas',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 1; index <= 5; index++)
            _RatingStar(
              index: index,
              selected: index <= widget.rating,
              justTapped: index == _justTappedIndex,
              entranceDelay: (!widget.playEntrance || _disableAnimations)
                  ? Duration.zero
                  : _entranceStagger * (index - 1),
              disableAnimations: _disableAnimations,
              skipEntrance: !widget.playEntrance,
              onPressed: () => _handleTap(index),
            ),
        ],
      ),
    );
  }
}

class _RatingStar extends StatefulWidget {
  const _RatingStar({
    required this.index,
    required this.selected,
    required this.justTapped,
    required this.entranceDelay,
    required this.disableAnimations,
    required this.skipEntrance,
    required this.onPressed,
  });

  final int index;
  final bool selected;
  final bool justTapped;
  final Duration entranceDelay;
  final bool disableAnimations;
  final bool skipEntrance;
  final VoidCallback onPressed;

  @override
  State<_RatingStar> createState() => _RatingStarState();
}

class _RatingStarState extends State<_RatingStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  Timer? _entranceTimer;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: AppMotionDuration.fast,
      value: (widget.disableAnimations || widget.skipEntrance) ? 1 : 0,
    );

    if (!widget.disableAnimations && !widget.skipEntrance) {
      _entranceTimer = Timer(widget.entranceDelay, () {
        if (mounted) _popController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RatingStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.justTapped && !oldWidget.justTapped && !widget.disableAnimations) {
      _popController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onPressed,
      tooltip: '${widget.index} estrelas',
      iconSize: 36,
      icon: ScaleTransition(
        scale: CurvedAnimation(
          parent: _popController,
          curve: AppMotionCurve.reward,
        ),
        child: Icon(
          widget.selected ? Icons.star_rounded : Icons.star_border_rounded,
          color: AppColors.logoAccent,
        ),
      ),
    );
  }
}
