import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'features/notifications/application/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: URLs limpas (/w/<id> em vez de /#/w/<id>). Exige que o alojamento
  // devolva index.html para qualquer caminho (ver docs/web.md). Sem efeito
  // em Android/iOS.
  usePathUrlStrategy();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  await PushNotificationService.initFirebase();

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
