// ADR 0008: a link's page identity decides which entries share one mounted
// page.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

sealed class R {
  const R();
}

final class MissingRoute extends R {
  const MissingRoute(this.path);
  final List<String> path;
}

/// `/site/{site}/{page}`: one page per site.
final class SiteRoute extends R {
  const SiteRoute(this.site, this.page);
  final String site;
  final String page;
}

final class ItemRoute extends R {
  const ItemRoute(this.id);
  final String id;
}

final tree = LinkTree<R>([
  Link<MissingRoute>('').rest((r) => r.path).build(MissingRoute.new),
  Link<SiteRoute>('site')
      .field((r) => r.site)
      .field((r) => r.page)
      .build(SiteRoute.new)
      .identity((r) => r.site),
  Link<ItemRoute>('items').field((r) => r.id).build(ItemRoute.new),
]);

BufferId buffer(R route) => tree.linkOf(route).buffer;

void main() {
  test('without an identity, a link\'s page identity is its buffer', () {
    final b = buffer(const ItemRoute('1'));
    expect(tree.pageIdentityOf(b), b);
    expect(
      tree.pageIdentityOf(b),
      isNot(tree.pageIdentityOf(buffer(const ItemRoute('2')))),
    );
  });

  test('entries with equal identities share one identity', () {
    final a = tree.pageIdentityOf(buffer(const SiteRoute('x', 'a')));
    expect(a, tree.pageIdentityOf(buffer(const SiteRoute('x', 'b'))));
    expect(a, isNot(tree.pageIdentityOf(buffer(const SiteRoute('y', 'a')))));
  });

  group('the mounted page', () {
    late int mounts;

    Future<LinkNavigator<R>> pump(WidgetTester tester) async {
      mounts = 0;
      final controller = WindowingController(
        initial: () {
          final d = WindowingDoc.initial();
          return NewTab(
            shellId: d.focusedShellId,
            tabId: const TabId.manual('t'),
            buffer: (
              const WindowId.manual('w'),
              buffer(const SiteRoute('x', 'a')),
            ),
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
              pageIdentity: tree.pageIdentityOf,
              pageTransition: (_) => _transition,
            ),
            bufferBuilder: (_, b) => _Page(b, () => mounts++),
          ),
        ),
      );
      return LinkNavigator(tree, controller);
    }

    testWidgets('stays mounted through push, replace, back and forward '
        'within its identity, rebuilt with the new buffer and no '
        'transition', (tester) async {
      final nav = await pump(tester);
      expect(mounts, 1);

      nav.push(const SiteRoute('x', 'b'));
      await tester.pump();
      expect(find.text('x/b'), findsOneWidget);
      expect(find.text('x/a'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);

      nav.replace(const SiteRoute('x', 'c'));
      await tester.pump();
      expect(find.text('x/c'), findsOneWidget);
      nav.back();
      await tester.pump();
      expect(find.text('x/a'), findsOneWidget);
      nav.forward();
      await tester.pump();
      expect(find.text('x/c'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(mounts, 1);
    });

    testWidgets('remounts, with its transition, for another identity', (
      tester,
    ) async {
      final nav = await pump(tester);
      nav.push(const SiteRoute('y', 'a'));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('y/a'), findsOneWidget);
      expect(mounts, 2);

      nav.push(const ItemRoute('1'));
      await tester.pumpAndSettle();
      nav.push(const ItemRoute('2'));
      await tester.pumpAndSettle();
      expect(mounts, 4);
    });
  });
}

class _Page extends StatefulWidget {
  const _Page(this.buffer, this.onMount);

  final BufferId buffer;
  final VoidCallback onMount;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      Text(switch (tree.routeOfBuffer(widget.buffer)) {
        SiteRoute(:final site, :final page) => '$site/$page',
        final r => '$r',
      });
}

final _transition = PageTransition(
  duration: const Duration(milliseconds: 100),
  builder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);
