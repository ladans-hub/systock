import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/widgets/platform_controls.dart';

void main() {
  for (final external in [false, true]) {
    testWidgets(
      'clear follows text and notifies search (external: $external)',
      (tester) async {
        final controller = external ? TextEditingController() : null;
        addTearDown(() => controller?.dispose());
        final changes = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: AdaptiveSearchField(
                hintText: 'Pesquisar',
                controller: controller,
                onChanged: changes.add,
                trailing: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
        );
        expect(find.byIcon(Icons.clear), findsNothing);
        await tester.enterText(find.byType(EditableText), 'feijao');
        await tester.pump();
        expect(find.byIcon(Icons.clear), findsOneWidget);
        expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();
        expect(changes, ['feijao', '']);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          isEmpty,
        );
        expect(find.byIcon(Icons.clear), findsNothing);
        if (controller != null) {
          controller.text = '12345678';
          await tester.pump();
          expect(find.byIcon(Icons.clear), findsOneWidget);
          await tester.tap(find.byIcon(Icons.clear));
          await tester.pump();
          expect(controller.text, isEmpty);
          expect(changes.last, '');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
