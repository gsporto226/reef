import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';

/// A routable buffer id is `kind:token` (blueprint §10.3) — e.g.
/// `task-edit:42`. Unroutable ids (plain uuids) never appear in URLs.
extension RoutableBufferId on BufferId {
  /// The routing kind — the segment before the first colon — or null when
  /// the id is unroutable.
  String? get kind {
    final index = id.indexOf(':');
    return index < 0 ? null : id.substring(0, index);
  }
}

/// Builds a buffer's page widget from its kind.
typedef BufferPageBuilder = Widget Function(
  BuildContext context,
  BufferId bufferId,
);

/// Maps buffer kinds to page builders — the app-side half of the navigation
/// adapter. [WorkspaceShell] derives its `SplitWorkspace.buildWindow` from
/// the registry; reef core stays router-agnostic.
class WorkspaceRegistry {
  /// Creates a registry; [notFoundBuilder] renders unknown kinds and
  /// unroutable ids (default: an empty box).
  WorkspaceRegistry({
    required Map<String, BufferPageBuilder> kinds,
    this.notFoundBuilder,
  }) : _kinds = Map.of(kinds);

  final Map<String, BufferPageBuilder> _kinds;

  final WidgetBuilder? notFoundBuilder;

  /// Builds the page for [bufferId] through its kind.
  Widget buildWindow(BuildContext context, BufferId bufferId) {
    final builder = bufferId.kind == null ? null : _kinds[bufferId.kind];
    if (builder == null) {
      return notFoundBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return builder(context, bufferId);
  }
}
