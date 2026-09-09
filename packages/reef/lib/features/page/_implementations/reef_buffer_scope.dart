import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:flutter/widgets.dart';

/// Exposes the enclosing window's [BufferId] to descendants via
/// `ReefBufferScope.of(context)` (§4.4) — layouts, dialogs and child scopes
/// reach the id without threading it through constructors.
class ReefBufferScope extends InheritedWidget {
  /// Wraps [child] with [bufferId] in scope.
  const ReefBufferScope({
    super.key,
    required this.bufferId,
    required super.child,
  });

  /// The buffer id of the enclosing [ReefWindow].
  final BufferId bufferId;

  /// Returns the buffer id of the nearest enclosing [ReefWindow].
  static BufferId of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReefBufferScope>()!.bufferId;

  @override
  bool updateShouldNotify(ReefBufferScope oldWidget) =>
      oldWidget.bufferId != bufferId;
}
