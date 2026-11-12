import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

const s1 = ShellId.manual('s1');
const s2 = ShellId.manual('s2');
const t1 = TabId.manual('t1');
const t2 = TabId.manual('t2');
const left = WindowId.manual('left');
const right = WindowId.manual('right');
const other = WindowId.manual('other');
const list = BufferId.manual('/tasks:');
const edit42 = BufferId.manual('/tasks/*/edit:42');
const edit43 = BufferId.manual('/tasks/*/edit:43');
const scratch = BufferId.manual('scratch:1');

final links = LinkTree<Object>([
  Link<String>('tasks').build(() => 'tasks'),
  Link<(int, String?)>('tasks')
      .field((r) => r.$1)
      .literal('edit')
      .query<String?>('q', (r) => r.$2, fallback: null)
      .build((id, q) => (id, q)),
  Link<List<String>>('').rest((path) => path).build((path) => path),
]);

/// Records what the adapter reports and injects route notifications, as a
/// browser would.
class FakeRouteInformationProvider extends RouteInformationProvider
    with ChangeNotifier {
  FakeRouteInformationProvider(String initial)
    : _value = RouteInformation(uri: Uri.parse(initial));

  RouteInformation _value;
  final reports = <(String, RouteInformationReportingType)>[];

  @override
  RouteInformation get value => _value;

  /// A route notification: browser back, forward or a typed URL.
  void browse(String uri, {Object? state}) {
    _value = RouteInformation(uri: Uri.parse(uri), state: state);
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    _value = routeInformation;
    reports.add((routeInformation.uri.toString(), type));
  }
}

const push = RouteInformationReportingType.navigate;
const replace = RouteInformationReportingType.neglect;

WindowState shows(BufferId buffer) =>
    WindowState(history: BufferHistory(current: HistoryEntry(buffer)));

/// s1 holds t1: left (the list) beside right (42); [focused] is active.
/// With [second], s2 holds t2: other (43).
WindowingDoc doc({
  WindowId focused = left,
  bool second = false,
  ShellId focusedShell = s1,
}) => WindowingDoc(
  shells: {
    s1: ShellState(tabIds: [t1], activeTabId: t1),
    if (second) s2: ShellState(tabIds: [t2], activeTabId: t2),
  },
  tabs: {
    t1: TabState(
      root: WindowBranch(
        axis: Axis.horizontal,
        children: const [WindowLeaf(left), WindowLeaf(right)],
        ratios: const [0.5, 0.5],
      ),
      activeWindowId: focused,
    ),
    if (second) t2: TabState(root: const WindowLeaf(other), activeWindowId: other),
  },
  windows: {
    left: shows(list),
    right: shows(edit42),
    if (second) other: shows(edit43),
  },
  focusedShellId: focusedShell,
);

/// Opens links only after a delay, as a late async openLink would.
class SlowController extends WindowingController {
  SlowController({super.initial});

