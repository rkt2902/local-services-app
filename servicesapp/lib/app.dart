import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/application/session_provider.dart';
import 'features/notifications/application/notification_handler.dart';
import 'features/notifications/application/notification_providers.dart';
import 'features/notifications/application/push_notification_service.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  StreamSubscription<String>? _pushTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!PushNotificationService.isEnabled) return;

    final push = ref.read(pushNotificationServiceProvider);
    // Regista o token FCM sempre que há um utilizador com sessão (arranque
    // com sessão guardada, login, troca de conta). O logout remove-o em
    // AuthController.signOut.
    ref.listenManual<String?>(currentUserIdProvider, (prev, next) {
      if (next != null && next != prev) push.registerForCurrentUser();
    }, fireImmediately: true);
    _pushTapSub = push.openedNotificationIds().listen(_onPushTapped);
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Toque num push: abre o mesmo destino que o toque na lista in-app.
  Future<void> _onPushTapped(String notificationId) async {
    try {
      // Cold start: esperar que a sessão resolva antes de navegar, senão o
      // redirect de /loading sobrepõe-se à navegação.
      final session = await ref.read(sessionStatusProvider.future);
      if (!session.isAuthenticated) return;
      final repo = ref.read(notificationRepositoryProvider);
      final notification = await repo.fetchById(notificationId);
      if (notification == null) return;
      await WidgetsBinding.instance.endOfFrame;
      final navContext =
          ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      await NotificationHandler.handle(navContext, ref, notification);
      await repo.markAsRead(notification.id);
      ref.invalidate(allNotificationsProvider);
    } catch (e) {
      debugPrint('Push: falha a abrir notificação $notificationId ($e)');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(sessionStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationSyncProvider);
    final router = ref.watch(appRouterProvider);
    // AnnotatedRegion (não uma chamada única a SystemChrome em main.dart)
    // para o estilo sobreviver a resumes/mudanças de UI do sistema — uma
    // só definição para a app toda, nunca por ecrã (ver app_theme.dart).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle,
      child: MaterialApp.router(
        title: 'ProJardim',
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }
}
