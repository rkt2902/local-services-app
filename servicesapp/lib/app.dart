import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/session_provider.dart';
import 'features/notifications/application/notification_providers.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
