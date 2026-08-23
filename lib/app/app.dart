import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/app/router/app_router.dart';
import 'package:systock/app/theme/app_theme.dart';
import 'package:systock/app/theme/theme_controller.dart';
import 'package:systock/core/security/session_lifecycle.dart';
import 'package:systock/l10n/generated/app_localizations.dart';

class SystockApp extends ConsumerWidget {
  const SystockApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Systock',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ref.watch(themeModeProvider),
    locale: ref.watch(appLocaleProvider),
    routerConfig: appRouter,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, child) =>
        SessionLifecycle(child: child ?? const SizedBox.shrink()),
  );
}
