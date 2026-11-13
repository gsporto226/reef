// The browser's acceptance flows (docs/integration-apps.md), against an
// in-test localhost server: no test touches the internet.
import 'dart:io';

import 'package:browser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';

const fixtures = {
  '/links.html':
      '<!doctype html><title>Links fixture</title>'
      '<h1>Links fixture</h1><a href="/two.html">Go to page two</a>',
};

final addressBar = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Address bar',
  ),
  matching: find.byType(EditableText),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final body = fixtures[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? 'missing')
        ..close();
    });
  });
  tearDownAll(() => server.close(force: true));

  Future<BrowserAppState> boot(WidgetTester tester) async {
    await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    return tester.state<BrowserAppState>(find.byType(BrowserApp));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(addressBar, text);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
  }

  /// [js] in the focused window's page, once it gives a non-null result.
  Future<Object?> evaluate(
    WidgetTester tester,
    BrowserAppState app,
    String js,
  ) async {
    for (var i = 0; i < 100; i++) {
      final web = app.webViews[app.controller.doc.value.activeWindowId];
      final result = await web?.evaluateJavascript(source: js);
      if (result != null) return result;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('No result for $js');
  }

  testWidgets('typing a fixture URL shows it in the focused window', (
    tester,
  ) async {
    final app = await boot(tester);
    final url = 'http://127.0.0.1:${server.port}/links.html';

    await type(tester, url);

    expect(app.focusedRoute, WebPage.of(Uri.parse(url)));
    expect(
      await evaluate(
        tester,
        app,
        "document.readyState == 'complete' ? document.title : null",
      ),
      'Links fixture',
    );
    expect(await evaluate(tester, app, 'location.href'), url);
  });

  testWidgets('an unknown internal path shows not-found', (tester) async {
    final app = await boot(tester);

    await type(tester, '/nope');

    expect(app.focusedRoute, const NotFoundRoute(['nope']));
    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('/nope'), findsWidgets);
  });
}
