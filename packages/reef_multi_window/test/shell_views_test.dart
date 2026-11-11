// Drives Flutter's experimental windowing API through flutter_test's test
// windowing owner: the flag is switched on in this isolate only.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart' as windowing;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_multi_window/reef_multi_window.dart';

const _s1 = ShellId.manual('s1');
const _s2 = ShellId.manual('s2');
const _t1 = TabId.manual('t1');
const _t2 = TabId.manual('t2');
const _w1 = WindowId.manual('w1');
const _w2 = WindowId.manual('w2');
const _w3 = WindowId.manual('w3');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: BufferId.manual(buffer)));

/// Shell `s1` shows buffer A. Shell `s2` shows B beside A.
WindowingDoc _doc() => WindowingDoc(
  shells: {
    _s1: ShellState(tabIds: [_t1], activeTabId: _t1),
    _s2: ShellState(tabIds: [_t2], activeTabId: _t2),
  },
  tabs: {
    _t1: const TabState(activeWindowId: _w1, root: WindowLeaf(_w1)),
    _t2: TabState(
      activeWindowId: _w2,
      root: WindowBranch(
        axis: Axis.horizontal,
        ratios: [0.5, 0.5],
        children: const [WindowLeaf(_w2), WindowLeaf(_w3)],
      ),
    ),
  },
  windows: {_w1: _shows('A'), _w2: _shows('B'), _w3: _shows('A')},
  focusedShellId: _s1,
);

class _App {
  _App(this.controller, this.platform, this.delegate);

  final WindowingController controller;
  final RealShellPlatform platform;
  final WindowingDelegate delegate;
  final notes = {'A': ValueNotifier('a1'), 'B': ValueNotifier('b1')};
  final contexts = <ShellId, BuildContext>{};
}

Future<_App> _pump(
  WidgetTester tester, {
  Size size = const Size(1000, 600),
}) async {
  final platform = RealShellPlatform(title: 'Reef', size: size);
  final controller = WindowingController(initial: _doc(), platform: platform);
  addTearDown(controller.dispose);
  final app = _App(controller, platform, const WindowingDelegate());
  await tester.pumpWidget(
    wrapWithView: false,
    WindowingRoot(
      controller: controller,
      delegate: app.delegate,
      bufferBuilder: (_, buffer) => ValueListenableBuilder(
        valueListenable: app.notes[buffer.value]!,
        builder: (_, note, _) => Text('${buffer.value}:$note'),
      ),
      child: ShellViews(
        controller: controller,
        platform: platform,
        shellBuilder: (context, shellId) => Directionality(
          key: ValueKey(shellId),
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              app.contexts[shellId] = context;
              return ShellProjection(shellId);
            },
          ),
        ),
      ),
    ),
  );
  return app;
}

Finder _in(ShellId shell, Finder finder) =>
    find.descendant(of: find.byKey(ValueKey(shell)), matching: finder);

/// Switches the windowing flag on between the two windowing owners the
/// binding sets up: after the default one (with the flag on, on Windows, it
/// FFI-initializes Win32 and fails inside flutter_tester) and before
/// flutter_test registers its test windowing owner. `overrideHttpClient` is
/// the one hook the binding reads in between.
class _WindowingTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient {
    isWindowingEnabled = true;
    return super.overrideHttpClient;
  }
}

