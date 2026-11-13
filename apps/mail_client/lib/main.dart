// The mail client integration app (docs/integration-apps.md): folders, a
// thread list and threads in one windowing doc of three windows, the nav
// (folder list), the list (one folder) and the detail (a thread or a draft).
// One custom arrangement draws them per screen class, as design/SPEC.md
// lays the screens out.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mail_client/src/components.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

void main() => runApp(MailApp(store: InMemoryHibernationStore()));

typedef Thread = ({
  String folder,
  String sender,
  String time,
  String sent,
  String subject,
  String preview,
  String body,
  bool unread,
});

typedef Folder = ({String name, MailGlyph glyph});

const folders = <String, Folder>{
  'inbox': (name: 'Inbox', glyph: MailGlyph.inbox),
  'archive': (name: 'Archive', glyph: MailGlyph.archive),
  'sent': (name: 'Sent', glyph: MailGlyph.send),
};

/// The threads every mailbox starts with.
const seedThreads = <String, Thread>{
  '42': (
    folder: 'inbox',
    sender: 'Maya Okafor',
    time: '11:42',
    sent: 'Today, 11:42',
    subject: 'Lunch on Friday?',
    preview: "Noon works. The place on Rua Augusta, if you're still up for it.",
    body:
        "Noon works.\n\nThe place on Rua Augusta, if you're still up for it. "
        "I'll book a table for three; Ana said she might join after her "
        'call.\n\nMaya',
    unread: true,
  ),
  '7': (
    folder: 'inbox',
    sender: 'CI Bot',
    time: '09:05',
    sent: 'Today, 09:05',
    subject: 'Build is green',
    preview: 'Ship it. All 214 checks passed on main.',
    body: 'Ship it. All 214 checks passed on main.',
    unread: true,
  ),
  '13': (
    folder: 'archive',
    sender: 'Ledger',
    time: 'Nov 2',
    sent: '2 Nov, 16:10',
    subject: 'Old receipts',
    preview: 'Your October receipts, attached.',
    body: 'Your October receipts, attached.',
    unread: false,
  ),
};

/// The app's threads: the seed plus what was sent this session.
class Mailbox extends ChangeNotifier {
  final threads = Map<String, Thread>.of(seedThreads);
  var _sent = 0;

  /// The threads of folder [folderId], by id.
  List<(String, Thread)> inFolder(String folderId) => [
    for (final MapEntry(:key, :value) in threads.entries)
      if (value.folder == folderId) (key, value),
  ];

  int unread(String folderId) =>
      inFolder(folderId).where((e) => e.$2.unread).length;

  /// The threads whose sender, subject or body contain [query], in any
  /// case.
  List<(String, Thread)> search(String query) {
    final q = query.toLowerCase();
    return [
      for (final MapEntry(:key, :value) in threads.entries)
        if ([
          value.sender,
          value.subject,
          value.body,
        ].any((f) => f.toLowerCase().contains(q)))
          (key, value),
    ];
  }

  /// Files a draft in Sent as a read thread; returns its id.
  String send({
    required String to,
    required String subject,
    required String body,
    required DateTime at,
  }) {
    final id = 'sent-${++_sent}';
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    threads[id] = (
      folder: 'sent',
      sender: to,
      time: time,
      sent: 'Today, $time',
      subject: subject.isEmpty ? '(no subject)' : subject,
      preview: body.split('\n').first,
      body: body,
      unread: false,
    );
    notifyListeners();
    return id;
  }
}

/// The folder list: `/folders`.
final class FoldersRoute {
  const FoldersRoute();

  static final link = Link<FoldersRoute>('folders').build(FoldersRoute.new);
}

/// One folder's threads: `/folders/inbox`.
final class FolderRoute {
  const FolderRoute(this.id);
  final String id;

  static final link = Link<FolderRoute>(
    'folders',
  ).field((r) => r.id).build(FolderRoute.new);
}

/// One thread: `/threads/42`.
final class ThreadRoute {
  const ThreadRoute(this.id);
  final String id;

  static final link = Link<ThreadRoute>(
    'threads',
  ).field((r) => r.id).build(ThreadRoute.new);
}

/// The threads matching a query: `/search/lunch`.
final class SearchRoute {
  const SearchRoute(this.query);
  final String query;

