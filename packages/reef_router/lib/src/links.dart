import 'package:flutter/foundation.dart';
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
  const _Parent(this.read);
  final Object? Function(Object? route) read;
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

_Parent _parent<R, P>(P Function(R route) get) => _Parent((r) => get(r as R));

/// A buffer and the arguments of its history entry.
typedef ResolvedLink = ({BufferId buffer, Map<String, String> arguments});

/// A node of the link tree to route type [R], mounted under a link to
/// exactly [P]; [P] is `Never` for a node with no parent (a root, or a
/// child of a [ValuelessLink]). Wrong nesting is a compile error (#69).
typedef LinkNode<R, P> = LinkNodeOf<R, P Function(P)>;

/// A built link to [R] with values, mounted under a link to exactly [P].
typedef TypedLink<R, P> = TypedLinkOf<R, P Function(P)>;

/// [LinkNode] with its parent type as [Q] = `P Function(P)`: a function
/// type is invariant in `P`, so a child expecting a subtype or a supertype
/// of its parent's route does not fit. Write [LinkNode] instead.
sealed class LinkNodeOf<R, Q> {
  const LinkNodeOf();

  LinkOf<R, Q> get _link;
  List<LinkNodeOf<Object?, Object?>> get _children;
  List<TreeGuard<Object?>> get _guards => const [];
  bool? get _fresh => null;

  /// This node's own freshness, over the tree's (ADR 0004 D3): a fresh
  /// link opens a new buffer each time, as a browser tab does.
  LinkNodeOf<R, Q> fresh([bool fresh = true]) => _Fresh(this, fresh);

  /// This node with [guard] run for its route and every route below it,
  /// after the guards already on it (ADR 0004 D9-D11). [name] is for
  /// errors; it defaults to the guard's types.
  LinkNodeOf<R, Q> guard<D, E>(
    GuardDecision Function(R route, D destination, E environment) guard, {
    String? name,
  }) => _Guarded(this, TreeGuard.of<R, D, E>(guard, name: name));
}

final class _Guarded<R, Q> extends LinkNodeOf<R, Q> {
  _Guarded(this._node, TreeGuard<Object?> guard)
    : _guards = [..._node._guards, guard];

  final LinkNodeOf<R, Q> _node;

  @override
  final List<TreeGuard<Object?>> _guards;

  @override
  LinkOf<R, Q> get _link => _node._link;

  @override
  List<LinkNodeOf<Object?, Object?>> get _children => _node._children;

  @override
  bool? get _fresh => _node._fresh;
}

final class _Fresh<R, Q> extends LinkNodeOf<R, Q> {
  const _Fresh(this._node, this._fresh);

  final LinkNodeOf<R, Q> _node;

  @override
  final bool _fresh;

  @override
  LinkOf<R, Q> get _link => _node._link;

  @override
  List<LinkNodeOf<Object?, Object?>> get _children => _node._children;

  @override
  List<TreeGuard<Object?>> get _guards => _node._guards;
}

/// What a guard decides about opening a route: allow or redirect, never
/// block (ADR 0006).
sealed class GuardDecision {
  const GuardDecision();

  const factory GuardDecision.allow() = GuardAllow;

  /// Opens [route] in place of the guarded one; its own guards run too.
  const factory GuardDecision.redirect(Object route) = GuardRedirect;
}

final class GuardAllow extends GuardDecision {
  const GuardAllow();
}

final class GuardRedirect extends GuardDecision {
  const GuardRedirect(this.route);
  final Object route;

  @override
  bool operator ==(Object other) =>
      other is GuardRedirect && other.route == route;

  @override
  int get hashCode => route.hashCode;
}

/// A guard as a class: it reads the route [R] at its node, the
/// [D]estination being opened and the app's [E]nvironment interface.
/// Pass an instance to `.guard`; a guard for a base route fits any node.
abstract base class LinkGuard<R, D, E> {
  const LinkGuard();

  GuardDecision call(R route, D destination, E environment);
}

/// A guard with its types kept for the bind check (D10).
final class TreeGuard<R> {
  TreeGuard._(
    this.name,
    this._run,
    this._takesEnvironment,
    this._takesDestinations,
    this._environment,
    this._destination,
  );

