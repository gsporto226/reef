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
            // Task pages and project p1 animate; the rest switch at once.
            pageTransition: (buffer) => switch (tree.routeOfBuffer(buffer)) {
              TaskRoute() || ProjectRoute(id: 'p1') => _transition,
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

  _Probe probe(WidgetTester tester, String text) => tester.widget<_Probe>(
    find.ancestor(of: find.text(text), matching: find.byType(_Probe)),
  );

  testWidgets('push plays the incoming page forward over the covered one', (
    tester,
  ) async {
    final nav = await pump(tester);
    nav.push(task);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(probe(tester, 'TaskRoute').animation.value, closeTo(0.5, 0.01));
    expect(probe(tester, 'ProjectRoute').animation.value, 1);
    expect(
      probe(tester, 'ProjectRoute').secondary.value,
      closeTo(0.5, 0.01),
    );

    await tester.pumpAndSettle();
    expect(find.text('ProjectRoute'), findsNothing);
    expect(find.text('TaskRoute'), findsOneWidget);
  });

  testWidgets('back plays the leaving page in reverse', (tester) async {
    final nav = await pump(tester);
    nav.push(task);
    await tester.pumpAndSettle();
    nav.back();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    expect(probe(tester, 'TaskRoute').animation.value, closeTo(0.75, 0.01));
    expect(
      probe(tester, 'ProjectRoute').secondary.value,
      closeTo(0.75, 0.01),
    );

    await tester.pumpAndSettle();
    expect(find.text('TaskRoute'), findsNothing);
    expect(probe(tester, 'ProjectRoute').secondary.value, 0);
  });

  testWidgets('replace plays only the incoming page', (tester) async {
    final nav = await pump(tester);
    nav.replace(task);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(probe(tester, 'TaskRoute').animation.value, closeTo(0.5, 0.01));
    expect(probe(tester, 'ProjectRoute').secondary.value, 0);

    await tester.pumpAndSettle();
    expect(find.text('ProjectRoute'), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 25));
    expect(tester.takeException(), isNull);
    expect(probe(tester, 'TaskRoute').animation.value, closeTo(0.25, 0.01));
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
    expect(find.byType(_Probe), findsNothing);
    nav.back();
    await tester.pump();
    expect(find.text('ProjectRoute'), findsOneWidget);
    expect(probe(tester, 'ProjectRoute').secondary.value, 0);
  });
}

class _Probe extends StatelessWidget {
  const _Probe(this.animation, this.secondary, this.child);

  final Animation<double> animation;
  final Animation<double> secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

const _transition = PageTransition(
  duration: Duration(milliseconds: 100),
  builder: _probe,
);

Widget _probe(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) => _Probe(animation, secondary, child);