  static final link = Link<SearchRoute>(
    'search',
  ).field((r) => r.query).build(SearchRoute.new);
}

/// A new draft: `/compose`. Fresh, so each open is its own draft (D3).
final class ComposeRoute {
  const ComposeRoute();

  static final link = Link<ComposeRoute>(
    'compose',
  ).build(ComposeRoute.new).fresh();
}

/// Any other path.
final class MailNotFoundRoute {
  const MailNotFoundRoute(this.path);
  final List<String> path;

  static final link = Link<MailNotFoundRoute>(
    '',
  ).rest((r) => r.path).build(MailNotFoundRoute.new);
}

/// Every mail link. The empty detail is a buffer no link reaches.
final links = LinkTree<Object>([
  FoldersRoute.link,
  FolderRoute.link,
  ThreadRoute.link,
  SearchRoute.link,
  ComposeRoute.link,
  MailNotFoundRoute.link,
]);

/// The route [buffer] shows; [MailNotFoundRoute] for a buffer no link
/// reaches.
Object routeOf(BufferId buffer) => links.routeOfBuffer(buffer);

final folderList = links.linkOf(const FoldersRoute()).buffer;

/// The detail window's bottom entry: no thread selected.
const noThread = BufferId.manual('empty:');

BufferId folder(String id) => links.linkOf(FolderRoute(id)).buffer;

BufferId thread(String id) => links.linkOf(ThreadRoute(id)).buffer;

BufferId search(String query) => links.linkOf(SearchRoute(query)).buffer;

/// The active tab's windows by role, from the buffer each one shows.
typedef MailWindows = ({WindowId? nav, WindowId? list, WindowId? detail});

MailWindows mailWindows(WindowingDoc doc) {
  WindowId? nav, list, detail;
  for (final w in doc.activeTab.root?.windowIds ?? const <WindowId>[]) {
    final buffer = doc.windows[w]!.history.current.buffer;
    if (buffer == folderList) {
      nav = w;
    } else if (routeOf(buffer) is FolderRoute ||
        routeOf(buffer) is SearchRoute) {
      list = w;
    } else {
      detail = w;
    }
  }
  return (nav: nav, list: list, detail: detail);
}

/// The first-run layout: nav | inbox | the first thread, the inbox focused.
WindowingDoc defaultLayout() {
  final start = WindowingDoc.initial(buffer: folderList);
  final nav = start.activeWindowId!;
  final (list, detail) = (WindowId.generate(), WindowId.generate());
  return start.applyAll([
    SplitWindow(nav, newWindowId: list, axis: Axis.horizontal),
    SplitWindow(list, newWindowId: detail, axis: Axis.horizontal),
    AttachBuffer(list, folder('inbox')),
    AttachBuffer(detail, noThread),
    PushBuffer(detail, thread('42')),
    ActivateWindow(list),
  ]);
}

/// A folder replaces the list window's buffer and clears the detail; a
/// search is pushed on the list, or replaces the search shown there; a
/// thread or draft is pushed on the detail, unless it shows there already.
/// The folder list, or a doc without those windows, goes through reef's
/// default.
List<WindowingCommand> mailOpenPolicy(
  WindowingDoc doc,
  BufferId buffer, {
  Map<String, String> arguments = const {},
}) {
  final (:nav, :list, :detail) = mailWindows(doc);
  final route = routeOf(buffer);
  if (route is FolderRoute && list != null) {
    return [
      AttachBuffer(list, buffer, arguments: arguments),
      if (detail != null) AttachBuffer(detail, noThread),
      ActivateWindow(list),
    ];
  }
  if (route is SearchRoute && list != null) {
    final searching =
        routeOf(doc.windows[list]!.history.current.buffer) is SearchRoute;
    return [
      searching
          ? ReplaceBuffer(list, buffer, arguments: arguments)
          : PushBuffer(list, buffer, arguments: arguments),
      ActivateWindow(list),
    ];
  }
  if (route is! FoldersRoute && route is! FolderRoute && detail != null) {
    return [
      if (doc.windows[detail]!.history.current !=
          HistoryEntry(buffer, arguments: arguments))
        PushBuffer(detail, buffer, arguments: arguments),
      ActivateWindow(detail),
    ];
  }
  return defaultOpenPolicy(doc, buffer, arguments: arguments);
}

