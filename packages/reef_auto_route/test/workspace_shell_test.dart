import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';
import 'package:reef_auto_route/reef_auto_route.dart';

WorkspaceRegistry _registry() => WorkspaceRegistry(kinds: {
      'task-edit': (_, id) =>
          Text('edit:${id.id}', textDirection: TextDirection.ltr),
      'task-list': (_, id) =>
          Text('list:${id.id}', textDirection: TextDirection.ltr),
    });

(Widget, StackRouter) _app() {
  final router = RootStackRouter.build(routes: [
    NamedRouteDef(
      name: 'Home',
      path: '/',
      builder: (_, _) => const SizedBox.shrink(),
    ),
    NamedRouteDef(
      name: 'WorkspaceRoute',
      path: '/w/:tabId',
      builder: (context, data) => WorkspaceShell(
        tabId: data.params.getString('tabId'),
        registry: _registry(),
      ),
    ),
  ]);
  return (
    ProviderScope(
      child: WidgetsApp.router(color: const Color(0xFF00695C), routerConfig: router.config()),
    ),
    router
  );
}

SplitTreeController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      // .first: a route replace can transiently mount the old and the new
      // shell — both watch the same controller.
      tester.element(find.byType(WorkspaceShell).first),
    ).read(workspaceControllerProvider('main'));

void main() {
  group('WorkspaceShell — deep links', () {
    testWidgets('?b=<kind:token> opens the buffer in an empty workspace',
        (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main?b=task-edit:1');
      await tester.pump();
      await tester.pump();

      expect(find.text('edit:task-edit:1'), findsOneWidget);
      final controller = _controller(tester);
      expect(controller.$focused.value?.id, 'task-edit:1');
      expect(controller.$root.value, isA<LeafSplitNode>());
    });

    testWidgets('?b= of an already-open buffer focuses it — no re-open',
        (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main?b=task-edit:1');
      await tester.pump();
      await tester.pump();

      _controller(tester)
          .split(BufferId.manual('task-edit:2'), axis: Axis.horizontal);
      await tester.pump();
      await tester.pump();

      router.pushPath('/w/main?b=task-edit:1');
      await tester.pump();
      await tester.pump();

      final controller = _controller(tester);
      expect(controller.$focused.value?.id, 'task-edit:1');
      expect(controller.$root.value, isA<SplitBranchNode>(),
          reason: 'focusing must not collapse or rebuild the split');
    });

    testWidgets('no b param leaves the workspace untouched', (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main');
      await tester.pump();
      await tester.pump();

      expect(_controller(tester).$root.value, isNull);
      expect(find.byType(WorkspaceShell), findsOneWidget);
    });

    testWidgets('WorkspaceScope exposes the tab controller inside panes',
        (tester) async {
      final router = RootStackRouter.build(routes: [
        NamedRouteDef(
          name: 'Home',
          path: '/',
          builder: (_, _) => const SizedBox.shrink(),
        ),
        NamedRouteDef(
          name: 'WorkspaceRoute',
          path: '/w/:tabId',
          builder: (context, data) => WorkspaceShell(
            tabId: data.params.getString('tabId'),
            registry: WorkspaceRegistry(kinds: {
              'probe': (context, id) => Builder(
                    builder: (context) => Text(
                      'focused:${WorkspaceScope.of(context).$focused.value?.id}',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
            }),
          ),
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(child: WidgetsApp.router(color: const Color(0xFF00695C), routerConfig: router.config())),
      );
      router.pushPath('/w/main?b=probe:x');
      await tester.pump();
      await tester.pump();

      expect(find.text('focused:probe:x'), findsOneWidget);
    });

    testWidgets('panes render through the registry', (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main');
      await tester.pump();
      await tester.pump();

      _controller(tester).open(BufferId.manual('task-list:9'));
      await tester.pump();
      await tester.pump();

      expect(find.text('list:task-list:9'), findsOneWidget);
    });
  });

  group('WorkspaceShell — URL sync', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    testWidgets('focus change rewrites the URL query', (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main');
      await tester.pump();
      await tester.pump();

      _controller(tester).open(BufferId.manual('task-edit:1'));
      await settle(tester);

      final data = RouteData.of(tester.element(find.byType(WorkspaceShell)));
      expect(data.queryParams.optString('b'), 'task-edit:1');
    });

    testWidgets('the replace keeps the same controller and the split tree',
        (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main?b=task-edit:1');
      await tester.pump();
      await tester.pump();

      final controller = _controller(tester);
      controller
          .split(BufferId.manual('task-edit:2'), axis: Axis.horizontal);
      await settle(tester);

      final data = RouteData.of(tester.element(find.byType(WorkspaceShell)));
      expect(data.queryParams.optString('b'), 'task-edit:2',
          reason: 'the split focused the new buffer — URL follows');

      expect(_controller(tester), same(controller),
          reason: 'the URL rewrite must reattach, not rebuild');
      expect(_controller(tester).$root.value, isA<SplitBranchNode>(),
          reason: 'both panes must survive the URL rewrite');
    });

    testWidgets('unroutable focus drops the b param', (tester) async {
      final (app, router) = _app();
      await tester.pumpWidget(app);
      router.pushPath('/w/main?b=task-edit:1');
      await tester.pump();
      await tester.pump();

      _controller(tester).open(BufferId.generate());
      await settle(tester);

      final data = RouteData.of(tester.element(find.byType(WorkspaceShell)));
      expect(data.queryParams.optString('b'), isNull);
    });
  });
}


