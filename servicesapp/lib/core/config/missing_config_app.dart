import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'supabase_config.dart';

/// Ecrã mostrado quando a app foi compilada sem `SUPABASE_URL` ou
/// `SUPABASE_ANON_KEY` (`--dart-define`). Antes a app arrancava contra um
/// URL vazio e só mostrava erros soltos (AUD-04, auditoria de 13/11).
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) {
          final textTheme = Theme.of(context).textTheme;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Build sem configuração',
                      style: textTheme.titleLarge
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Faltam ${SupabaseConfig.missingKeys.join(' e ')}. '
                      'Volta a compilar com os --dart-define do '
                      '.vscode/launch.json (ver docs/SETUP.md).',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
