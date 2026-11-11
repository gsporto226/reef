import 'package:flutter/foundation.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';

/// Where a deep link points (spec §9): path segments plus query arguments.
@immutable
class BufferPath {
  const BufferPath(this.segments, [this.arguments = const {}]);

  /// Reads [uri]'s path segments (empty ones dropped) and query.
  factory BufferPath.fromUri(Uri uri) => BufferPath(
    [...uri.pathSegments.where((s) => s.isNotEmpty)],
    uri.queryParameters,
  );

  final List<String> segments;
  final Map<String, String> arguments;

  Uri toUri() => Uri(
    path: '/${segments.map(Uri.encodeComponent).join('/')}',
    queryParameters: arguments.isEmpty ? null : arguments,
  );

  @override
  String toString() => toUri().toString();

  @override
  bool operator ==(Object other) =>
      other is BufferPath &&
      listEquals(other.segments, segments) &&
      mapEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(segments),
    Object.hashAllUnordered(arguments.entries.map((e) => (e.key, e.value))),
  );
}

/// A resolved link: the buffer and the arguments the path carried.
typedef BufferLink = ({BufferId buffer, Map<String, String> arguments});

/// Maps each buffer kind to one path template, both ways (spec §9). A
/// template like `/tasks/:taskId/edit` maps to buffer `task-edit:42`; the
/// parameters, joined by `/`, form the token. A template without
/// parameters resolves to a fresh draft buffer each time.
class LinkTable {
  const LinkTable(this.templates);

  /// Path template per buffer kind.
  final Map<String, String> templates;

  /// The buffer [path] points at, or null when no template matches.
  BufferLink? resolve(BufferPath path) {
    for (final MapEntry(key: kind, value: template) in templates.entries) {
      final pattern = _segments(template);
      if (pattern.length != path.segments.length) continue;
      final params = <String>[];
      var matches = true;
      for (var i = 0; i < pattern.length && matches; i++) {
        if (pattern[i].startsWith(':')) {
          params.add(path.segments[i]);
        } else {
          matches = pattern[i] == path.segments[i];
        }
      }
      if (!matches) continue;
      final token = params.isEmpty ? BufferId.generate().id : params.join('/');
      return (buffer: BufferId.manual('$kind:$token'), arguments: path.arguments);
    }
    return null;
  }

  /// [buffer]'s path with [arguments] as its query, or null when its kind
  /// has no template or its token does not fit the template.
  BufferPath? pathOf(BufferId buffer, [Map<String, String> arguments = const {}]) {
    final colon = buffer.id.indexOf(':');
    if (colon < 0) return null;
    final template = templates[buffer.id.substring(0, colon)];
    if (template == null) return null;
    final pattern = _segments(template);
    final params = pattern.where((s) => s.startsWith(':')).length;
    final values = buffer.id.substring(colon + 1).split('/');
    if (params > 0 && values.length != params) return null;
    var next = 0;
    return BufferPath([
      for (final s in pattern) s.startsWith(':') ? values[next++] : s,
    ], arguments);
  }

  static List<String> _segments(String template) =>
      [...template.split('/').where((s) => s.isNotEmpty)];
}
