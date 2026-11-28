import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_links.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_system_state_screen.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/invite_optout_providers.dart';
import '../data/invite_optout_repository.dart';

enum _OptoutStep { ask, done, invalid }

/// `/sem-convites?t=<token>`: quem recebeu um convite por email (0085)
/// confirma que não quer receber mais. Público, sem sessão.
class InviteOptoutScreen extends ConsumerStatefulWidget {
  const InviteOptoutScreen({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<InviteOptoutScreen> createState() => _InviteOptoutScreenState();
}

class _InviteOptoutScreenState extends ConsumerState<InviteOptoutScreen> {
  late _OptoutStep _step = inviteOptoutTokenLooksValid(widget.token)
      ? _OptoutStep.ask
      : _OptoutStep.invalid;
  bool _loading = false;

  Future<void> _confirm() async {
    final token = widget.token;
    if (token == null) return;
    setState(() => _loading = true);
    final toast = AppToast.of(context);
    try {
      final ok = await ref
          .read(inviteOptoutRepositoryProvider)
          .optout(token.trim());
      if (!mounted) return;
      setState(() => _step = ok ? _OptoutStep.done : _OptoutStep.invalid);
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goHome() => context.go('/');

  @override
  Widget build(BuildContext context) {
    final support = AppLinks.supportEmail;
    final screen = switch (_step) {
      _OptoutStep.ask => AppSystemStateScreen(
        icon: Icons.unsubscribe_outlined,
        iconBackground: AppStatusColor.neutral.background,
        iconForeground: AppStatusColor.neutral.foreground,
        title: 'Deixar de receber emails',
        message:
            'Se confirmar, a ProJardim não volta a enviar convites para o seu '
            'email.',
        primaryActionLabel: 'Não quero receber mais emails',
        onPrimaryAction: _confirm,
        isPrimaryActionLoading: _loading,
        secondaryActionLabel: 'Conhecer a ProJardim',
        onSecondaryAction: _goHome,
      ),
      _OptoutStep.done => AppSystemStateScreen(
        icon: Icons.check_rounded,
        iconBackground: AppStatusColor.success.background,
        iconForeground: AppStatusColor.success.foreground,
        title: 'Pedido registado',
        message:
            'Não voltamos a enviar emails para este endereço. Obrigado pela '
            'atenção.',
        primaryActionLabel: 'Ir para o início',
        onPrimaryAction: _goHome,
      ),
      _OptoutStep.invalid => AppSystemStateScreen(
        icon: Icons.link_off_rounded,
        iconBackground: AppStatusColor.neutral.background,
        iconForeground: AppStatusColor.neutral.foreground,
        title: 'Link incompleto',
        message:
            'Não foi possível reconhecer este link. Para deixar de receber '
            'emails da ProJardim, responda "não" a qualquer email nosso ou '
            'escreva para $support.',
        primaryActionLabel: 'Ir para o início',
        onPrimaryAction: _goHome,
      ),
    };
    return AppFadeThroughSwitcher(switchKey: _step, child: screen);
  }
}
