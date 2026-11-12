import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import 'link_nesting_test.dart' show tree;
import 'nesting_routes.dart';

const project = ProjectRoute('p1');
const task = TaskRoute(project, 't9');

void main() {
  Future<LinkNavigator<AppRoute>> pump(WidgetTester tester) async {
    final controller = WindowingController(
      initial: () {
        final d = WindowingDoc.initial();
        return NewTab(
          shellId: d.focusedShellId,
          tabId: const TabId.manual('t'),
          buffer: (const WindowId.manual('w'), tree.linkOf(project).buffer),
        ).apply(d);
      },
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: controller,
          delegate: WindowingDelegate(
            // Task pages fade in; every other route type switches at once.
            pageTransition: (buffer) => switch (tree.routeOfBuffer(buffer)) {
              TaskRoute() => const PageTransition(
                duration: Duration(milliseconds: 100),
                builder: _fade,
              ),
              _ => null,
            },
          ),
          bufferBuilder: (_, buffer) =>
              Text('${tree.routeOfBuffer(buffer).runtimeType}'),
        ),
      ),
    );
    return LinkNavigator(tree, controller);
  }

  testWidgets('the route type picks the transition that runs', (
    tester,
  ) async {
    final nav = await pump(tester);
    nav.push(task);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('TaskRoute'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, closeTo(0.5, 0.01));

    await tester.pumpAndSettle();
    expect(find.text('ProjectRoute'), findsNothing);
    expect(find.text('TaskRoute'), findsOneWidget);
  });

  testWidgets('going back to a page still animating out reuses it', (
    tester,
  ) async {
    final nav = await pump(tester);
    nav.push(task);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    nav.back();
    await tester.pump();
    expect(tester.takeException(), isNull);
    nav.forward();
    await tester.pump();
    nav.back();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('ProjectRoute'), findsOneWidget);
    expect(find.text('TaskRoute'), findsNothing);
  });

  testWidgets('a route type without a transition switches at once', (
    tester,
  ) async {
    final nav = await pump(tester);
    nav.push(const ProjectRoute('p2'));
    await tester.pump();
    expect(find.text('ProjectRoute'), findsOneWidget);
    expect(find.byType(FadeTransition), findsNothing);
  });
}

Widget _fade(Widget child, Animation<double> animation) =>
    FadeTransition(opacity: animation, child: child);
