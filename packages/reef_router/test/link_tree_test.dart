import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import '../tool/generate_link_stages.dart' as stages;

enum Sort { recent, oldest }

sealed class AppRoute {
  const AppRoute();
}

final class HomeRoute extends AppRoute {
  const HomeRoute();

  static final link = Link<HomeRoute>('').build(HomeRoute.new);

  @override
  bool operator ==(Object other) => other is HomeRoute;

  @override
  int get hashCode => 0;
}

final class ItemRoute extends AppRoute {
  const ItemRoute(this.id, {this.sort = Sort.recent, this.q});
  final int id;
  final Sort sort;
  final String? q;

  static final link = Link<ItemRoute>('items')
      .field((r) => r.id)
      .literal('view')
      .query(
        'sort',
        (r) => r.sort,
        fallback: Sort.recent,
        codec: .enumeration(Sort.values),
      )
      .query<String?>('q', (r) => r.q, fallback: null)
      .build((id, sort, q) => ItemRoute(id, sort: sort, q: q));

  @override
  bool operator ==(Object other) =>
      other is ItemRoute &&
      other.id == id &&
      other.sort == sort &&
      other.q == q;

  @override
  int get hashCode => Object.hash(id, sort, q);
}

final class NewItemRoute extends AppRoute {
  const NewItemRoute();

  static final link = Link<NewItemRoute>('items/new/view')
      .build(NewItemRoute.new);

  @override
  bool operator ==(Object other) => other is NewItemRoute;

  @override
  int get hashCode => 1;
}

final class NotFoundRoute extends AppRoute {
  const NotFoundRoute(this.path);
  final List<String> path;

  static final link = Link<NotFoundRoute>('')
      .rest((r) => r.path)
      .build(NotFoundRoute.new);

  @override
  bool operator ==(Object other) =>
      other is NotFoundRoute && other.path.join('/') == path.join('/');

  @override
  int get hashCode => path.join('/').hashCode;
}

final class XRoute extends AppRoute {
  const XRoute(this.id);
  final String id;
  static final link = Link<XRoute>('x').field((r) => r.id).build(XRoute.new);
}

final class YRoute extends AppRoute {
  const YRoute(this.id);
  final String id;
  static final link =
      Link<YRoute>('').field((r) => r.id).literal('y').build(YRoute.new);
}

final class ZRoute extends AppRoute {
  const ZRoute(this.id);
  final String id;
  static final link = Link<ZRoute>('z').field((r) => r.id).build(ZRoute.new);
}

final tree = LinkTree<AppRoute>([
  NotFoundRoute.link,
  ItemRoute.link,
  NewItemRoute.link,
  HomeRoute.link,
]);

AppRoute at(String uri) => tree.routeOf(Uri.parse(uri));