/// Back with nothing behind it: the open nav closes onto the list; else
/// back reaches the platform.
List<WindowingCommand>? _navBack(WindowingDoc doc) =>
    switch (mailWindows(doc)) {
      (:final nav?, :final list?, detail: _) when doc.activeWindowId == nav => [
        ActivateWindow(list),
      ],
      _ => null,
    };

/// The mail client over [store]. A [launchLink] (a tapped notification)
/// opens on top of the restored doc, or into an empty one on a fresh
/// install.
class MailApp extends StatefulWidget {
  const MailApp({super.key, required this.store, this.launchLink});

  final HibernationStore store;
  final Uri? launchLink;

  static MailAppState of(BuildContext context) =>
      context.findAncestorStateOfType<MailAppState>()!;

  @override
  State<MailApp> createState() => MailAppState();
}

class MailAppState extends State<MailApp> with WidgetsBindingObserver {
  late final WindowingController controller;
  late final nav = LinkNavigator(links, controller);

  /// Desktop sidebar `State=Collapsed`.
  final collapsed = ValueNotifier(false);

  /// The tablet inbox overlay is open over the detail.
  final overlay = ValueNotifier(false);

  /// The last active window that isn't the nav: a tap on the sidebar
  /// activates the nav window, and the tablet screens must not follow it.
  final content = ValueNotifier<WindowId?>(null);

  final mailbox = Mailbox();

  @override
  void initState() {
    super.initState();
    controller = WindowingController(
      // Runs only on a fresh install: a notification opens into an empty doc.
      initial: () =>
          widget.launchLink != null ? WindowingDoc.initial() : defaultLayout(),
      store: widget.store,
      openPolicy: mailOpenPolicy,
      focusPolicy: const WindowingFocusPolicy(emptyBack: _navBack),
    )..doc.addListener(_track);
    _track();
    WidgetsBinding.instance.addObserver(this);
    if (widget.launchLink case final uri?) notify(uri);
  }

  WindowId? get _active => controller.doc.value.activeWindowId;

  void _track() {
    final active = _active, w = windows;
    if (active == w.nav) return;
    // In the overlay, a tap on the list activates it: that's still the
    // overlay, not the tablet inbox.
    if (overlay.value && active == w.list) return;
    overlay.value = false;
    content.value = active;
  }

  MailWindows get windows => mailWindows(controller.doc.value);

  BufferId? _shows(WindowId? window) =>
      controller.doc.value.windows[window]?.history.current.buffer;

  /// The detail window shows a thread or a draft.
  bool get hasDetail => switch (_shows(windows.detail)) {
    final b? => b != noThread,
    null => false,
  };

  /// The folder the list window shows; null while it shows a search.
  String? get listFolder => switch (_shows(windows.list)) {
    final b? => switch (routeOf(b)) {
      FolderRoute(:final id) => id,
      _ => null,
    },
    null => 'inbox',
  };

  /// The query the list window shows, or empty.
  String get query => switch (_shows(windows.list)) {
    final b? => switch (routeOf(b)) {
      SearchRoute(:final query) => query,
      _ => '',
    },
    null => '',
  };

  /// The search bar's text: a search on the list, pushed over the folder
  /// and replaced while typing; an empty one goes back to the folder.
  void searchFor(String text) {
    if (text.isNotEmpty) {
      controller.openBuffer(search(text));
    } else if (query.isNotEmpty) {
      controller.popBuffer(windows.list!);
    }
  }

  /// A tapped push notification for [uri].
  Future<void> notify(Uri uri) => nav.go(links.routeOf(uri));

  /// A fresh draft each time.
  void compose() =>
      controller.openBuffer(links.linkOf(const ComposeRoute()).buffer);

  void openThread(String id) => controller.openBuffer(thread(id));

  /// A folder in the sidebar. The folder the list already shows: desktop
  /// leaves a draft for it, tablet toggles the overlay, mobile shows it.
  void openFolder(BuildContext context, String id) {
    final (:nav, :list, :detail) = windows;
    if (list == null || _shows(list) != folder(id)) {
      overlay.value = false;
      controller.openBuffer(folder(id));
      return;
    }
    switch (screenTypeOf(context)) {
      case ScreenType.desktop:
        if (_shows(detail) case final d? when routeOf(d) is ComposeRoute) {
          controller.popBuffer(detail!);
        }
      case ScreenType.tablet when hasDetail:
        overlay.value = !overlay.value;
      case _:
        controller.activateWindow(list);
    }
  }

