import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef_example/undo_providers.dart';
import 'package:reef_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app boots on a real device and opens a task in an editor',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.byType(EditableText), findsWidgets);
  });

  testWidgets('undo and redo a title edit', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    final title = find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'Buy milk');
    final text = tester.widget<EditableText>(title).controller;
    final undo = ProviderScope.containerOf(tester.element(title))
        .read(undoControllerProvider);
    await tester.enterText(title, 'Buy bread');
    await tester.pumpAndSettle();

    expect(undo.$canUndo.value, isTrue);
    undo.undo();
    await tester.pumpAndSettle();
    expect(text.text, 'Buy milk');

    undo.redo();
    await tester.pumpAndSettle();
    expect(text.text, 'Buy bread');
  });
}