  /// [guard] for a tree's `guards:`, run before every node's guards.
  static TreeGuard<R> of<R, D, E>(
    GuardDecision Function(R route, D destination, E environment) guard, {
    String? name,
  }) => TreeGuard._(
    name ?? 'guard<$R, $D, $E>',
    (r, d, e) => guard(r as R, d as D, e as E),
    (e) => e is E,
    (routes) => routes is List<D>,
    E,
    D,
  );

  final String name;
  final GuardDecision Function(Object? route, Object? dest, Object? env) _run;
  final bool Function(Object? environment) _takesEnvironment;
  final bool Function(List<Object?> routes) _takesDestinations;
  final Type _environment;
  final Type _destination;
}

final class _Branch<R, Q> extends LinkNodeOf<R, Q> {
  const _Branch(this._link, this._children);

  @override
  final LinkOf<R, Q> _link;

  @override
  final List<LinkNodeOf<Object?, Object?>> _children;
}

/// A built link: the URL of route type [R], both ways (ADR 0004).
sealed class LinkOf<R, Q> extends LinkNodeOf<R, Q> {
  LinkOf._(this._parts, this._create) {
    final path = _parts.where((p) => p is! _Query && p is! _Parent).toList();
    if (path.indexWhere((p) => p is _Rest) case final i
        when i >= 0 && i != path.length - 1) {
      throw ArgumentError('A rest part must end the path of $R');
    }
  }

  final List<_Part> _parts;
  final R Function(List<Object?> values) _create;

  @override
  LinkOf<R, Q> get _link => this;

  @override
  List<LinkNodeOf<Object?, Object?>> get _children => const [];

  Type get _route => R;

  bool _owns(Object? route) => route is R;
}

/// See [TypedLink].
final class TypedLinkOf<R, Q> extends LinkOf<R, Q> {
  TypedLinkOf._(super._parts, super._create) : super._();

  /// This link with [children] mounted under it; each reads its parent
  /// value with `.parent` and extends its path and query.
  LinkNodeOf<R, Q> children(List<LinkNode<Object?, R>> children) =>
      _Branch(this, children);
}

/// A built link to [R] with no values and no parent: its one route needs
/// no `.parent` in its children.
final class ValuelessLink<R> extends LinkOf<R, Never Function(Never)> {
  ValuelessLink._(super._parts, super._create) : super._();

  /// This link with [children] mounted under it; each extends its path
  /// and query.
  LinkNode<R, Never> children(List<LinkNode<Object?, Never>> children) =>
      _Branch(this, children);
}

/// A link at its place in the tree: its parents' parts, then its own.
final class _Mount {
  _Mount(
    this.link,
    this.parts,
    this.create,
    this.guards,
    this.fresh, [
    this.parent,
    this.up,
  ]);

  final List<TreeGuard<Object?>> guards;
  final bool? fresh;
  final _Mount? parent;

  /// The parent route of a route of this mount; null at the root.
  final Object? Function(Object? route)? up;

