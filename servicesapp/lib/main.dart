import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/missing_config_app.dart';
import 'core/config/supabase_config.dart';
import 'core/services/crash_reporting.dart';
import 'features/notifications/application/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: URLs limpas (/w/<id> em vez de /#/w/<id>). Exige que o alojamento
  // devolva index.html para qualquer caminho (ver docs/web.md). Sem efeito
  // em Android/iOS.
  usePathUrlStrategy();

  // AUD-17: a fonte vem de assets/google_fonts/, sem pedir nada à Google
  // (funciona sem rede no primeiro arranque e não envia o IP).
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['google_fonts'], license);
  });

  // AUD-04: sem as chaves do Supabase a app não tem backend; mostra o que
  // falta em vez de arrancar contra um URL vazio.
  if (!SupabaseConfig.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  await PushNotificationService.initFirebase();
  await CrashReporting.init(
    firebaseReady: PushNotificationService.isEnabled,
  );

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
