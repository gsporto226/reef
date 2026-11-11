import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/main.dart';

void main() {
  testWidgets('the app opens the task list through WindowingRoot; tapping a '
      'task splits an editor window beside it', (tester) async {
    // Desktop width: the default projection lays windows side by side.
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithView: false, const ReefExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(WindowingRoot), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(
      find.text('New shell'),
      findsNothing,
      reason: 'windowing is off: no pop-out controls',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ListView),
      findsOneWidget,
      reason: 'the list window survives the split',
    );
    expect(find.byType(WindowHost), findsNWidgets(2));
    expect(
      find.byType(EditableText),
      findsNWidgets(2),
      reason: 'list filter + the new editor window',
    );
  });

  group('an edited title hibernates when the app', () {
    Future<InMemoryHibernationStore> edit(WidgetTester tester) async {
      final store = InMemoryHibernationStore();
      await tester.pumpWidget(
        wrapWithView: false,
        ReefExampleApp(store: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Buy milk',
        ),
        'Buy bread',
      );
      await tester.pumpAndSettle();
      return store;
    }

    String saved(HibernationStore store) =>
        '${store.load(const BufferId.manual('task-edit:Buy milk'))}';

    testWidgets('is asked to exit', (tester) async {
      final store = await edit(tester);
      expect(saved(store), isNot(contains('Buy bread')));
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      expect(saved(store), contains('Buy bread'));
    });

    testWidgets('detaches', (tester) async {
      final store = await edit(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      expect(saved(store), contains('Buy bread'));
    });
  });
}
