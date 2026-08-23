import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/l10n/localized_text.dart';

void main() {
  testWidgets('fixed application copy follows the active locale', (
    tester,
  ) async {
    Future<void> pump(Locale locale) => tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('pt'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: LocalizedText('Relatórios')),
      ),
    );

    await pump(const Locale('pt'));
    expect(find.text('Relatórios'), findsOneWidget);

    await pump(const Locale('en'));
    expect(find.text('Reports'), findsOneWidget);
  });

  testWidgets('ordinary business data is never translated implicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('pt'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: Text('Produto do cliente')),
      ),
    );

    expect(find.text('Produto do cliente'), findsOneWidget);
  });
}
