import 'package:reef/reef.dart';

part 'link_stages.g.dart';

/// The text form of a link value of type [V].
abstract base class LinkCodec<V> {
  const LinkCodec();

  /// A codec from two functions.
  factory LinkCodec.of(
    String Function(V value) encode,
    V Function(String text) decode,
  ) = _FunctionCodec<V>;

  /// An enum by its name.
  static LinkCodec<V> enumeration<V extends Enum>(List<V> values) =>
      _FunctionCodec((v) => v.name, values.byName);

  String encode(V value);

  /// Throws on malformed [text], which then matches nothing.
  V decode(String text);
}

final class _FunctionCodec<V> extends LinkCodec<V> {
  _FunctionCodec(this._encode, this._decode);

  final String Function(V value) _encode;
  final V Function(String text) _decode;

  @override
  String encode(V value) => _encode(value);

  @override
  V decode(String text) => _decode(text);
}

/// The codec for `String`, `int` or `bool`, nullable or not.
LinkCodec<V> _inferred<V>() {
  bool isA<T>() => <T>[] is List<V> && <V>[] is List<T?>;
  final Object Function(String)? parse = isA<String>()
      ? (s) => s
      : isA<int>()
      ? int.parse
      : isA<bool>()
      ? bool.parse
      : null;
  if (parse == null) {
    throw ArgumentError('No codec inferred for $V; pass codec:');
  }
  return _FunctionCodec<V>((v) => '$v', (s) => parse(s) as V);
}

sealed class _Part {
  const _Part();
}

final class _Literal extends _Part {
  const _Literal(this.text);
  final String text;
}

final class _Segment extends _Part {
  const _Segment(this.format, this.parse);
  final String Function(Object? route) format;
  final Object? Function(String text) parse;
}

final class _Rest extends _Part {
  const _Rest(this.read);
  final List<String> Function(Object? route) read;
}

final class _Query extends _Part {
  const _Query(this.name, this.format, this.parse);
  final String name;

  /// Null for the fallback value.
  final String? Function(Object? route) format;

  /// Null text reads as the fallback value.
  final Object? Function(String? text) parse;
}

/// The parent value; the tree replaces it with the parent's parts.
final class _Parent extends _Part {
  const _Parent(this.read, this.fits);
  final Object? Function(Object? route) read;
  final bool Function(TypedLink<Object?> parent) fits;
}

/// [part] reading its value from the parent value [get] gives.
_Part _through(_Part part, Object? Function(Object? route) get) =>
    switch (part) {
      _Literal() || _Parent() => part,
      _Segment(:final format, :final parse) => _Segment(
        (r) => format(get(r)),
        parse,
      ),
      _Rest(:final read) => _Rest((r) => read(get(r))),
      _Query(:final name, :final format, :final parse) => _Query(
        name,
        (r) => format(get(r)),
        parse,
      ),
    };

List<_Part> _literals(String path) => [
  for (final s in path.split('/'))
    if (s.isNotEmpty) _Literal(s),
];

_Segment _field<R, V>(V Function(R route) get, LinkCodec<V>? codec) {
  final c = codec ?? _inferred<V>();
  return _Segment((r) => c.encode(get(r as R)), c.decode);
}

_Query _query<R, V>(
  String name,
  V Function(R route) get,
  V fallback,
  LinkCodec<V>? codec,
) {
  final c = codec ?? _inferred<V>();
  return _Query(name, (r) {
    final v = get(r as R);
    return v == fallback ? null : c.encode(v);
  }, (s) => s == null ? fallback : c.decode(s));
}

_Rest _rest<R>(List<String> Function(R route) get) => _Rest((r) => get(r as R));

_Parent _parent<R, P>(P Function(R route) get) =>
    _Parent((r) => get(r as R), (l) => l is TypedLink<P>);

/// A buffer and the arguments of its history entry.
typedef ResolvedLink = ({BufferId buffer, Map<String, String> arguments});

/// A link and the links mounted under it (ADR 0004 D12, D13, D14).
sealed class LinkNode<R> {
  const LinkNode();

  TypedLink<R> get _link;
  List<LinkNode<Object?>> get _children;
}

final class _Branch<R> extends LinkNode<R> {
  const _Branch(this._link, this._children);

  @override
  final TypedLink<R> _link;

