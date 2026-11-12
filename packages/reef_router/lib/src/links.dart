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

/// A buffer and the arguments of its history entry.
typedef ResolvedLink = ({BufferId buffer, Map<String, String> arguments});

/// A built link: the URL of route type [R], both ways (ADR 0004).
final class TypedLink<R> {
  TypedLink._(this._parts, this._create) {
    final path = _parts.where((p) => p is! _Query).toList();
    if (path.indexWhere((p) => p is _Rest) case final i
        when i >= 0 && i != path.length - 1) {
      throw ArgumentError('A rest part must end the path of $R');
    }
  }

  final List<_Part> _parts;
  final R Function(List<Object?> values) _create;

  bool _owns(Object? route) => route is R;

  Iterable<_Part> get _path => _parts.where((p) => p is! _Query);

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

  R? _match(List<String> segments, Map<String, String> query) {
    final values = <Object?>[];
    var i = 0;
    try {
      for (final part in _parts) {
        switch (part) {
          case _Literal(:final text):
            if (i >= segments.length || segments[i++] != text) return null;
          case _Segment(:final parse):
            if (i >= segments.length) return null;
            values.add(parse(segments[i++]));
          case _Rest():
            values.add(segments.sublist(i));
            i = segments.length;
          case _Query(:final name, :final parse):
            values.add(parse(query[name]));
        }
      }
    } on Object {
      return null; // A malformed value matches nothing.
    }
    return i == segments.length ? _create(values) : null;
  }

  /// [route]'s path values in order, a rest's spread; with [literals],
  /// its whole path.
  List<String> _values(Object? route, {bool literals = false}) => [
    for (final part in _path)
      ...switch (part) {
        _Literal(:final text) => [if (literals) text],
        _Segment(:final format) => [format(route)],
        _Rest(:final read) => read(route),
        _Query() => const <String>[],
      },
  ];

  Map<String, String> _arguments(Object? route) => {
    for (final part in _parts.whereType<_Query>())
      part.name: ?part.format(route),
  };
}

/// Every link of an app, matched by specificity (ADR 0004 D4, D6). It
/// needs a root catch-all (`Link('').rest(...)`), the not-found route.
final class LinkTree<R> {
  LinkTree(List<TypedLink<R>> links)
    : _links = [...links]..sort((a, b) => _compare(b._rank, a._rank)) {
    if (!_links.any((l) => l._isCatchAll)) {
      throw StateError('A link tree needs a root catch-all link (/**)');
    }
  }

  final List<TypedLink<R>> _links;

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
        return route;
      }
    }
    throw StateError('No link matches $uri');
  }

  TypedLink<R> _linkOf(R route) => _links.firstWhere(
    (l) => l._owns(route),
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
    for (final s in kind.split('/').where((s) => s.isNotEmpty)) {
      if (s == '**') {
        segments.addAll(values.skip(next));
        next = values.length;
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
