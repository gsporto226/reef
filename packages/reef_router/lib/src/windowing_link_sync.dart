import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/reef.dart';

/// How a change from [before] to [after] enters the browser history (spec
/// §9): a push when the focused window's back stack grew by the buffer it
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

/// Keeps the route information (the browser URL on web) equal to the
/// focused shell's focused buffer path, and sends the initial route and
/// every later route notification (browser back, forward, a typed URL) to
/// [WindowingController.openLink]. Place it under a [WindowingRoot].
class WindowingLinkSync extends StatefulWidget {
  const WindowingLinkSync({
    super.key,
    this.routeInformationProvider,
    required this.child,
  });

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
  var _incoming = false;

  @override
  void initState() {
    super.initState();
    _controller =
        context.getInheritedWidgetOfExactType<WindowingScope>()!.controller;
    _before = _controller.doc.value;
    _controller.doc.addListener(_report);
    _provider.addListener(_open);
    _open();
    _report();
  }

  @override
  void dispose() {
    _controller.doc.removeListener(_report);
    _provider.removeListener(_open);
    _owned?.dispose();
    super.dispose();
  }

  void _open() {
    _incoming = true;
    // Without newShell, openLink dispatches before its first await.
    _controller.openLink(BufferPath.fromUri(_provider.value.uri));
    _incoming = false;
  }

  void _report() {
    final before = _before;
    final after = _before = _controller.doc.value;
    if (_incoming) return;
    final window = after.windows[_focusedWindow(after)];
    if (window == null) return;
    final path = _controller.links.pathOf(window.history.current)?.toUri();
    if (path == null || path == _provider.value.uri) return;
    _provider.routerReportsNewRouteInformation(
      RouteInformation(uri: path),
      type: reportType(before, after),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
