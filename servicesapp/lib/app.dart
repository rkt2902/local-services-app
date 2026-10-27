import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_toast.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/application/session_provider.dart';
import 'features/notifications/application/notification_handler.dart';
import 'features/notifications/application/notification_presentation.dart';
import 'features/notifications/application/notification_providers.dart';
import 'features/notifications/application/push_notification_service.dart';
import 'features/notifications/data/notification_model.dart';

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
    // Com a app aberta o sistema não mostra o push: aviso no topo, com o
    // estilo da app, para cada notificação que chega pelo Realtime.
    ref.listenManual<AsyncValue<List<AppNotification>>>(
      notificationsStreamProvider,
      (prev, next) => _showNotificationBanner(
        prev?.asData?.value,
        next.asData?.value,
      ),
    );
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

  void _showNotificationBanner(
    List<AppNotification>? before,
    List<AppNotification>? after,
  ) {
    if (after == null) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final notification = notificationForBanner(before, after);
    if (notification == null) return;
    final router = ref.read(appRouterProvider);
    // No ecrã de notificações a lista já mostra a nova.
    final path = router.state.uri.path;
    if (path == '/notifications' || path == '/client/alerts') return;
    final navContext = router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    final look = notificationLook(notification.type);
    final texts = notificationBannerTexts(notification);
    AppToast.maybeOf(navContext)?.notification(
      title: texts.title,
      body: texts.body,
      icon: look.icon,
      color: look.tone,
      onTap: () => _openNotification(notification),
    );
  }

  /// Toque no aviso do topo: mesmo destino que na lista, e fica lida.
  Future<void> _openNotification(AppNotification notification) async {
    final repo = ref.read(notificationRepositoryProvider);
    try {
      await repo.markAsRead(notification.id);
    } catch (_) {
      // Sem rede: abre na mesma, fica por ler.
    }
    final navContext =
        ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    await NotificationHandler.handle(navContext, ref, notification);
    ref.invalidate(allNotificationsProvider);
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
        // Só português de Portugal: sem isto os seletores de data e hora
        // apareciam em inglês ("Select time", AM/PM).
        locale: const Locale('pt', 'PT'),
        supportedLocales: const [Locale('pt', 'PT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scrollBehavior: const _AppScrollBehavior(),
        routerConfig: router,
      ),
    );
  }
}

/// Na web (PC) deixa arrastar com o rato e o trackpad as listas e o
/// PageView do onboarding, como no telemóvel se arrasta com o dedo. Por
/// defeito o Flutter não aceita arrasto de rato; o resto fica igual.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
