import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/json_file_hibernation_store.dart';
import 'package:reef_example/undo_providers.dart';
import 'package:reef_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saving a task runs the save operation to a ready state',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved yet'), findsOneWidget);

    await tester.tap(find.text('Save (submit style)'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pumpAndSettle();
    expect(find.text('Saved!'), findsOneWidget);
  });

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

  testWidgets('system back steps the editor window back to the list',
      (tester) async {
    await tester.pumpWidget(
      app.ReefExampleApp(store: InMemoryHibernationStore()),
      wrapWithView: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    final editor = find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'Buy milk');
    expect(editor, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(editor, findsNothing, reason: 'the editor window stepped back');
    expect(find.byType(EditableText), findsNWidgets(2),
        reason: 'two lists, each with its filter');
  });

  testWidgets('the route follows the focused task, and a route opens one',
      (tester) async {
    final route = _Route();
    await tester.pumpWidget(
      app.ReefExampleApp(
        store: InMemoryHibernationStore(),
        routeInformationProvider: route,
      ),
      wrapWithView: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    expect(route.value.uri.path, '/tasks/Buy%20milk/edit');

    route.browse('/tasks/Walk%20dog/edit');
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is EditableText && w.controller.text == 'Walk dog'),
        findsOneWidget);
    expect(route.value.uri.path, '/tasks/Walk%20dog/edit');
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

  testWidgets('a task path as a launch argument opens that editor on top of '
      'the restored layout', (tester) async {
    final store = InMemoryHibernationStore();
    await tester.pumpWidget(
      app.ReefExampleApp(store: store),
      wrapWithView: false,
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox()); // tears the app down
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      app.ReefExampleApp(store: store, launchArgs: const ['/tasks/Walk dog/edit']),
      wrapWithView: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Walk dog'),
      findsOneWidget,
      reason: 'the linked editor is open',
    );
    expect(find.text('Buy milk'), findsOneWidget,
        reason: 'the restored list is kept beside it');
  });

  group('on a file store', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('reef_example_app');
      file = File('${dir.path}/store.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> boot(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox()); // tears any app down
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app.ReefExampleApp(store: JsonFileHibernationStore.load(file)),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();
    }

    Finder titled(String text) => find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == text);

    testWidgets('layout and an edited title come back after a restart, and '
        '"Reset layout" returns to the first-run layout', (tester) async {
      await boot(tester);
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.enterText(titled('Buy milk'), 'Buy bread');
      await tester.pumpAndSettle();

      await boot(tester);
      expect(titled('Buy bread'), findsOneWidget,
          reason: 'the editor window and its edited title are restored');

      await tester.tap(find.text('Reset layout'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget, reason: 'filter only');

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      expect(titled('Buy bread'), findsOneWidget,
          reason: 'the buffer survives the reset');
    });

    testWidgets('an unreadable file starts on the first-run layout',
        (tester) async {
      file.writeAsStringSync('{not json');
      await boot(tester);

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget, reason: 'filter only');
    });
  });
}

/// A route information provider standing in for the browser.
class _Route extends RouteInformationProvider with ChangeNotifier {
  RouteInformation _value = RouteInformation(uri: Uri.parse('/'));

  @override
  RouteInformation get value => _value;

  void browse(String uri) {
    _value = RouteInformation(uri: Uri.parse(uri));
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(RouteInformation routeInformation,
          {RouteInformationReportingType type =
              RouteInformationReportingType.none}) =>
      _value = routeInformation;
}
