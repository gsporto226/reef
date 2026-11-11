import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/undo_providers.dart';
import 'package:reef_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without the windowing flag the app boots inline, with no pop-out '
      'controls, and opens a task in an editor',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.byType(EditableText), findsWidgets);
    for (final label in [
      'Open in window',
      'New shell',
      'Pop out tab',
      'Close shell',
    ]) {
      expect(find.text(label), findsNothing,
          reason: 'windowing is off: no pop-out controls');
    }
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

  testWidgets(
    'the layout comes back after the app restarts on the same store',
    (tester) async {
      final store = InMemoryHibernationStore();
      await tester.pumpWidget(
        app.ReefExampleApp(store: store),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget, reason: 'filter only');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsWidgets);

      await tester.pumpWidget(const SizedBox()); // tears the app down
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app.ReefExampleApp(store: store),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Buy milk',
        ),
        findsOneWidget,
        reason: 'the editor window is restored',
      );
    },
  );
}
