import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/src/links.dart';

/// How a change from [before] to [after] enters the browser history (spec
/// §9): a push when the focused window's history grew by the buffer it
/// showed before, else a replace of the current entry.
RouteInformationReportingType reportType(
  WindowingDoc before,
  WindowingDoc after,
) {
  final window = _focusedWindow(after);
  final was = before.windows[window]?.history;
  final now = after.windows[window]?.history;
  final pushed =
      was != null &&
      now != null &&
      listEquals(now.back, [...was.back, was.current]);
  return pushed
      ? RouteInformationReportingType.navigate
      : RouteInformationReportingType.neglect;
}

WindowId? _focusedWindow(WindowingDoc doc) =>
    doc.tabs[doc.shells[doc.focusedShellId]?.activeTabId]?.activeWindowId;

/// Keeps the route information (the browser URL on web) equal to the URL
/// [tree] gives the focused shell's focused buffer, and resolves the
/// initial route and every later route notification (browser back,
/// forward, a typed URL) through [tree] into
/// [WindowingController.openLink]. Place it under a [WindowingRoot].
class WindowingLinkSync extends StatefulWidget {
  const WindowingLinkSync({
    super.key,
    required this.tree,
    this.routeInformationProvider,
    required this.child,
  });

  /// Maps URLs to buffers and back.
  final LinkTree<Object?> tree;

  /// Default: the platform's, starting on its initial route.
  final RouteInformationProvider? routeInformationProvider;
  final Widget child;

  @override
  State<WindowingLinkSync> createState() => _WindowingLinkSyncState();
}

class _WindowingLinkSyncState extends State<WindowingLinkSync> {
  late final _owned = widget.routeInformationProvider == null
      ? PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(
            uri: Uri.parse(
              WidgetsBinding.instance.platformDispatcher.defaultRouteName,
            ),
          ),
        )
      : null;
  late final RouteInformationProvider _provider =
      widget.routeInformationProvider ?? _owned!;
  late final WindowingController _controller;
  late WindowingDoc _before;
  var _incoming = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        context.getInheritedWidgetOfExactType<WindowingScope>()!.controller;
    _before = _controller.doc.value;
    _controller.doc.addListener(_report);
    _provider.addListener(_open);
    _open().whenComplete(() {
      if (mounted) _report();
    });
  }

  @override
  void dispose() {
    _controller.doc.removeListener(_report);
    _provider.removeListener(_open);
    _owned?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WindowingLinkSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.routeInformationProvider,
          widget.routeInformationProvider),
      'WindowingLinkSync cannot switch route information providers',
    );
  }

  Future<void> _open() {
    // Echoes are muted until openLink completes, however late that is.
    _incoming++;
    final (:buffer, :arguments) = widget.tree.resolve(_provider.value.uri);
    return _controller
        .openLink(buffer, arguments: arguments)
        .whenComplete(() => _incoming--);
  }

  void _report() {
    final before = _before;
    final after = _before = _controller.doc.value;
    if (_incoming > 0) return;
    final window = after.windows[_focusedWindow(after)];
    if (window == null) return;
    final entry = window.history.current;
    final path = widget.tree.uriOfBuffer(entry.buffer, entry.arguments);
    if (path == null || path == _provider.value.uri) return;
    _provider.routerReportsNewRouteInformation(
      RouteInformation(uri: path),
      type: reportType(before, after),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      identical(
        context.getInheritedWidgetOfExactType<WindowingScope>()!.controller,
        _controller,
      ),
      'WindowingLinkSync cannot switch windowing controllers',
    );
    return widget.child;
  }
}
