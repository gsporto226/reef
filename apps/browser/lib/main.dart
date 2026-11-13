// The browser integration app (docs/integration-apps.md): real web pages in
// reef windows. reef owns every navigation; the webview only renders the
// current history entry. This file wires the store, the controller and the
// shells; routes.dart, chrome.dart and page.dart hold the rest.
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reef/reef.dart';
import 'package:reef_multi_window/reef_multi_window.dart';
import 'package:reef_router/reef_router.dart';

import 'chrome.dart';
import 'file_store.dart';
import 'page.dart';
import 'routes.dart';

export 'chrome.dart';
export 'page.dart';
export 'routes.dart';

/// Launched with a URL (the default browser), it opens on top of the
/// restored session. A dragged-out tab is a real window with
/// `FLUTTER_WINDOWING=true` (master channel); without it, one window.
void main(List<String> args) => runWidget(
  BrowserApp(
    store: JsonFileHibernationStore(sessionFile()),
    launchArg: args.firstOrNull,
    platform: RealShellPlatform(title: 'Browser'),
  ),
);

/// The browser over [store]. [launchArg], a URL or an internal path, opens
/// in a new tab on top of the restored session (spec §9 cold start).
class BrowserApp extends StatefulWidget {
  const BrowserApp({
    super.key,
    required this.store,
    this.launchArg,
    this.platform,
  });

  final HibernationStore store;
  final String? launchArg;

  /// Opens the shells a dragged-out tab lands in: a [RealShellPlatform]
  /// draws each in its own platform window; any other (tests) draws every
  /// shell side by side in one view.
  final ShellPlatform? platform;

  static BrowserAppState of(BuildContext context) =>
      context.findAncestorStateOfType<BrowserAppState>()!;

  @override
  State<BrowserApp> createState() => BrowserAppState();
}

class BrowserAppState extends State<BrowserApp> {
  /// The global undo timeline: Ctrl+Shift+T reopens a closed tab on it.
  final undo = UndoController();

  /// The settings lock: the guard's environment (D8).
  final settingsLocked = ValueNotifier(false);
  late final _bound = links.bind(settingsLocked);
  late final controller = WindowingController(
    undo: undo,
    // Runs only when nothing was restored: a launch URL is then the only tab.
    initial: () => (_fresh = widget.launchArg != null)
        ? WindowingDoc.initial()
        : WindowingDoc.initial(
            buffer: links.linkOf(const NewTabRoute()).buffer,
          ),
    store: _forgetSessionUnlessRestored(),
    interceptor: _bound.interceptor,
    platform: widget.platform,
  );

  /// Deletes the saved layout before the controller reads it when
  /// "Restore session on start" is off. Peeked from the saved buckets: the
  /// value is registered on the controller, which restores the doc first.
  HibernationStore _forgetSessionUnlessRestored() {
    final store = widget.store;
    final restore = ReefRootRestorationBucket(store)
        .claimChild(_bucket)
        .peek(_restoreKey, restoreSession);
    if (!restore) store.delete(WindowingController.hibernationKey);
    return store;
  }

  /// Nothing was restored and a launch URL fills the empty first tab.
  var _fresh = false;

  static const _bucket = 'browser', _restoreKey = 'restoreSession';

  /// The "Restore session on start" setting; off starts fresh.
  final restoreSession = ReefRestorableValue(true);
  late final nav = LinkNavigator(links, controller);
  late final void Function() _unwatch;

  @override
  void initState() {
    super.initState();
    _unwatch = _bound.watch(controller, refresh: settingsLocked);
    controller.restoration.claimChild(_bucket)
      ..register('bookmarks', bookmarks)
      ..register(_restoreKey, restoreSession);
    if (widget.launchArg case final arg?) {
      final route = routeOfInput(arg);
      _fresh ? nav.go(route) : nav.openInNewTab(route);
    }
  }

  /// The bookmarked routes, oldest first; restored across restarts.
  final bookmarks = ReefRestorableValue<List<Object>>(
    const [],
    codec: bookmarksCodec,
  );

  /// Bookmarks [route] (the focused route by default), or clears its
  /// bookmark.
  void toggleBookmark([Object? route]) {
    route ??= focusedRoute;
    if (route == null) return;
    final now = bookmarks.value;
    bookmarks.value = now.contains(route)
        ? [...now.where((r) => r != route)]
        : [...now, route];
  }

  /// Whether the focused route is bookmarked.
  bool get bookmarked => bookmarks.value.contains(focusedRoute);

  /// Each web page window's webview, for tests to read the page through.
  final webViews = <WindowId, InAppWebViewController>{};

  /// Bumped when [webViews] changes, so a mirror finds its original's.
  final webViewsChanged = ValueNotifier(0);

  /// The route the focused window shows; null without one.
  Object? get focusedRoute => routeOf(controller.doc.value.activeWindowId);

  /// Route [window]'s current entry; null once the window is gone.
  Object? routeOf(WindowId? window) {
    final entry = controller.doc.value.windows[window]?.history.current;
    return entry == null
        ? null
        : links.routeOfBuffer(entry.buffer, entry.arguments);
  }