  @override
  final List<LinkNode<Object?>> _children;
}

/// A built link: the URL of route type [R], both ways (ADR 0004).
final class TypedLink<R> extends LinkNode<R> {
  TypedLink._(this._parts, this._create) {
    final path = _parts.where((p) => p is! _Query && p is! _Parent).toList();
    if (path.indexWhere((p) => p is _Rest) case final i
        when i >= 0 && i != path.length - 1) {
      throw ArgumentError('A rest part must end the path of $R');
    }
  }

  final List<_Part> _parts;
  final R Function(List<Object?> values) _create;

  @override
  TypedLink<R> get _link => this;

  @override
  List<LinkNode<Object?>> get _children => const [];

  Type get _route => R;

  bool _owns(Object? route) => route is R;

  /// This link with [children] mounted under it; each extends its path
  /// and query.
  LinkNode<R> children(List<LinkNode<Object?>> children) =>
      _Branch(this, children);
}

/// A link at its place in the tree: its parents' parts, then its own.
final class _Mount {
  _Mount(this.link, this.parts, this.create);

  final TypedLink<Object?> link;
  final List<_Part> parts;
  final Object? Function(List<Object?> values) create;

  int get _valueCount => parts.where((p) => p is! _Literal).length;

  Iterable<_Part> get _path => parts.where((p) => p is! _Query);

  /// The buffer kind: the template, `*` per value and `**` for a rest.
  String get _kind =>
      '/${_path.map((p) => switch (p) {
        _Literal(:final text) => text,
        _Segment() => '*',
        _ => '**',
      }).join('/')}';

  bool get _isCatchAll => _path.length == 1 && _path.single is _Rest;

  /// Rest links rank last, then more literals, then longer paths win.
  (int, int, int) get _rank => (
    _path.any((p) => p is _Rest) ? 0 : 1,
    _path.whereType<_Literal>().length,
    _path.length,
  );

  Object? _match(List<String> segments, Map<String, String> query) {
    final values = <Object?>[];
    var i = 0;
    try {
      for (final part in parts) {
        switch (part) {
          case _Literal(:final text):
            if (i >= segments.length || segments[i++] != text) return null;
          case _Segment(:final parse):
            if (i >= segments.length) return null;
            values.add(parse(segments[i++]));
          case _Rest():
            // The parts after a rest match from the end (D13).
            final path = _path.toList();
            final end = segments.length - path.length + path.indexOf(part) + 1;
            if (end < i) return null;
            values.add(segments.sublist(i, end));
            i = end;
          case _Query(:final name, :final parse):
            values.add(parse(query[name]));
          case _Parent():
            throw StateError('A mount has no parent part');
        }
      }
    } on Object {
      return null; // A malformed value matches nothing.
    }
    return i == segments.length ? create(values) : null;
  }

  /// [route]'s path values in order, a rest's spread; with [literals],
  /// its whole path.
  List<String> _values(Object? route, {bool literals = false}) => [
    for (final part in _path)
      ...switch (part) {
        _Literal(:final text) => [if (literals) text],
        _Segment(:final format) => [format(route)],
        _Rest(:final read) => read(route),
        _Query() || _Parent() => const <String>[],
      },
  ];

  Map<String, String> _arguments(Object? route) => {
    for (final part in parts.whereType<_Query>())
      part.name: ?part.format(route),
  };
}

