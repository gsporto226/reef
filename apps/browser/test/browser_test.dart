import 'package:browser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

/// The address bar's text field, found by its semantics label.
final addressBar = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Address bar',
  ),
  matching: find.byType(EditableText),
);

void main() {
  const page = WebPage('http', Host('127.0.0.1:8080'), [
    'docs',
    'a b.html',
  ], 'x=1&y=2');

  group('link tree', () {
    test('a web page round-trips through /web/{scheme}/{host}/**', () {
      final uri = links.uriOf(page);
      expect(uri.pathSegments, [
        'web',
        'http',
        '127.0.0.1:8080',
        'docs',
        'a b.html',
      ]);
      // The site's whole query is one opaque argument (D15).
      expect(uri.queryParameters, {'q': 'x=1&y=2'});
      expect(links.routeOf(uri), page);
      final (:buffer, :arguments) = links.linkOf(page);
      expect(links.routeOfBuffer(buffer, arguments), page);
    });

    test('an empty query is left out of the URL', () {
      const bare = WebPage('https', Host('example.com'), [], '');
      expect(links.uriOf(bare).hasQuery, isFalse);
      expect(links.routeOf(links.uriOf(bare)), bare);
    });

    test('every new tab page is its own buffer', () {
      expect(
        links.linkOf(const NewTabRoute()).buffer,
        isNot(links.linkOf(const NewTabRoute()).buffer),
      );
    });

    test('an unknown internal path is not found', () {
      expect(
        links.routeOf(Uri.parse('/nope/x')),
        const NotFoundRoute(['nope', 'x']),
      );
    });
  });

  group('address bar input', () {
    test('a web URL is that page', () {
      expect(
        routeOfInput('http://127.0.0.1:8080/docs/a%20b.html?x=1&y=2'),
        page,
      );
      expect(addressOf(page), 'http://127.0.0.1:8080/docs/a%20b.html?x=1&y=2');
    });

    test('a path is an internal page', () {
      expect(routeOfInput('/nope'), const NotFoundRoute(['nope']));
      expect(addressOf(const NotFoundRoute(['nope'])), '/nope');
    });

    test('a bare host is https', () {
      expect(
        routeOfInput('example.com/a'),
        const WebPage('https', Host('example.com'), ['a'], ''),
      );
    });
  });

  testWidgets('boots on a new tab; an unknown internal path shows not-found', (
    tester,
  ) async {
    await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    expect(find.text('New tab'), findsOneWidget);

    await tester.enterText(addressBar, '/nope');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    final c = tester.state<BrowserAppState>(find.byType(BrowserApp)).controller;
    final doc = c.doc.value;
    expect(
      links.routeOfBuffer(
        doc.windows[doc.activeWindowId]!.history.current.buffer,
      ),
      const NotFoundRoute(['nope']),
    );
  });
}