  final LinkOf<Object?, Object?> link;
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
/// Children extend their parent's path and query (D12, D13, D14). Where a
/// link may be mounted is checked by its type; the rest at startup.
final class LinkTree<R> {
  /// [guards] run for every route, before the nodes' guards; a redirect
  /// chain longer than [redirectLimit] is a loop. [fresh] is the default
  /// freshness of its links (D3).
  LinkTree(
    List<LinkNode<R, Never>> roots, {
    this._guards = const [],
    this.fresh = false,
    this.redirectLimit = 5,
  }) {
    final mounted = <LinkOf<Object?, Object?>>{};
    void mount(LinkNodeOf<Object?, Object?> node, _Mount? parent) {
      final link = node._link;
      final name = link._route;
      if (!mounted.add(link)) {
        throw StateError('The link to $name is mounted twice; use two types');
      }
      if (link is! LinkOf<R, Object?>) {
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
        // The types put a link with .parent under a parent with values.
        final n = parent!._valueCount;
        at = _Mount(
          link,
          [for (final q in inherited) _through(q, p.read), ...own],
          (v) => link._create([parent.create(v.sublist(0, n)), ...v.skip(n)]),
          node._guards,
          node._fresh,
          parent,
          p.read,
        );
      } else {
        at = _Mount(
          link,
          [...inherited, ...own],
          link._create,
          node._guards,
          node._fresh,
          parent,
          switch (parent) {
            // A parent with no values has one route.
            final p? => (_) => p.create(const []),
            null => null,
          },
        );
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
  final List<TreeGuard<R>> _guards;
  final int redirectLimit;
  final bool fresh;

  /// This tree with its guards given [environment]. Fails when a guard
  /// needs another environment type, or a destination type narrower than
  /// [R] (D10).
  BoundLinkTree<R> bind(Object? environment) {
    for (final g in [..._guards, for (final l in _links) ...l.guards]) {
      if (!g._takesDestinations(<R>[])) {
        throw StateError(
          '${g.name} takes a ${g._destination} destination; '
          'the tree opens any $R',
        );
      }
      if (!g._takesEnvironment(environment)) {
        throw StateError(
          '${g.name} needs a ${g._environment} environment; '
          'got ${environment.runtimeType}',
        );
      }
    }
    return BoundLinkTree._(this, environment);
  }

  /// The first non-allow decision for opening [route], and its guard's
  /// name: tree-wide guards, then each ancestor's from the root with its
  /// own value, then the route's own (spec story 50).
  (GuardDecision, String) _decide(R route, Object? environment) {
    final levels = <(_Mount, Object?)>[];
    Object? value = route;
    for (_Mount? m = _linkOf(route); m != null; m = m.parent) {
      levels.add((m, value));
      if (m.parent != null) value = m.up!(value);
    }
    final chain = [
      for (final g in _guards) (g, route as Object?),
      for (final (m, v) in levels.reversed)
        for (final g in m.guards) (g, v),
    ];
    for (final (g, v) in chain) {
      final decision = g._run(v, route, environment);
      if (decision is! GuardAllow) return (decision, g.name);
    }
    return (const GuardDecision.allow(), '');
  }

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

  /// The route [route] is mounted under, holding the parent's query; null
  /// for a root link (spec stories 25, 32).
  R? parentOf(R route) => _linkOf(route).up?.call(route) as R?;

  /// [route]'s buffer and the query arguments for its history entry.
  /// [fresh] overrides the link's freshness; a fresh buffer's token ends
  /// in a new `~<uuid>`, which no URL carries (D3).
  ResolvedLink linkOf(R route, {bool? fresh}) {
    final link = _linkOf(route);
    final token = link._values(route).map(_escape).join('/');
    return (
      buffer: BufferId.of(
        link._kind,
        (fresh ?? link.fresh ?? this.fresh)
            ? '$token~${BufferId.generate().id}'
            : token,
      ),
      arguments: link._arguments(route),
    );
  }

  /// Whether [buffer] is a fresh link's: never already open.
  bool isFresh(BufferId buffer) =>
      (buffer.token?.contains('~') ?? false) &&
      _links.any((l) => l._kind == buffer.kind);

  /// The buffer and arguments [uri] stands for.
  ResolvedLink resolve(Uri uri) => linkOf(routeOf(uri));

  /// The route [buffer] shows with [arguments]. A kind no link mounts
  /// gives the not-found route.
  R routeOfBuffer(BufferId buffer, [Map<String, String> arguments = const {}]) {
    final kind = buffer.kind ?? buffer.id;
    final token = (buffer.token ?? '').split('~').first;
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
      value.replaceAll('%', '%25').replaceAll('/', '%2F').replaceAll('~', '%7E');
}

/// A [LinkTree] whose guards are bound to an environment: checks routes,
/// and enforces the guards through windowing's [interceptor] (D9).
final class BoundLinkTree<R> {
  BoundLinkTree._(this.tree, this.environment);

  final LinkTree<R> tree;
  final Object? environment;

  /// Allow, or a redirect to the final allowed target. Throws
  /// past [LinkTree.redirectLimit] redirects.
  GuardDecision check(R route) {
    var target = route;
    for (var hops = 0; ; hops++) {
      final (decision, name) = tree._decide(target, environment);
      switch (decision) {
        case GuardAllow():
          return hops == 0 ? decision : GuardDecision.redirect(target as Object);
        case GuardRedirect(:final route):
          if (route is! R) {
            throw StateError('$name redirected to $route, not a $R');
          }
          if (hops == tree.redirectLimit) {
            throw StateError(
              'Redirect loop: past ${tree.redirectLimit} redirects, '
              '$name sent $target to $route',
            );
          }
          target = route as R;
      }
    }
  }

  /// Re-checks the current entry of every window when [refresh] fires and
  /// whenever [controller]'s doc changes, which covers undo and redo (they
  /// skip the interceptor), and once now, which covers restore (D8). A
  /// redirect replaces the entry.
  /// Returns the call that stops watching.
  void Function() watch(WindowingController controller, {Listenable? refresh}) {
    void recheck() {
      final commands = <WindowingCommand>[];
      for (final MapEntry(key: id, value: window)
          in controller.doc.value.windows.entries) {
        final HistoryEntry(:buffer, :arguments) = window.history.current;
        if (tree.uriOfBuffer(buffer) == null) continue;
        if (check(tree.routeOfBuffer(buffer, arguments))
            case GuardRedirect(:final route)) {
          final target = tree.linkOf(route as R);
          commands.add(
            ReplaceBuffer(id, target.buffer, arguments: target.arguments),
          );
        }
      }
      if (commands.isNotEmpty) controller.dispatchAll(commands);
    }

    controller.doc.addListener(recheck);
    refresh?.addListener(recheck);
    recheck();
    return () {
      controller.doc.removeListener(recheck);
      refresh?.removeListener(recheck);
    };
  }

  /// Checks every command that shows a link buffer, back and forward
  /// included. A redirect aims the same command at the target, so it
  /// replaces the guarded entry (D7).
  CommandDecision interceptor(WindowingDoc doc, WindowingCommand command) {
    HistoryEntry? last(List<HistoryEntry>? entries) => entries?.lastOrNull;
    final shown = switch (command) {
      NewTab(buffer: (_, final b)?, :final arguments) ||
      SplitWindow(buffer: final b?, :final arguments) ||
      AttachBuffer(buffer: final b, :final arguments) ||
      PushBuffer(buffer: final b, :final arguments) ||
      ReplaceBuffer(buffer: final b, :final arguments) => HistoryEntry(
        b,
        arguments: arguments,
      ),
      PopBuffer(:final windowId) => last(doc.windows[windowId]?.history.back),
      NavigateForward(:final windowId) => last(
        doc.windows[windowId]?.history.forward,
      ),
      _ => null,
    };
    if (shown == null || tree.uriOfBuffer(shown.buffer) == null) {
      return const CommandDecision.approve();
    }
    switch (check(tree.routeOfBuffer(shown.buffer, shown.arguments))) {
      case GuardAllow():
        return const CommandDecision.approve();
      case GuardRedirect(:final route):
        final (:buffer, :arguments) = tree.linkOf(route as R);
        return CommandDecision.replace(switch (command) {
          NewTab c => NewTab(
            shellId: c.shellId,
            tabId: c.tabId,
            buffer: (c.buffer!.$1, buffer),
            arguments: arguments,
            entryId: c.entryId,
          ),
          SplitWindow c => SplitWindow(
            c.windowId,
            newWindowId: c.newWindowId,
            axis: c.axis,
            buffer: buffer,
            arguments: arguments,
            entryId: c.entryId,
          ),
          AttachBuffer c => AttachBuffer(
            c.windowId,
            buffer,
            arguments: arguments,
            entryId: c.entryId,
          ),
          PushBuffer c => PushBuffer(
            c.windowId,
            buffer,
            arguments: arguments,
            entryId: c.entryId,
          ),
          ReplaceBuffer c => ReplaceBuffer(
            c.windowId,
            buffer,
            arguments: arguments,
            entryId: c.entryId,
          ),
          PopBuffer(:final windowId) ||
          NavigateForward(:final windowId) => CommandSequence([
            command,
            ReplaceBuffer(windowId, buffer, arguments: arguments),
          ]),
          _ => throw StateError('Unreachable: $command'),
        });
    }
  }
}
