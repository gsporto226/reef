// The windowing API is experimental (flutter/flutter#30701): `@internal`,
// master-channel only, enabled per invocation with `FLUTTER_WINDOWING=true`
// (see main_windowed.dart).
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/src/widgets/_window.dart' as windowing;
import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/features/windowing/buffer_window_page.dart';

/// What to render in a new OS window: one buffer, popped out.
class BufferWindowRequest {
  const BufferWindowRequest({
    required this.bufferId,
    required this.title,
    this.size = const Size(480, 360),
  });

  final BufferId bufferId;
  final String title;
  final Size size;
}

/// The seam between the example app and Flutter's experimental windowing API
/// (blueprint §10.4). The app talks to this interface only — the unstable
/// `@internal` API is quarantined in [RealWindowHost], and the fake keeps the
/// intent testable without the windowing feature flag.
abstract interface class WindowHost {
  /// Whether windows can be opened from [context] — a [WindowRegistry] must
  /// be in scope (the app must be running under a window manager).
  bool isSupportedIn(BuildContext context);

  /// Opens a new OS window rendering [request].
  void open(BuildContext context, BufferWindowRequest request);
}

/// Test double: records requests.
class FakeWindowHost implements WindowHost {
  final List<BufferWindowRequest> requests = [];

  @override
  bool isSupportedIn(BuildContext context) => true;

  @override
  void open(BuildContext context, BufferWindowRequest request) =>
      requests.add(request);
}

/// Real seam: creates a regular [WindowController] per request and registers
/// it with the ambient [WindowRegistry]; the manager renders the entry.
class RealWindowHost implements WindowHost {
  RealWindowHost({required this.contentBuilder});

  /// Builds the page for a popped-out buffer — the same kind→page mapping the
  /// workspace registry uses, so any routable buffer can leave the tree.
  final Widget Function(BuildContext context, BufferId bufferId) contentBuilder;

  @override
  bool isSupportedIn(BuildContext context) =>
      windowing.WindowRegistry.maybeOf(context) != null;

  @override
  void open(BuildContext context, BufferWindowRequest request) {
    final registry = windowing.WindowRegistry.maybeOf(context);
    if (registry == null) {
      return;
    }
    final delegate = _ManagedWindowDelegate(registry);
    final controller = windowing.WindowController(
      size: request.size,
      title: request.title,
      delegate: delegate,
    );
    final entry = windowing.WindowEntry(
      controller: controller,
      builder: (_) => BufferWindowPage(
        bufferId: request.bufferId,
        title: request.title,
        contentBuilder: contentBuilder,
      ),
    );
    delegate.attach(entry);
    registry.register(entry);
  }
}

/// Keeps the registry in sync: an entry must be unregistered before its
/// window is destroyed.
class _ManagedWindowDelegate extends windowing.WindowControllerDelegate {
  _ManagedWindowDelegate(this._registry);

  final windowing.WindowRegistry _registry;
  windowing.WindowEntry? _entry;

  void attach(windowing.WindowEntry entry) => _entry = entry;

  @override
  void onWindowCloseRequested(windowing.WindowController controller) {
    final entry = _entry;
    if (entry != null) {
      _registry.unregister(entry);
    }
    controller.destroy();
  }
}