  /// Back link: on to the list, whatever the detail history holds.
  void closeDetail() {
    final (:nav, :list, :detail) = windows;
    if (detail == null) return;
    controller.attachBuffer(detail, noThread);
    if (list != null) controller.activateWindow(list);
  }

  /// Send files the draft in Sent. Desktop then returns to what the draft
  /// covered, the others to the list (SPEC.md Flows).
  void send(
    BuildContext context, {
    required String to,
    required String subject,
    required String body,
  }) {
    mailbox.send(to: to, subject: subject, body: body, at: DateTime.now());
    screenTypeOf(context) == ScreenType.desktop
        ? controller.popBuffer(windows.detail!)
        : closeDetail();
  }

  void openNav() => controller.activateWindow(windows.nav!);

  void closeNav() {
    if (windows.list case final list?) controller.activateWindow(list);
  }

  /// System back and Escape: close the tablet overlay, else the
  /// controller's back (which closes the open nav, see [_navBack]).
  bool back(BuildContext context) {
    if (screenTypeOf(context) == ScreenType.tablet && overlay.value) {
      overlay.value = false;
      return true;
    }
    return controller.back();
  }

  // The tablet overlay is app state, not a window, so the app takes
  // system back itself rather than through WindowingSystemBack.
  @override
  Future<bool> didPopRoute() async => back(context);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    collapsed.dispose();
    overlay.dispose();
    content.dispose();
    mailbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mail',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: T.accentDefault,
      ),
    ),
    home: Builder(
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (screenTypeOf(context) != ScreenType.desktop) back(context);
          },
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: T.surfaceList,
            child: LinkScope(
              navigator: nav,
              child: WindowingRoot(
                controller: controller,
                bufferBuilder: (_, buffer) => MailPage(buffer),
                delegate: WindowingDelegate(
                  windowChrome: (_, _, _, page) => page,
                  windowArrangement: WindowArrangement.custom(
                    (_, tabId) => MailLayout(tabId),
                  ),
                  // One projection on every screen class, without a tab strip.
                  projectionPolicy: (_, _, _) =>
                      (_, _, shellId) =>
                          DesktopProjection(shellId, showTabStrip: false),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Tab [tabId]'s windows laid out as the SPEC.md screens of this screen
/// class.
class MailLayout extends StatelessWidget {
  const MailLayout(this.tabId, {super.key});

  final TabId tabId;

  @override
  Widget build(BuildContext context) {
    final app = MailApp.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.controller.doc,
        app.collapsed,
        app.overlay,
        app.content,
      ]),
      builder: (context, _) {
        final (:nav, :list, :detail) = app.windows;
        // A tap on the sidebar leaves the active window where it was.
        Widget host(WindowId? id) => id == null
            ? const SizedBox.shrink()
            : WindowHost(id, activateOnPointer: id != nav);
        final active = app.controller.doc.value.tabs[tabId]?.activeWindowId;
        final navOpen = active != null && active == nav;
        return switch (screenTypeOf(context)) {
          ScreenType.desktop => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (nav != null)
                SizedBox(
                  width: app.collapsed.value
                      ? T.sidebarWidthCollapsed
                      : T.sidebarWidthExpanded,
                  child: host(nav),
                ),
              Expanded(
                child: Column(
                  children: [
                    const _TopBar(searchWidth: T.searchWidthDesktop),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (list != null)
                            SizedBox(
                              width: T.paneListWidthDesktop,
                              child: host(list),
                            ),
                          Expanded(child: host(detail)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ScreenType.tablet => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (nav != null)
                SizedBox(width: T.sidebarWidthCollapsed, child: host(nav)),
              Expanded(
                child: Column(
                  children: [
                    const _TopBar(),
                    Expanded(
                      child: app.content.value == detail && app.hasDetail
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                // A tap on the reading pane closes the
                                // overlay.
                                Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: (_) =>
                                      app.overlay.value = false,
                                  child: host(detail),
                                ),
                                if (app.overlay.value && list != null)
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: T.paneListWidthTablet,
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        boxShadow: elevationOverlay,
                                      ),
                                      child: host(list),
                                    ),
                                  ),
                              ],
                            )
                          : host(list ?? detail),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ScreenType.mobile => Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: active == detail && app.hasDetail
                        ? host(detail)
                        : host(list ?? detail),
                  ),
                  _MobileBar(navOpen: navOpen),
                ],
              ),
              if (navOpen)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: T.sidebarWidthExpanded,
                  child: host(nav),
                ),
            ],
          ),
        };
      },
    );
  }
}