void main() {
  _WindowingTestBinding();

  group('windowing on', () {
    late _RecordingOwner owner;
    setUp(() {
      isWindowingEnabled = true;
      final binding = WidgetsBinding.instance;
      final inner = binding.windowingOwner;
      addTearDown(() => binding.windowingOwner = inner);
      binding.windowingOwner = owner = _RecordingOwner(inner);
    });

    windowing.WindowController windowOf(_App app, ShellId shell) =>
        windowing.WindowScope.of(app.contexts[shell]!)
            as windowing.WindowController;

    void requestClose(_App app, ShellId shell) {
      final window = windowOf(app, shell);
      owner.delegates[window]!.onWindowCloseRequested(window);
    }

    testWidgets('a native close request on one of several shells closes it '
        'in the doc and its view goes away', (tester) async {
      final app = await _pump(tester);
      final window = windowOf(app, _s2);
      requestClose(app, _s2);
      await tester.pump();
      expect(app.controller.doc.value.shells.keys, [_s1]);
      expect(find.byType(View), findsOneWidget);
      expect(window.isDestroyed, isTrue);
    });

    testWidgets('a vetoed native close request keeps the doc and the view, '
        'and publishes the veto', (tester) async {
      final app = await _pump(tester);
      app.controller.interceptor = (doc, command) => command is CloseShell
          ? const CommandDecision.veto(UndoLabel('Unsaved'))
          : const CommandDecision.approve();
      final before = app.controller.doc.value;
      final window = windowOf(app, _s2);
      requestClose(app, _s2);
      await tester.pump();
      expect(app.controller.doc.value, same(before));
      expect(
        app.controller.vetoes.value!.command,
        isA<CloseShell>().having((c) => c.shellId, 'shellId', _s2),
      );
      expect(find.byType(View), findsNWidgets(2));
      expect(window.isDestroyed, isFalse);
    });

    testWidgets('a native close request on the last shell destroys the real '
        'shell and leaves the doc alone', (tester) async {
      final app = await _pump(tester);
      app.controller.closeShell(_s2);
      await tester.pump();
      final before = app.controller.doc.value;
      final window = windowOf(app, _s1);
      requestClose(app, _s1);
      await tester.pump();
      expect(app.controller.doc.value, same(before));
      expect(window.isDestroyed, isTrue);
      expect(find.byType(View), findsNothing);
    });

    testWidgets('activating a real shell focuses it in the doc', (
      tester,
    ) async {
      final app = await _pump(tester);
      expect(app.controller.doc.value.focusedShellId, _s1);
      windowOf(app, _s2).activate();
      expect(app.controller.doc.value.focusedShellId, _s2);
      windowOf(app, _s1).activate();
      expect(app.controller.doc.value.focusedShellId, _s1);
    });

    testWidgets('a doc with two shells mounts two views, each showing its '
        'own buffers', (tester) async {
      final app = await _pump(tester);
      expect(app.platform.isSupported, isTrue);
      expect(app.controller.capabilities.canPopOut, isTrue);
      expect(find.byType(View), findsNWidgets(2));
      expect(find.byType(View), findsNWidgets(2));
      expect(_in(_s1, find.text('A:a1')), findsOneWidget);
      expect(_in(_s1, find.text('B:b1')), findsNothing);
      expect(_in(_s2, find.text('B:b1')), findsOneWidget);
      expect(_in(_s2, find.text('A:a1')), findsOneWidget);
    });

    testWidgets('new shells take the title and size of the platform '
        'configuration', (tester) async {
      final app = await _pump(tester, size: const Size(900, 500));
      final context = app.contexts[_s1]!;
      expect(windowing.WindowScope.titleOf(context), 'Reef');
      expect(MediaQuery.sizeOf(context), const Size(900, 500));
    });

    testWidgets('openShell adds a view; closing the shell removes it', (
      tester,
    ) async {
      final app = await _pump(tester);
      final opened = await app.controller.openShell();
      final id = (opened as Ok<ShellError, ShellId>).value;
      await tester.pump();
      expect(find.byType(View), findsNWidgets(3));
      expect(find.byKey(ValueKey(id)), findsOneWidget);

      app.controller.closeShell(id);
      await tester.pump();
      expect(find.byType(View), findsNWidgets(2));
      expect(find.byKey(ValueKey(id)), findsNothing);
    });

    testWidgets('the same buffer in two shells stays in sync after an edit', (
      tester,
    ) async {
      final app = await _pump(tester);
      app.notes['A']!.value = 'a2';
      await tester.pump();
      expect(_in(_s1, find.text('A:a2')), findsOneWidget);
      expect(_in(_s2, find.text('A:a2')), findsOneWidget);
    });

    testWidgets('units in every view find the same controller and delegate', (
      tester,
    ) async {
      final app = await _pump(tester);
      for (final shell in [_s1, _s2]) {
        final context = app.contexts[shell]!;
        expect(WindowingScope.of(context).controller, same(app.controller));
        expect(WindowingDelegateScope.of(context), same(app.delegate));
      }
    });

    testWidgets('ShellProjection picks the projection by its own view size', (
      tester,
    ) async {
      final app = await _pump(tester);
      app.platform.size = const Size(400, 600);
      final id = (await app.controller.openShell() as Ok).value as ShellId;
      await tester.pump();
      expect(_in(_s1, find.byType(DesktopProjection)), findsOneWidget);
      expect(_in(id, find.byType(TabbedProjection)), findsOneWidget);
    });

    testWidgets('a restored shell whose real shell fails to open leaves the '
        'doc; the other shell gets its view', (tester) async {
      owner.failing = {1};
      final app = await _pump(tester);
      await tester.pump();
      expect(app.controller.doc.value.shells.keys, [_s1]);
      expect(find.byType(View), findsOneWidget);
      expect(_in(_s1, find.text('A:a1')), findsOneWidget);
    });

    testWidgets('when every restored shell fails to open, the last shell '
        'stays in the doc', (tester) async {
      owner.failing = {0, 1};
      final app = await _pump(tester);
      await tester.pump();
      expect(app.controller.doc.value.shells.keys, [_s2]);
      expect(find.byType(View), findsNothing);
    });

    testWidgets('a failed window creation returns a platformFailure', (
      tester,
    ) async {
      final binding = WidgetsBinding.instance;
      final owner = binding.windowingOwner;
      addTearDown(() => binding.windowingOwner = owner);
      binding.windowingOwner = _BrokenOwner();
      final result = await RealShellPlatform().open(_s1);
      expect(
        (result as Err<ShellError, Object>).value.kind,
        ShellErrorKind.platformFailure,
      );
    });
  });

  group('windowing off', () {
    setUp(() => isWindowingEnabled = false);
    tearDown(() => isWindowingEnabled = true);

    testWidgets('ShellViews renders the focused shell inline and canPopOut is '
        'false', (tester) async {
      final app = await _pump(tester);
      expect(app.platform.isSupported, isFalse);
      expect(app.controller.capabilities.canPopOut, isFalse);
      expect(find.byType(View), findsOneWidget);
      expect(_in(_s1, find.text('A:a1')), findsOneWidget);
      expect(find.byKey(const ValueKey(_s2)), findsNothing);

      app.controller.activateShell(_s2);
      await tester.pump();
      expect(_in(_s2, find.text('B:b1')), findsOneWidget);
      expect(find.byKey(const ValueKey(_s1)), findsNothing);

      app.controller.closeShell(_s2);
      await tester.pump();
      expect(_in(_s1, find.text('A:a1')), findsOneWidget);
    });
  });
}

class _BrokenOwner implements windowing.WindowingOwner {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('no windows here');
}

/// flutter_test's owner, recording each window's delegate: nothing in the
/// test owner raises a native close request, so tests raise it themselves.
/// Window creations whose index is in [failing] throw.
class _RecordingOwner implements windowing.WindowingOwner {
  _RecordingOwner(this.inner);

  final windowing.WindowingOwner inner;
  final delegates =
      <windowing.WindowController, windowing.WindowControllerDelegate>{};
  Set<int> failing = {};
  var _created = 0;

  @override
  windowing.WindowController createWindowController({
    required windowing.WindowControllerDelegate delegate,
    Size? size,
    BoxConstraints? constraints,
    required bool resizable,
    String? title,
  }) {
    if (failing.contains(_created++)) throw UnsupportedError('no window');
    final window = inner.createWindowController(
      delegate: delegate,
      size: size,
      constraints: constraints,
      resizable: resizable,
      title: title,
    );
    delegates[window] = delegate;
    return window;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used');
}
