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

final class DraftRoute extends R {
  const DraftRoute(this.to);
  final String? to;
}

final class ItemRoute extends R {
  const ItemRoute(this.id);
  final String id;
}

final tree = LinkTree<R>([
  Link<MissingRoute>('').rest((r) => r.path).build(MissingRoute.new),
  Link<DraftRoute>('compose').query('to', (r) => r.to, fallback: null).build(DraftRoute.new)
      .fresh(),
  Link<ItemRoute>('items').field((r) => r.id).build(ItemRoute.new),
]);

void main() {
  test('a fresh link gives a new buffer each time, its URL without the '
      'suffix', () {
    final a = tree.linkOf(const DraftRoute('x@y'));
    final b = tree.linkOf(const DraftRoute('x@y'));
    expect(a.buffer, isNot(b.buffer));
    expect(a.arguments, {'to': 'x@y'});
    expect(tree.uriOfBuffer(a.buffer, a.arguments).toString(),
        '/compose?to=x%40y');
    expect((tree.routeOfBuffer(a.buffer, a.arguments) as DraftRoute).to,
        'x@y');
    expect(tree.resolve(Uri.parse('/compose')).buffer,
        isNot(tree.resolve(Uri.parse('/compose')).buffer));
    expect(tree.isFresh(a.buffer), isTrue);
  });

  test('the call site overrides the link, the link the tree', () {
    expect(tree.linkOf(const ItemRoute('1')).buffer,
        tree.linkOf(const ItemRoute('1')).buffer);
    final f = tree.linkOf(const ItemRoute('1~2'), fresh: true).buffer;
    expect(tree.isFresh(f), isTrue);
    expect((tree.routeOfBuffer(f) as ItemRoute).id, '1~2');
    expect(tree.isFresh(tree.linkOf(const DraftRoute(null), fresh: false)
        .buffer), isFalse);
    final all = LinkTree<R>([
      Link<MissingRoute>('').rest((r) => r.path).build(MissingRoute.new),
      Link<ItemRoute>('items').field((r) => r.id).build(ItemRoute.new)
          .fresh(false),
      Link<DraftRoute>('compose').query('to', (r) => r.to, fallback: null)
          .build(DraftRoute.new),
    ], fresh: true);
    expect(all.isFresh(all.linkOf(const DraftRoute(null)).buffer), isTrue);
    expect(all.isFresh(all.linkOf(const ItemRoute('1')).buffer), isFalse);
  });

  group('navigation', () {
    late WindowingController controller;
    late LinkNavigator<R> nav;
    setUp(() {
      controller = WindowingController(openPolicy: splitBesideOpenPolicy);
      nav = LinkNavigator(tree, controller);
    });
    tearDown(() => controller.dispose());
    WindowingDoc doc() => controller.doc.value;

    test('go on a fresh link pushes into the focused window; two goes are '
        'two buffers', () async {
      await nav.go(const ItemRoute('1'));
      final w = doc().activeWindowId!;
      await nav.go(const DraftRoute(null));
      await nav.go(const DraftRoute(null));
      expect(doc().windows, hasLength(1));
      final h = doc().windows[w]!.history;
      expect(h.back, hasLength(2));
      expect(h.current.buffer, isNot(h.back.last.buffer));
    });

    test('shared links focus the window already showing them', () async {
      await nav.go(const ItemRoute('1'));
      final w = doc().activeWindowId!;
      nav.openInSplit(const ItemRoute('2'));
      expect(doc().activeWindowId, isNot(w));
      await nav.go(const ItemRoute('1'));
      expect(doc().activeWindowId, w);
      expect(doc().windows, hasLength(2));
    });
  });
}