/// Every link of an app, matched by specificity (ADR 0004 D4, D6). It
/// needs a root catch-all (`Link('').rest(...)`), the not-found route.
/// Children extend their parent's path and query (D12, D13, D14).
final class LinkTree<R> {
  LinkTree(List<LinkNode<R>> roots) {
    final mounted = <TypedLink<Object?>>{};
    void mount(LinkNode<Object?> node, _Mount? parent) {
      final link = node._link;
      final name = link._route;
      if (!mounted.add(link)) {
        throw StateError('The link to $name is mounted twice; use two types');
      }
      if (link is! TypedLink<R>) {
        throw StateError('The link to $name does not build a $R');
      }
      final own = link._parts.where((p) => p is! _Parent).toList();
      final inherited = parent?.parts ?? const <_Part>[];
      for (final q in own.whereType<_Query>()) {
        if (inherited.any((p) => p is _Query && p.name == q.name)) {
          throw StateError(
            'The link to $name redeclares the query "${q.name}"; '
            'read it from the parent',
          );
        }
      }
      final _Mount at;
      if (link._parts.whereType<_Parent>().firstOrNull case final p?) {
        if (parent == null || !p.fits(parent.link)) {
          throw StateError('The link to $name needs a parent of its type');
        }
        final n = parent._valueCount;
        at = _Mount(link, [
          for (final q in inherited) _through(q, p.read),
          ...own,
        ], (v) => link._create([parent.create(v.sublist(0, n)), ...v.skip(n)]));
      } else {
        if (parent != null && parent._valueCount > 0) {
          throw StateError(
            'The link to $name needs .parent: its parent has values',
          );
        }
        at = _Mount(link, [...inherited, ...own], link._create);
      }
      if (at.parts.whereType<_Rest>().length > 1) {
        throw StateError('The link to $name has two rest parts');
      }
      _links.add(at);
      for (final child in node._children) {
        mount(child, at);
      }
    }

    for (final root in roots) {
      mount(root, null);
    }
    _links.sort((a, b) => _compare(b._rank, a._rank));
    if (!_links.any((l) => l._isCatchAll)) {
      throw StateError('A link tree needs a root catch-all link (/**)');
    }
  }

  final List<_Mount> _links = [];

  static int _compare((int, int, int) a, (int, int, int) b) => a.$1 != b.$1
      ? a.$1 - b.$1
      : a.$2 != b.$2
      ? a.$2 - b.$2
      : a.$3 - b.$3;

  /// The route [uri] stands for; the catch-all's when nothing else matches.
  R routeOf(Uri uri) {
    final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];
    for (final link in _links) {
      if (link._match(segments, uri.queryParameters) case final route?) {
        return route as R;
      }
    }
    throw StateError('No link matches $uri');
  }

  _Mount _linkOf(R route) => _links.firstWhere(
    (l) => l.link._owns(route),
    orElse: () => throw ArgumentError('No link for $route'),
  );

  Uri uriOf(R route) {
    final link = _linkOf(route);
    return _uri(link._values(route, literals: true), link._arguments(route));
  }

  /// [route]'s buffer and the query arguments for its history entry.
  ResolvedLink linkOf(R route) {
    final link = _linkOf(route);
    return (
      buffer: BufferId.of(
        link._kind,
        link._values(route).map(_escape).join('/'),
      ),
      arguments: link._arguments(route),
    );
  }

  /// The buffer and arguments [uri] stands for.
  ResolvedLink resolve(Uri uri) => linkOf(routeOf(uri));

  /// The route [buffer] shows with [arguments]. A kind no link mounts
  /// gives the not-found route.
  R routeOfBuffer(BufferId buffer, [Map<String, String> arguments = const {}]) {
    final kind = buffer.kind ?? buffer.id;
    final token = buffer.token ?? '';
    final values = [
      if (token.isNotEmpty) ...token.split('/').map(Uri.decodeComponent),
    ];
    var next = 0;
    final segments = <String>[];
    final parts = kind.split('/').where((s) => s.isNotEmpty).toList();
    for (final (i, s) in parts.indexed) {
      if (s == '**') {
        // Values after a rest are read from the end (D13).
        final after = parts.skip(i + 1).where((s) => s == '*').length;
        final end = values.length - after;
        if (end > next) {
          segments.addAll(values.sublist(next, end));
          next = end;
        }
      } else if (s == '*') {
        if (next < values.length) segments.add(values[next++]);
      } else {
        segments.add(s);
      }
    }
    return routeOf(_uri(segments, arguments));
  }

  /// [buffer]'s URL, or null when no link mounts its kind.
  Uri? uriOfBuffer(
    BufferId buffer, [
    Map<String, String> arguments = const {},
  ]) => _links.any((l) => l._kind == buffer.kind)
      ? uriOf(routeOfBuffer(buffer, arguments))
      : null;

  static Uri _uri(List<String> segments, Map<String, String> arguments) => Uri(
    path: '/${segments.map(Uri.encodeComponent).join('/')}',
    queryParameters: arguments.isEmpty ? null : arguments,
  );

  /// Escapes only what would make the token ambiguous.
  static String _escape(String value) =>
      value.replaceAll('%', '%25').replaceAll('/', '%2F');
}