void main() {
  test('home mounts at /', () {
    expect(at('/'), const HomeRoute());
    expect(tree.uriOf(const HomeRoute()).toString(), '/');
  });

  test('path and query parts decode; fallbacks fill absent query keys', () {
    expect(at('/items/7/view'), const ItemRoute(7));
    expect(
      at('/items/7/view?sort=oldest&q=a%20b'),
      const ItemRoute(7, sort: Sort.oldest, q: 'a b'),
    );
  });

  test('fallback values stay out of the URL', () {
    expect(tree.uriOf(const ItemRoute(7)).toString(), '/items/7/view');
    expect(
      tree.uriOf(const ItemRoute(7, sort: Sort.oldest, q: 'x')).toString(),
      '/items/7/view?sort=oldest&q=x',
    );
  });

  test('a literal link beats a value link, whatever the declaration order', () {
    expect(at('/items/new/view'), const NewItemRoute());
  });

  test('a malformed value is no match, so the catch-all gets the path', () {
    expect(
      at('/items/abc/view'),
      const NotFoundRoute(['items', 'abc', 'view']),
    );
    expect(
      at('/items/1/view?sort=sideways'),
      const NotFoundRoute(['items', '1', 'view']),
    );
    expect(at('/nope/deeper'), const NotFoundRoute(['nope', 'deeper']));
    expect(
      tree.uriOf(const NotFoundRoute(['nope', 'a b'])).toString(),
      '/nope/a%20b',
    );
  });

  test('a tree without a root catch-all fails at startup', () {
    expect(() => LinkTree<AppRoute>([HomeRoute.link]), throwsStateError);
  });

  test(
    'a value type without an inferred codec fails when the link is built',
    () {
      expect(
        () => Link<Object>('x').field((r) => r).build((v) => v),
        throwsArgumentError,
      );
    },
  );

  test('a rest part must end the path', () {
    expect(
      () => Link<List<String>>('').rest((r) => r).literal('x').build((r) => r),
      throwsArgumentError,
    );
  });

  test('a route maps to a buffer and its arguments, and back', () {
    const route = ItemRoute(7, sort: Sort.oldest);
    final (:buffer, :arguments) = tree.linkOf(route);
    expect(buffer, BufferId.of('/items/*/view', '7'));
    expect(arguments, {'sort': 'oldest'});
    expect(tree.routeOfBuffer(buffer, arguments), route);
    expect(
      tree.uriOfBuffer(buffer, arguments).toString(),
      '/items/7/view?sort=oldest',
    );
    final resolved = tree.resolve(Uri.parse('/items/7/view?sort=oldest'));
    expect(resolved.buffer, buffer);
    expect(resolved.arguments, arguments);
  });

  test('tokens escape only % and /', () {
    const route = NotFoundRoute(['a/b', '50%', 'c d']);
    final buffer = tree.linkOf(route).buffer;
    expect(buffer, BufferId.of('/**', 'a%2Fb/50%25/c d'));
    expect(tree.routeOfBuffer(buffer), route);
  });

  test('a buffer whose kind no longer resolves opens the not-found route', () {
    expect(
      tree.routeOfBuffer(BufferId.of('/old/*', '5')),
      const NotFoundRoute(['old', '5']),
    );
    expect(
      tree.routeOfBuffer(const BufferId.manual('scratch')),
      const NotFoundRoute(['scratch']),
    );
    expect(
      tree.uriOfBuffer(BufferId.of('/old/*', '5')),
      isNull,
      reason: 'a buffer the tree did not mount has no URL',
    );
  });

  test('the committed link stages match the generator', () {
    expect(
      File('lib/src/link_stages.g.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n'),
      stages.generate(),
      reason: 'run dart tool/generate_link_stages.dart',
    );
  });

  test('a 20-value link builds', () {
    var link = Link<List<int>>('').field((r) => r[0]);
    final built = link
        .field((r) => r[1])
        .field((r) => r[2])
        .field((r) => r[3])
        .field((r) => r[4])
        .field((r) => r[5])
        .field((r) => r[6])
        .field((r) => r[7])
        .field((r) => r[8])
        .field((r) => r[9])
        .field((r) => r[10])
        .field((r) => r[11])
        .field((r) => r[12])
        .field((r) => r[13])
        .field((r) => r[14])
        .field((r) => r[15])
        .field((r) => r[16])
        .field((r) => r[17])
        .field((r) => r[18])
        .field((r) => r[19])
        .build(
          (a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t) => [
            a,
            b,
            c,
            d,
            e,
            f,
            g,
            h,
            i,
            j,
            k,
            l,
            m,
            n,
            o,
            p,
            q,
            r,
            s,
            t,
          ],
        );
    final values = List.generate(20, (i) => i);
    final small = LinkTree<Object?>([
      built,
      Link<List<String>>('x').rest((r) => r).build((r) => r),
      Link<List<String>>('').rest((r) => r).build((r) => r),
    ]);
    expect(small.routeOf(small.uriOf(values)), values);
  });

  test('two links that match one URL at one rank fail at startup', () {
    expect(
      () => LinkTree<AppRoute>([NotFoundRoute.link, XRoute.link, YRoute.link]),
      throwsA(isStateError.having((e) => e.message, 'message',
          allOf(contains('/x/*'), contains('/*/y')))),
    );
    // Same rank, but no URL matches both.
    LinkTree<AppRoute>([NotFoundRoute.link, XRoute.link, ZRoute.link]);
  });

  test('the tree lists its templates in matching order', () {
    expect(tree.templates, ['/items/new/view', '/items/*/view', '/', '/**']);
  });
}
