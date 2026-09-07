import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/widgets/error_dialog.dart';

void main() {
  testWidgets(
    'error stays visible until Close and exposes selectable details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppFailure(
                  context,
                  const StorageFailure(
                    'Falha ao guardar.',
                    cause: 'Ficheiro em uso (32)',
                  ),
                ),
                child: const Text('Testar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Testar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ficheiro em uso (32)'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.cancel_outlined));
      expect(icon.color, Colors.red.shade700);
      await tester.pump(const Duration(seconds: 10));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