  @override
  void dispose() {
    _unwatch();
    controller.dispose();
    settingsLocked.dispose();
    bookmarks.dispose();
    restoreSession.dispose();
    webViewsChanged.dispose();
    super.dispose();
  }

  /// Opens [route] (a copy of the focused page when null) in a new window
  /// floating over the scope [scopeOf] picks, on top of its floats.
  WindowId? _float(
    FloatScope Function(WindowingDoc doc, WindowId focused) scopeOf, [
    Object? route,
  ]) {
    final doc = controller.doc.value;
    final focused = doc.activeWindowId;
    if (focused == null) return null;
    final id = WindowId.generate();
    final link = route == null ? null : links.linkOf(route);
    controller.dispatchAll([
      SplitWindow(
        focused,
        newWindowId: id,
        axis: Axis.horizontal,
        buffer: link?.buffer,
        arguments: link?.arguments ?? const {},
      ),
      FloatWindow(id, scope: scopeOf(doc, focused)),
    ]);
    return id;
  }

  /// Picture in picture: the focused page floats over the whole shell.
  WindowId? pictureInPicture() =>
      _float((doc, _) => ShellScope(doc.focusedShellId));

  /// The find panel floats over the focused window.
  WindowId? findInPage() => _float((_, w) => WindowScope(w), const FindRoute());

  /// The downloads popup floats over the focused tab.
  WindowId? downloads() => _float(
    (doc, _) => TabScope(doc.shells[doc.focusedShellId]!.activeTabId),
    const DownloadsRoute(),
  );

  /// Docks floating [window] on [side] of the focused tab's active window.
  void dock(WindowId window, DockSide side) {
    final doc = controller.doc.value;
    controller.dockWindow(
      window,
      tabId: doc.shells[doc.focusedShellId]!.activeTabId,
      side: side,
    );
  }

  /// Opens a fresh new tab page in a new tab.
  void newTab() => nav.openInNewTab(const NewTabRoute());

  /// Opens [route], the focused page when null, in a new window beside the
  /// focused one: an independent view with its own webview.
  void openInSplit([Object? route]) {
    if (route ?? focusedRoute case final r?) nav.openInSplit(r);
  }

  /// Mirrors the focused window beside it: the same entry with
  /// `view: shared`, drawing the original's webview (no second one).
  void mirrorSplit() {
    final doc = controller.doc.value;
    final focused = doc.activeWindowId;
    final entry = doc.windows[focused]?.history.current;
    if (focused == null || entry == null) return;
    controller.dispatchAll([
      SplitWindow(
        focused,
        newWindowId: WindowId.generate(),
        axis: Axis.horizontal,
        buffer: entry.buffer,
        arguments: {...entry.arguments, viewKey: 'shared'},
      ),
    ]);
  }

  /// Moves [tab] to the end of [shell]'s strip. The last tab of its shell
  /// takes the shell with it (the doc refuses to empty a shell).
  // ponytail: always appends; drop at the pointer's index if order matters.
  void moveTabTo(TabId tab, ShellId shell) {
    final doc = controller.doc.value;
    final from = doc.shells.keys.firstWhere(
      (s) => doc.shells[s]!.tabIds.contains(tab),
    );
    if (from == shell) return;
    final index = doc.shells[shell]!.tabIds.length;
    if (doc.shells[from]!.tabIds.length > 1) {
      return controller.moveTab(tab, shellId: shell, index: index);
    }
    final placeholder = TabId.generate();
    controller.dispatchAll([
      NewTab(shellId: from, tabId: placeholder),
      MoveTab(tab, shellId: shell, index: index),
      CloseShell(from),
    ]);
  }

  /// Each shell's surface, built once so a doc change doesn't rebuild it.
  final _shells = <ShellId, Widget>{};
  Widget _shell(ShellId id) =>
      _shells.putIfAbsent(id, () => BrowserShell(id, key: ObjectKey(id)));

  @override
  Widget build(BuildContext context) => LinkScope(
    navigator: nav,
    child: WindowingRoot(
      controller: controller,
      bufferBuilder: (_, buffer) => BrowserPage(buffer),
      delegate: WindowingDelegate(
        pageIdentity: links.pageIdentityOf,
        windowChrome: (_, id, _, page) =>
            controller.doc.value.floating.containsKey(id)
            ? FloatPanel(id, page)
            : page,
        // The chrome: tab strip over the toolbar.
        tabStrip: (_, shellId) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [TabStrip(shellId), Toolbar(shellId)],
        ),
        projectionPolicy: (_, _, _) =>
            (_, _, shellId) => DesktopProjection(shellId),
      ),
      child: switch (widget.platform) {
        final RealShellPlatform platform => ShellViews(
          controller: controller,
          platform: platform,
          shellBuilder: (_, id) => _shell(id),
        ),
        _ => ValueListenableBuilder(
          valueListenable: controller.doc,
          builder: (_, doc, _) => Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final id in doc.shells.keys) Expanded(child: _shell(id)),
            ],
          ),
        ),
      },
    ),
  );
}
