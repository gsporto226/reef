import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page/_implementations/reef_buffer_scope.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/page_identity/_providers/reef_scope_provider.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;

/// Resolves the provider exposing a buffer's viewmodel. Usually a
/// family-keyed provider invocation (`taskEditViewModelProvider(bufferId: id)`);
/// pass a lambda ignoring the id for non-keyed providers.
typedef BufferViewModelProvider<V extends ViewModel<Object?>>
    = ProviderListenable<V> Function(BufferId bufferId);

/// A window onto a buffer (§10 of `docs/blueprint.md`): a viewport bound to
/// one [BufferId], rendering that buffer's viewmodel through its
/// out-bindings.
///
/// - `bufferId: null` (default) materializes a **fresh buffer**.
/// - `bufferId: someId` **opens that buffer** — several windows may show the
///   same buffer id; they share the viewmodel and live-sync through its
///   `ValueListenables`.
///
/// The window also watches the buffer's `reefScopeProvider`, so buffer-scoped
/// resources die with the buffer (last window gone), not with any single
/// window. Identity, scope and provider watch are owned here — the page layer
/// stays layout-and-wiring only (§4.4).
class ReefWindow<V extends ViewModel<Object?>> extends ConsumerStatefulWidget {
  /// Creates a window bound to [bufferId] (or a fresh buffer when null).
  const ReefWindow({
    super.key,
    this.bufferId,
    required this.viewModel,
    required this.builder,
  });

  /// The buffer to open; null materializes a new buffer.
  final BufferId? bufferId;

  /// Resolves the buffer's viewmodel provider from the buffer id.
  final BufferViewModelProvider<V> viewModel;

  /// Layout builder receiving the watched viewmodel.
  final Widget Function(BuildContext context, V viewModel) builder;

  @override
  ConsumerState<ReefWindow<V>> createState() => _ReefWindowState<V>();
}

class _ReefWindowState<V extends ViewModel<Object?>>
    extends ConsumerState<ReefWindow<V>> {
  late final BufferId bufferId = widget.bufferId ?? BufferId.generate();

  @override
  Widget build(BuildContext context) {
    // Keeps the buffer's scope alive while at least one window shows it.
    ref.watch(reefScopeProvider(bufferId));
    final V viewModel = ref.watch(widget.viewModel(bufferId));
    return ReefBufferScope(
      bufferId: bufferId,
      child: Builder(
        builder: (context) => widget.builder(context, viewModel),
      ),
    );
  }
}
