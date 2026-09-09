import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/page_identity/_implementations/reef_scope.dart';

/// The buffer's [ReefScope], keyed by [BufferId].
///
/// Hand-written (reef core stays codegen-free). Auto-dispose: the scope lives
/// while at least one window on the buffer watches it — shared across windows,
/// disposed with the buffer (§4.4).
final reefScopeProvider =
    Provider.autoDispose.family<ReefScope, BufferId>((ref, bufferId) {
  final scope = ReefScope();
  ref.onDispose(scope.dispose);
  return scope;
});