/// Top bar, desktop and tablet; [searchWidth] null fills.
class _TopBar extends StatelessWidget {
  const _TopBar({this.searchWidth});

  final double? searchWidth;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: T.space12,
      horizontal: T.space24,
    ),
    decoration: hairlineBar(),
    alignment: Alignment.center,
    child: _Search(width: searchWidth),
  );
}

/// Top bar, mobile: at the bottom, Search beside the `Nav toggle`. While
/// the nav is open the toggle keeps its slot, hidden and inert.
class _MobileBar extends StatelessWidget {
  const _MobileBar({required this.navOpen});

  final bool navOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      T.space24,
      T.space12,
      T.space12,
      T.space12,
    ),
    decoration: hairlineBar(top: true),
    child: Row(
      spacing: T.space16,
      children: [
        const Expanded(child: _Search()),
        navOpen
            ? const SizedBox.square(dimension: T.sizeControlMd)
            : IconControl(
                MailGlyph.sidebarExpand,
                label: 'Folders',
                onTap: MailApp.of(context).openNav,
              ),
      ],
    ),
  );
}

/// The page for one mail buffer, picked by its kind.
class MailPage extends StatelessWidget {
  const MailPage(this.buffer, {super.key});

  final BufferId buffer;

  @override
  Widget build(BuildContext context) {
    return switch (routeOf(buffer)) {
      FoldersRoute() => const _Sidebar(),
      FolderRoute(:final id) => _ThreadList(folderId: id),
      SearchRoute(:final query) => _ThreadList(query: query),
      ThreadRoute(:final id) => _ThreadPane(id),
      ComposeRoute() => const _ComposePane(),
      _ when buffer == noThread => const Paper(
        color: T.surfaceReading,
        child: SizedBox.expand(),
      ),
      _ => Center(child: Text('Unknown buffer ${buffer.id}')),
    };
  }
}

/// The search bar, kept in step with the list window: it shows the query
/// the list shows, and empties when back leaves the search.
class _Search extends StatefulWidget {
  const _Search({this.width});

  final double? width;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final text = TextEditingController();
  late final MailAppState app = MailApp.of(context);