  @override
  Future<void> openLink(
    BufferId buffer, {
    Map<String, String> arguments = const {},
    bool newShell = false,
    LinkVerb verb = LinkVerb.go,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.openLink(
      buffer,
      arguments: arguments,
      newShell: newShell,
      verb: verb,
    );
  }
}

void main() {
  group('reportType', () {
    test('the focused window pushing its previous buffer is a push', () {
      final before = doc(focused: right);
      final after = PushBuffer(right, edit43).apply(before);
      expect(reportType(before, after), push);
    });

    test('focus following a push into another window is still a push', () {
      final before = doc();
      final after = PushBuffer(right, edit43)
          .apply(const ActivateWindow(right).apply(before));
      expect(reportType(before, after), push);
    });

    test('a focus switch, a replace or a pop rewrites the current entry', () {
      final before = doc(focused: right);
      expect(
        reportType(before, const ActivateWindow(left).apply(before)),
        replace,
      );
      expect(
        reportType(before, ReplaceBuffer(right, edit43).apply(before)),
        replace,
      );
      final pushed = PushBuffer(right, edit43).apply(before);
      expect(reportType(pushed, PopBuffer(right).apply(pushed)), replace);
    });

    test('a focused window that did not exist before replaces', () {
      expect(
        reportType(doc(), doc(second: true, focusedShell: s2)),
        replace,
      );
    });
  });

  group('WindowingLinkSync', () {
    late WindowingController controller;
    late FakeRouteInformationProvider provider;

    Future<void> mount(
      WidgetTester tester,
      WindowingDoc initial, {
      String route = '/',
      bool slow = false,
      bool entryState = false,
    }) async {
      controller = slow
          ? SlowController(initial: () => initial)
          : WindowingController(initial: () => initial);
      provider = FakeRouteInformationProvider(route);
      await tester.pumpWidget(
        WindowingRoot(
          controller: controller,
          bufferBuilder: (_, _) => const SizedBox(),
          child: WindowingLinkSync(
            tree: links,
            routeInformationProvider: provider,
            entryState: entryState,
            child: const SizedBox(),
          ),
        ),
      );
    }

    String? focusedPath() {
      final d = controller.doc.value;
      final tab = d.tabs[d.shells[d.focusedShellId]!.activeTabId]!;
      final entry = d.windows[tab.activeWindowId]!.history.current;
      return links.uriOfBuffer(entry.buffer, entry.arguments)?.toString();
    }

    testWidgets('example 1: the initial route opens its buffer and is not '
        'echoed back', (tester) async {
      await mount(tester, WindowingDoc.initial(), route: '/tasks/42/edit');

      expect(
        controller.doc.value.windows.values.single.history.current.buffer,
        edit42,
      );
      expect(provider.value.uri.toString(), '/tasks/42/edit');
      expect(provider.reports, isEmpty);
    });

    testWidgets('an unknown initial route opens the not-found route with '
        'the unmatched path, and keeps the URL', (tester) async {
      await mount(tester, doc(focused: right), route: '/nope/a');
      expect(focusedPath(), '/nope/a');
      expect(
        links.routeOfBuffer(controller.doc.value.windows[right]!.history
            .current.buffer),
        ['nope', 'a'],
      );
      expect(provider.reports, isEmpty);
    });

    testWidgets('URL write-back keeps the current entry query',
        (tester) async {
      await mount(tester, doc(), route: '/tasks');
      controller.dispatch(PushBuffer(left, edit42, arguments: {'q': 'x'}));
      expect(provider.reports, [('/tasks/42/edit?q=x', push)]);
      controller.dispatch(const PopBuffer(left));
      controller.dispatch(const NavigateForward(left));
      expect(provider.reports.last, ('/tasks/42/edit?q=x', push));
    });

    testWidgets('example 2: one window pushes an entry; browser back steps '
        'the window back without a new entry', (tester) async {
      await mount(tester, doc(), route: '/tasks');
      expect(provider.reports, isEmpty);

      controller.dispatch(PushBuffer(left, edit42));
      expect(provider.reports, [('/tasks/42/edit', push)]);

      provider.browse('/tasks');
      expect(focusedPath(), '/tasks');
      expect(provider.reports, hasLength(1));
    });

    testWidgets('example 3: two windows; a push, a focus switch, then '
        'browser back to the earlier buffer', (tester) async {
      await mount(tester, doc(), route: '/tasks');

      controller.dispatchAll([
        const ActivateWindow(right),
        PushBuffer(right, edit43),
      ]);
      expect(provider.reports, [('/tasks/43/edit', push)]);

      controller.dispatch(const ActivateWindow(left));
      expect(provider.reports.last, ('/tasks', replace));

      provider.browse('/tasks/42/edit');
      expect(focusedPath(), '/tasks/42/edit');
      expect(
        controller.doc.value.windows[right]!.history,
        BufferHistory(
          current: HistoryEntry(edit43),
          back: [HistoryEntry(edit42)],
        ),
        reason: "the right window's own window history is untouched",
      );
      expect(provider.reports, hasLength(2));
    });

    testWidgets('a link opened late is still not echoed back', (tester) async {
      await mount(tester, WindowingDoc.initial(), route: '/tasks/42/edit',
          slow: true);
      await tester.pump(const Duration(milliseconds: 10));
      expect(focusedPath(), '/tasks/42/edit');
      expect(provider.reports, isEmpty);

      controller.dispatch(
          PushBuffer(controller.doc.value.windows.keys.single, edit43));
      expect(provider.reports, [('/tasks/43/edit', push)]);
    });

    testWidgets('an empty tab reports nothing', (tester) async {
      await mount(tester, WindowingDoc.initial(), route: '/unknown');
      expect(provider.reports, isEmpty);
    });

    testWidgets('defaults to the platform provider', (tester) async {
      controller = WindowingController(initial: () => doc());
      await tester.pumpWidget(
        WindowingRoot(
          controller: controller,
          bufferBuilder: (_, _) => const SizedBox(),
          child: WindowingLinkSync(
            tree: links,
            child: const SizedBox(key: Key('page')),
          ),
        ),
      );
      controller.dispatch(PushBuffer(left, edit42));
      expect(find.byKey(const Key('page')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a focused buffer without a path reports nothing', (
      tester,
    ) async {
      await mount(tester, doc(focused: right), route: '/tasks/42/edit');
      controller.dispatch(PushBuffer(right, scratch));
      expect(provider.reports, isEmpty);
    });

    testWidgets("with several shells the URL follows the focused shell's "
        'focused buffer', (tester) async {
      await mount(tester, doc(second: true), route: '/tasks');
      controller.dispatch(const ActivateShell(s2));
      expect(provider.reports, [('/tasks/43/edit', replace)]);
    });

    testWidgets('keeps its provider on rebuild and refuses a new one', (
      tester,
    ) async {
      await mount(tester, doc(), route: '/tasks');
      Widget app(RouteInformationProvider p) => WindowingRoot(
        controller: controller,
        bufferBuilder: (_, _) => const SizedBox(),
        child: WindowingLinkSync(
          tree: links,
          routeInformationProvider: p,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(app(provider));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(FakeRouteInformationProvider('/')));
      expect(tester.takeException(), isAssertionError);
    });

        testWidgets('stops listening when removed', (tester) async {
      await mount(tester, doc(), route: '/tasks');
      await tester.pumpWidget(const SizedBox());
      controller.dispatch(PushBuffer(left, edit42));
      provider.browse('/tasks/43/edit');
      expect(provider.reports, isEmpty);
    });
    group('entry state (D2)', () {
      String idOf(WindowId w) =>
          controller.doc.value.windows[w]!.history.current.id.id;

      testWidgets('reports carry the current entry id', (tester) async {
        await mount(tester, doc(), route: '/tasks', entryState: true);
        controller.dispatch(PushBuffer(left, edit42));
        expect(provider.value.state, idOf(left));
      });

      testWidgets('back and forward move the owning window to the entry and '
          'focus it', (tester) async {
        await mount(tester, doc(second: true), route: '/tasks',
            entryState: true);
        controller.dispatch(PushBuffer(left, edit42));
        final first = controller.doc.value.windows[left]!.history.back.single;
        controller.dispatch(PushBuffer(left, edit43));
        final second = idOf(left);
        controller.dispatch(const ActivateShell(s2));
        final reports = provider.reports.length;

        provider.browse('/tasks', state: first.id.id);
        expect(controller.doc.value.focusedShellId, s1);
        expect(focusedPath(), '/tasks');
        expect(controller.doc.value.windows[left]!.history.forward,
            hasLength(2));
        expect(controller.doc.value.windows[other]!.history.current.buffer,
            edit43, reason: 'no window opened the URL as a link');

        provider.browse('/tasks/43/edit', state: second);
        expect(idOf(left), second);
        expect(controller.doc.value.windows[left]!.history.back, hasLength(2));
        expect(provider.reports, hasLength(reports));
      });

      testWidgets('a guard redirecting mid-move leaves the URL on the final '
          'entry', (tester) async {
        await mount(tester, doc(), route: '/tasks', entryState: true);
        controller.dispatch(PushBuffer(left, edit42));
        final first = controller.doc.value.windows[left]!.history.back.single;
        controller.interceptor = (_, c) => c is PopBuffer
            ? CommandDecision.replace(CommandSequence(
                [c, ReplaceBuffer(c.windowId, edit43)]))
            : const CommandDecision.approve();

        provider.browse('/tasks', state: first.id.id);
        expect(focusedPath(), '/tasks/43/edit');
        expect(provider.value.uri.toString(), '/tasks/43/edit');
        expect(provider.value.state, idOf(left));
        expect(provider.reports.last, ('/tasks/43/edit', replace));
      });

      testWidgets('a vanished entry opens the URL as a link', (tester) async {
        await mount(tester, doc(), route: '/tasks', entryState: true);
        provider.browse('/tasks/43/edit', state: 'gone');
        expect(focusedPath(), '/tasks/43/edit');
      });

      testWidgets('without entry state the id is ignored and no state is '
          'reported', (tester) async {
        await mount(tester, doc(), route: '/tasks');
        controller.dispatch(PushBuffer(left, edit42));
        final id = controller.doc.value.windows[left]!.history.back.single.id;
        expect(provider.value.state, isNull);
        controller.dispatch(PushBuffer(left, edit43));
        provider.browse('/tasks', state: id.id);
        expect(controller.doc.value.windows[left]!.history.forward, isEmpty,
            reason: 'opened as a link, history not moved back');
      });
    });
  });
}