// The browser integration app (docs/integration-apps.md): real web pages in
// reef windows. reef owns every navigation; the webview only renders the
// current history entry. This file wires the store, the controller and the
// shells; routes.dart, chrome.dart and page.dart hold the rest.
// ignore_for_file: experimental_member_use
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reef/reef.dart';
import 'package:reef_multi_window/reef_multi_window.dart';
import 'package:reef_router/reef_router.dart';

import 'chrome.dart';
import 'page.dart';
import 'routes.dart';
import 'src/tokens.g.dart';

export 'chrome.dart';
export 'page.dart';
export 'routes.dart';

/// The browser over [store]. [launchArg], a URL or an internal path, opens
/// in a new tab on top of the restored session (spec §9 cold start).
class BrowserApp extends StatefulWidget {
  const BrowserApp({
    super.key,
    required this.store,
    this.launchArg,
    this.platform,
    this.views,
  });

  final HibernationStore store;
  final String? launchArg;

  /// Opens the shells a dragged-out tab lands in: a [RealShellPlatform]
  /// draws each in its own platform window; any other (tests) draws every
  /// shell side by side in one view.
  final ShellPlatform? platform;

  /// Draws the shells over a real [platform] (lib/entry.dart supplies
  /// [ShellViews]); without it, every shell sits side by side in one view.
  final Widget Function(WindowingController, ShellBuilder)? views;

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
    interceptor: _intercept,
    platform: widget.platform,
    persistence: persistedSession,
    focusPolicy: WindowingFocusPolicy(
      closeEmptyTab: true,
      // Like Chrome: back with nothing left closes a page-opened pane.
      emptyBack: (doc) => _openedByPage.contains(doc.activeWindowId)
          ? emptyBackCloseWindow(doc)
          : emptyBackNothing(doc),
    ),
  );

  /// The most tabs one window (shell) holds; more are vetoed.
  static const maxTabs = 10;

  /// Below this width a side-by-side split stacks instead.
  static const narrowShell = 600.0;

  /// Each shell's last laid-out width, for the narrow-split check.
  final shellWidths = <ShellId, double>{};

  /// Windows a page opened (`target=_blank`, `window.open`).
  // ponytail: not restored; after a restart their back does nothing.
  final _openedByPage = <WindowId>{};

  /// Opens [route] in a new tab for a page; back on it with nothing left
  /// closes it.
  void openFromPage(Object route) {
    final before = controller.doc.value;
    nav.openInNewTab(route);
    final after = controller.doc.value;
    if (after != before) _openedByPage.add(after.activeWindowId!);
  }

  /// Vetoes closing a shell of more than one tab unless the user confirmed
  /// it ([confirmClose]); the settings guard sees every other command.
  CommandDecision _intercept(WindowingDoc doc, WindowingCommand command) =>
      switch (command) {
        CloseShell(:final shellId)
            when shellId != _confirmedClose &&
                (doc.shells[shellId]?.tabIds.length ?? 0) > 1 =>
          const CommandDecision.veto(UndoLabel('Close its tabs?')),
        NewTab(:final shellId) when _full(doc, shellId) => _tooManyTabs,
        MoveTab(:final tabId, :final shellId)
            when _full(doc, shellId) &&
                !doc.shells[shellId]!.tabIds.contains(tabId) =>
          _tooManyTabs,
        // A narrow window stacks a split rather than squeezing two pages.
        final SplitWindow s
            when s.axis == Axis.horizontal &&
                (shellWidths[_shellOf(doc, s.windowId)] ?? double.infinity) <
                    narrowShell =>
          _stacked(doc, s),
        _ => _bound.interceptor(doc, command),
      };

  /// The shell whose tab holds tree window [window].
  ShellId? _shellOf(WindowingDoc doc, WindowId window) {
    final tab = doc.tabOf(window);
    return doc.shells.keys
        .where((s) => doc.shells[s]!.tabIds.contains(tab))
        .firstOrNull;
  }

  bool _full(WindowingDoc doc, ShellId shell) =>
      (doc.shells[shell]?.tabIds.length ?? 0) >= maxTabs;

  static const _tooManyTabs = CommandDecision.veto(
    UndoLabel('A window holds at most $maxTabs tabs'),
  );

  /// [s] split vertically, past the settings guard too.
  CommandDecision _stacked(WindowingDoc doc, SplitWindow s) {
    final stacked = SplitWindow(
      s.windowId,
      newWindowId: s.newWindowId,
      axis: Axis.vertical,
      buffer: s.buffer,
      arguments: s.arguments,
      entryId: s.entryId,
    );
    final guarded = _bound.interceptor(doc, stacked);
    return guarded.approves ? CommandDecision.replace(stacked) : guarded;
  }

  /// The shell whose close the user confirmed, during that close only.
  ShellId? _confirmedClose;

  /// The shell whose vetoed close awaits the user's answer.
  final closePrompt = ValueNotifier<ShellId?>(null);

  void _vetoed() => switch (controller.vetoes.value) {
    CommandVeto(command: CloseShell(:final shellId)) =>
      closePrompt.value = shellId,
    final veto? => vetoNotice.value = veto.reason.localize(),
    null => null,
  };

  /// Another veto's reason, shown until dismissed.
  final vetoNotice = ValueNotifier<String?>(null);

  /// Answers the close prompt: [confirmed] closes its shell past the check.
  void answerClose({required bool confirmed}) {
    final shell = closePrompt.value;
    closePrompt.value = null;
    if (!confirmed || shell == null) return;
    _confirmedClose = shell;
    controller.closeShell(shell);
    _confirmedClose = null;
  }

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

  /// The "Open links in" setting: [pane], [split] or [tab]. It sets how a
  /// go link (address bar, history, bookmarks) opens a page not yet open;
  /// an open one is still focused (the link policy).
  final openIn = ReefRestorableValue(pane);
  static const pane = 'pane', split = 'split', tab = 'tab';

  void _applyOpenIn() => controller.openPolicy = switch (openIn.value) {
    split => splitBesideOpenPolicy,
    tab => newTabOpenPolicy,
    _ => defaultOpenPolicy,
  };
  late final void Function() _unwatch;

  /// The "Memory saver" setting: on, a background tab releases its pages
  /// (webviews) and reloads them when activated; off, every tab stays
  /// loaded.
  final memorySaver = ReefRestorableValue(true);

  /// Tabs that stay loaded in the background even with [memorySaver] on.
  // ponytail: not restored; restore it with a codec if pins must survive a
  // restart.
  final pinnedTabs = ValueNotifier<Set<TabId>>(const {});

  /// Pins the focused tab, or unpins it.
  void togglePin() {
    final tab = focusedTab;
    final now = pinnedTabs.value;
    pinnedTabs.value = now.contains(tab)
        ? ({...now}..remove(tab))
        : {...now, tab};
  }

  /// The focused shell's active tab.
  TabId get focusedTab {
    final doc = controller.doc.value;
    return doc.shells[doc.focusedShellId]!.activeTabId;
  }

  bool _keepTabAlive(TabId tab) =>
      !memorySaver.value || pinnedTabs.value.contains(tab);

  @override
  void initState() {
    super.initState();
    _unwatch = _bound.watch(controller, refresh: settingsLocked);
    controller.vetoes.addListener(_vetoed);
    controller.restoration.claimChild(_bucket)
      ..register('bookmarks', bookmarks)
      ..register(_restoreKey, restoreSession)
      ..register('openIn', openIn)
      ..register('memorySaver', memorySaver);
    openIn.addListener(_applyOpenIn);
    _applyOpenIn();
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
    closePrompt.dispose();
    vetoNotice.dispose();
    openIn.dispose();
    memorySaver.dispose();
    pinnedTabs.dispose();
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

  /// Opens [route], the focused page when null, in a new platform window;
  /// without pop-out, in a new tab.
  void openInNewWindow([Object? route]) {
    if (route ?? focusedRoute case final r?) nav.openInNewWindow(r);
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

  /// Moves the focused pane into a new tab of its shell: one undo step, and
  /// the window keeps its history.
  void moveToNewTab() {
    final doc = controller.doc.value;
    final window = doc.activeWindowId;
    if (window == null) return;
    final tab = TabId.generate();
    controller.dispatchAll([
      NewTab(shellId: doc.focusedShellId, tabId: tab),
      MoveWindow(window, tabId: tab),
    ]);
  }

  /// Moves the focused pane beside [shell]'s active window, in its active
  /// tab. The source tab may be left empty (spec §2).
  void moveToShell(ShellId shell) {
    final doc = controller.doc.value;
    final window = doc.activeWindowId;
    final tab = doc.shells[shell]?.activeTabId;
    if (window == null || tab == null) return;
    controller.moveWindow(window, tabId: tab);
  }

  /// Each shell's surface, built once so a doc change doesn't rebuild it.
  final _shells = <ShellId, Widget>{};
  Widget _shell(ShellId id) =>
      _shells.putIfAbsent(id, () => BrowserShell(id, key: ObjectKey(id)));

  @override
  Widget build(BuildContext context) => LinkScope(
    navigator: nav,
    // A new delegate re-reads which background tabs stay loaded.
    child: ListenableBuilder(
      listenable: Listenable.merge([memorySaver, pinnedTabs]),
      builder: (_, _) => _root(),
    ),
  );

  Widget _root() => WindowingRoot(
    controller: controller,
    bufferBuilder: (_, buffer) => BrowserPage(buffer),
    delegate: WindowingDelegate(
      pageIdentity: links.pageIdentityOf,
      windowChrome: (_, id, _, page) =>
          controller.doc.value.floating.containsKey(id)
          ? FloatPanel(id, page)
          : Pane(id, page),
      // The chrome: tab strip over the toolbar.
      tabStrip: (_, shellId) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [TabStrip(shellId), Toolbar(shellId)],
      ),
      projectionPolicy: (_, _, _) =>
          (_, _, shellId) => DesktopProjection(shellId),
      keepTabAlive: _keepTabAlive,
      labels: WindowingLabels(
        tab: (id) => UndoLabel(
          titleOf(
            routeOf(controller.doc.value.tabs[id]?.activeWindowId) ??
                const NewTabRoute(),
          ),
        ),
        window: (id) => UndoLabel(titleOf(routeOf(id) ?? const NewTabRoute())),
      ),
      emptyBuilder: (_, _) => const EmptyTab(),
      splitter: (_, axis) => SizedBox(
        width: axis == Axis.horizontal ? T.space4 : null,
        height: axis == Axis.horizontal ? null : T.space4,
        child: const ColoredBox(color: T.borderHairline),
      ),
    ),
    child:
        widget.views?.call(controller, (_, id) => _shell(id)) ??
        ValueListenableBuilder(
        valueListenable: controller.doc,
        builder: (_, doc, _) => Row(
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in doc.shells.keys) Expanded(child: _shell(id)),
          ],
        ),
      ),
  );
}

/// The doc the session saves: no picture-in-picture floats, and no tab
/// showing only a fresh New Tab page, except a shell's last tab: closing
/// that would close the shell or empty the tab (ADR 0012).
WindowingDoc persistedSession(WindowingDoc doc) => doc.applyAll([
  for (final MapEntry(:key, :value) in doc.floating.entries)
    if (value.scope is ShellScope) CloseWindow(key),
  for (final shell in doc.shells.values)
    for (final tab in [
      for (final tab in shell.tabIds)
        if (doc.tabs[tab]?.root case WindowLeaf(:final id)
            when _freshNewTab(doc.windows[id]?.history))
          tab,
    ].take(shell.tabIds.length - 1))
      CloseTab(tab),
]);

bool _freshNewTab(BufferHistory? history) =>
    history != null &&
    history.back.isEmpty &&
    history.forward.isEmpty &&
    links.routeOfBuffer(history.current.buffer, history.current.arguments)
        is NewTabRoute;