  void _sync() {
    if (text.text != app.query) text.text = app.query;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    app.controller.doc.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    app.controller.doc.removeListener(_sync);
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MailSearchBar(
    width: widget.width,
    controller: text,
    onChanged: app.searchFor,
  );
}

/// `Sidebar`: Expanded or Collapsed on desktop, Collapsed on tablet,
/// Expanded right on mobile.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final app = MailApp.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.controller.doc,
        app.collapsed,
        app.mailbox,
      ]),
      builder: (context, _) {
        final selected = app.listFolder;
        final screen = screenTypeOf(context);
        if (screen == ScreenType.mobile) return _NavPill(selected);
        final expanded = screen == ScreenType.desktop && !app.collapsed.value;
        return DecoratedBox(
          decoration: const BoxDecoration(color: T.surfaceNav),
          child: DecoratedBox(
            decoration: rightHairline,
            position: DecorationPosition.foreground,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: T.space20,
                horizontal: expanded ? T.space12 : T.space10,
              ),
              child: Column(
                crossAxisAlignment: expanded
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                spacing: T.space4,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: T.space4),
                    child: expanded
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Mail',
                                style: MailText.serifBrand24.copyWith(
                                  color: T.textPrimary,
                                ),
                              ),
                              IconControl(
                                MailGlyph.sidebarCollapse,
                                label: 'Collapse sidebar',
                                onTap: () => app.collapsed.value = true,
                              ),
                            ],
                          )
                        : IconControl(
                            MailGlyph.sidebarExpand,
                            label: 'Expand sidebar',
                            // Tablet stays collapsed (SPEC.md Open issues).
                            onTap: screen == ScreenType.desktop
                                ? () => app.collapsed.value = false
                                : null,
                          ),
                  ),
                  PrimaryButton(
                    glyph: MailGlyph.pencil,
                    semanticLabel: 'Compose',
                    label: expanded ? 'Compose' : null,
                    radius: expanded ? T.radiusLg : T.radiusMd,
                    onTap: app.compose,
                  ),
                  const SizedBox(height: T.space16),
                  if (expanded)
                    Text(
                      'Folders'.toUpperCase(),
                      style: MailText.sansOverline12.copyWith(
                        color: T.textMuted,
                      ),
                    ),
                  for (final MapEntry(:key, :value) in folders.entries)
                    FolderRow(
                      name: value.name,
                      glyph: value.glyph,
                      selected: key == selected,
                      count: switch (app.mailbox.unread(key)) {
                        0 => null,
                        final n => '$n',
                      },
                      showLabel: expanded,
                      onTap: () => app.openFolder(context, key),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `Sidebar / Expanded right`: labels beside the icon pill, bottom-right.
class _NavPill extends StatelessWidget {
  const _NavPill(this.selected);

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final app = MailApp.of(context);
    void folderTap(String id) {
      app.openFolder(context, id);
      app.closeNav();
    }

    final rows = [
      ('Sent', () => folderTap('sent')),
      ('Archive', () => folderTap('archive')),
      ('Inbox', () => folderTap('inbox')),
      ('Compose', app.compose),
    ];
    return Container(
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.only(right: T.space12, bottom: T.space12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              T.space8,
              T.space12,
              T.space8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: T.space8,
              children: [
                for (final (label, onTap) in rows)
                  Tap(
                    label: label,
                    onTap: onTap,
                    child: SizedBox(
                      height: T.sizeControlMd,
                      child: Center(
                        child: Text(
                          label,
                          style: MailText.sansLabelStrong15.copyWith(
                            color: T.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: T.sizeControlMd), // Close spacer
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: T.surfaceNav,
              border: hairlineAll,
              borderRadius: BorderRadius.circular(T.radiusMd),
              boxShadow: elevationOverlay,
            ),
            child: Padding(
              padding: const EdgeInsets.all(T.space8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: T.space8,
                children: [
                  for (final id in ['sent', 'archive', 'inbox'])
                    FolderRow(
                      name: folders[id]!.name,
                      glyph: folders[id]!.glyph,
                      selected: id == selected,
                      showLabel: false,
                      onTap: () => folderTap(id),
                    ),
                  PrimaryButton(
                    glyph: MailGlyph.pencil,
                    semanticLabel: 'Compose',
                    onTap: app.compose,
                  ),
                  IconControl(
                    MailGlyph.sidebarCollapseRight,
                    label: 'Close',
                    radius: T.radiusSm,
                    onTap: app.closeNav,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Pane / Thread list` for folder [folderId], or the results for [query].
class _ThreadList extends StatelessWidget {
  const _ThreadList({this.folderId, this.query});

  final String? folderId, query;

  @override
  Widget build(BuildContext context) {
    final app = MailApp.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.controller.doc,
        app.overlay,
        app.mailbox,
      ]),
      builder: (context, _) {
        final (rows, title, caption) = switch ((folderId, query)) {
          (final f?, _) => (
            app.mailbox.inFolder(f),
            folders[f]?.name ?? f,
            '${app.mailbox.inFolder(f).length} conversations · '
                '${app.mailbox.unread(f)} unread',
          ),
          (_, final q) => (
            app.mailbox.search(q!),
            'Search',
            '${app.mailbox.search(q).length} results for “$q”',
          ),
        };
        // Rows show the selection only beside the reading pane.
        final beside =
            screenTypeOf(context) == ScreenType.desktop || app.overlay.value;
        final shown = app._shows(app.windows.detail);
        return Paper(
          color: T.surfaceList,
          child: DecoratedBox(
            decoration: rightHairline,
            position: DecorationPosition.foreground,
            child: ListView(
              padding: const EdgeInsets.symmetric(
                vertical: T.space24,
                horizontal: T.space12,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    T.space12,
                    0,
                    T.space12,
                    T.space16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: T.space2,
                    children: [
                      Text(
                        title,
                        style: MailText.serifTitle22.copyWith(
                          color: T.textPrimary,
                        ),
                      ),
                      Text(
                        caption,
                        style: MailText.sansCaption13.copyWith(
                          color: T.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final (id, t) in rows) ...[
                  const SizedBox(height: T.space4),
                  ThreadRow(
                    sender: t.sender,
                    time: t.time,
                    subject: t.subject,
                    preview: t.preview,
                    unread: t.unread,
                    selected: beside && shown == thread(id),
                    onTap: () => app.openThread(id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The reading surface of the thread and compose panes: desktop pads it
/// `[40,56,32,56]`; tablet and mobile pad 32 and lead with a Back link.
class _ReadingPane extends StatelessWidget {
  const _ReadingPane({required this.gap, required this.children});

  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final app = MailApp.of(context);
    final desktop = screenTypeOf(context) == ScreenType.desktop;
    final listFolder = app.listFolder;
    final back = listFolder == null
        ? 'Search'
        : folders[listFolder]?.name ?? listFolder;
    return Paper(
      color: T.surfaceReading,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: desktop
                    ? const EdgeInsets.fromLTRB(
                        T.space56,
                        T.space40,
                        T.space56,
                        T.space32,
                      )
                    : const EdgeInsets.all(T.space32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    if (!desktop) BackLink(label: back, onTap: app.closeDetail),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Pane / Thread` for thread [id].
class _ThreadPane extends StatelessWidget {
  const _ThreadPane(this.id);

  final String id;

  @override
  Widget build(BuildContext context) {
    final t = MailApp.of(context).mailbox.threads[id];
    if (t == null) return Center(child: Text('Missing thread $id'));
    final initials = t.sender.split(' ').map((w) => w[0]).take(2).join();
    return _ReadingPane(
      gap: T.space24,
      children: [
        Text(
          t.subject,
          style: MailText.serifDisplay32.copyWith(color: T.textPrimary),
        ),
        Container(
          padding: const EdgeInsets.only(bottom: T.space20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: T.borderHairline)),
          ),
          child: Row(
            spacing: T.space12,
            children: [
              Avatar(initials),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.sender,
                      style: MailText.sansLabelStrong15.copyWith(
                        color: T.textPrimary,
                      ),
                    ),
                    Text(
                      'to you',
                      style: MailText.sansCaption13.copyWith(
                        color: T.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                t.sent,
                style: MailText.sansCaption13.copyWith(color: T.textMuted),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: T.readingBodyMaxWidth),
            child: Text(
              t.body,
              style: MailText.sansBody16.copyWith(color: T.textPrimary),
            ),
          ),
        ),
        const Spacer(),
        ReplyBar('Reply to ${t.sender.split(' ').first}…'),
      ],
    );
  }
}

/// `Pane / Compose`, seeded with the design's reply draft.
class _ComposePane extends StatefulWidget {
  const _ComposePane();

  @override
  State<_ComposePane> createState() => _ComposePaneState();
}

class _ComposePaneState extends State<_ComposePane> {
  final to = TextEditingController(text: 'maya@okafor.dev');
  final subject = TextEditingController(text: 'Re: Lunch on Friday?');
  final body = TextEditingController(
    text:
        'Hi Maya,\n\nNoon on Friday works for me. See you at Rua Augusta.'
        '\n\nGabriel',
  );

  @override
  void dispose() {
    to.dispose();
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ReadingPane(
    gap: T.space16,
    children: [
      Text(
        'New message',
        style: MailText.serifDisplay32.copyWith(color: T.textPrimary),
      ),
      ComposeField(label: 'To', value: to),
      ComposeField(label: 'Subject', value: subject),
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: T.readingBodyMaxWidth),
          child: TextField(
            controller: body,
            maxLines: null,
            style: MailText.sansBody16.copyWith(color: T.textPrimary),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ),
      const Spacer(),
      Align(
        alignment: Alignment.centerRight,
        // Needs a recipient.
        child: ListenableBuilder(
          listenable: to,
          builder: (context, _) => PrimaryButton(
            glyph: MailGlyph.send,
            semanticLabel: 'Send',
            label: 'Send',
            hug: true,
            onTap: to.text.trim().isEmpty
                ? null
                : () => MailApp.of(context).send(
                    context,
                    to: to.text.trim(),
                    subject: subject.text.trim(),
                    body: body.text,
                  ),
          ),
        ),
      ),
    ],
  );
}
