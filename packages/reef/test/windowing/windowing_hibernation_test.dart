import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _key = BufferId.manual('windowing:');

void main() {
  late InMemoryHibernationStore store;

  setUp(() => store = InMemoryHibernationStore());

  WindowingController controller({
    WindowingDoc? initial,
    UndoController? undo,
  }) {
    final c = WindowingController(store: store, initial: initial, undo: undo);
    addTearDown(c.dispose);
    return c;
  }

  test('a second controller on the same store restores an equal doc', () {
    final undo = UndoController();
    final first = controller(undo: undo);
    final tab = first.newTab(buffer: const BufferId.manual('a'));
    final a = first.doc.value.tabs[tab]!.activeWindowId!;
    final b = first.splitWindow(a, axis: Axis.vertical);
    first.resizeWindow(b, const [0.3, 0.7]);
    final c = first.splitWindow(
      b,
      axis: Axis.horizontal,
      buffer: const BufferId.manual('c'),
    );
    first.floatWindow(c, scope: TabScope(tab));
    first.moveFloating(c, const Rect.fromLTWH(10, 20, 300, 200));
    final d = first.splitWindow(a, axis: Axis.horizontal);
    first.floatWindow(d, scope: WindowScope(c));
    first.pushBuffer(a, const BufferId.manual('a2'));
    first.popBuffer(a);
    first.attachShell();
    first.activateWindow(b);
    first.newTab();
    undo.undo(); // published without dispatch, saved too

    final second = controller();
    expect(second.doc.value, first.doc.value);
    expect(second.doc.value.floating[d]!.scope, WindowScope(c));
    expect(second.doc.value.windows[a]!.history.forward, [
      const BufferId.manual('a2'),
    ]);
  });

  test('the persistence transform shapes the record, not the live doc', () {
    final first = WindowingController(
      store: store,
      persistence: (doc) => WindowingDoc(
        shells: doc.shells,
        tabs: doc.tabs,
        windows: {
          for (final e in doc.windows.entries)
            if (!doc.floating.containsKey(e.key)) e.key: e.value,
        },
        focusedShellId: doc.focusedShellId,
      ),
    );
    addTearDown(first.dispose);
    final tab = first.newTab(buffer: const BufferId.manual('a'));
    final a = first.doc.value.tabs[tab]!.activeWindowId!;
    final b = first.splitWindow(a, axis: Axis.vertical);
    first.floatWindow(b, scope: TabScope(tab));

    expect(first.doc.value.floating.keys, [b]);
    final second = controller();
    expect(second.doc.value.floating, isEmpty);
    expect(second.doc.value.windows.keys, [a]);
  });

  test('extra round-trips through a second controller', () {
    final first = controller();
    expect(first.extra, isNull);
    first.extra = {'projection': 'tabbed'};
    expect(controller().extra, {'projection': 'tabbed'});
  });

  test('the record is plain JSON with a version', () {
    final first = controller();
    first.newTab(buffer: const BufferId.manual('a'));
    final record =
        jsonDecode(jsonEncode(store.load(_key))) as Map<String, dynamic>;
    expect(record['version'], 1);
    store.save(_key, record);
    expect(controller().doc.value, first.doc.value);
  });

  test('a focus-only change is saved', () {
    final first = controller();
    final shell = first.doc.value.focusedShellId;
    first.attachShell();
    first.activateShell(shell);
    expect(controller().doc.value.focusedShellId, shell);
  });

  test('the record wins over initial; a restored controller has no undo', () {
    final first = controller();
    first.newTab();
    final undo = UndoController();
    final second = controller(initial: WindowingDoc.initial(), undo: undo);
    expect(second.doc.value, first.doc.value);
    expect(undo.$canUndo.value, isFalse);
  });

  test('without a record the controller starts from initial', () {
    final initial = WindowingDoc.initial();
    expect(controller(initial: initial).doc.value, initial);
  });

  test('without a store nothing is saved', () {
    final plain = WindowingController();
    addTearDown(plain.dispose);
    plain.newTab();
    plain.discardSavedLayout();
    expect(store.load(_key), isNull);
  });

  test('discardSavedLayout deletes the record', () {
    final first = controller();
    first.newTab();
    first.discardSavedLayout();
    expect(store.load(_key), isNull);
    final initial = WindowingDoc.initial();
    expect(controller(initial: initial).doc.value, initial);
  });

  group('a bad record means no record', () {
    Map<String, dynamic> good() {
      final c = WindowingController(store: store);
      final tab = c.newTab(buffer: const BufferId.manual('a'));
      final w = c.doc.value.tabs[tab]!.activeWindowId!;
      c.splitWindow(w, axis: Axis.horizontal);
      final json =
          jsonDecode(jsonEncode(store.load(_key))) as Map<String, dynamic>;
      c.dispose();
      return json;
    }

    Map<String, dynamic> doc(Map<String, dynamic> r) =>
        r['doc'] as Map<String, dynamic>;
    Map<String, dynamic> firstTab(Map<String, dynamic> r) =>
        (doc(r)['tabs'] as Map<String, dynamic>).values.last
            as Map<String, dynamic>;

    final cases = <String, void Function(Map<String, dynamic>)>{
      'unknown version': (r) => r['version'] = 2,
      'malformed': (r) => r['doc'] = 'nope',
      'unknown focused shell': (r) => doc(r)['focusedShell'] = 'x',
      'shell without tabs': (r) =>
          ((doc(r)['shells'] as Map).values.first as Map)['tabs'] = [],
      'active tab outside the shell': (r) =>
          ((doc(r)['shells'] as Map).values.first as Map)['activeTab'] = 'x',
      'tab in no shell': (r) =>
          (doc(r)['tabs'] as Map)['orphan'] = <String, dynamic>{},
      'tab in two shells': (r) {
        final shells = doc(r)['shells'] as Map;
        final s = shells.values.first as Map;
        shells['s2'] = {'tabs': s['tabs'], 'activeTab': s['activeTab']};
      },
      'tree window missing': (r) => (doc(r)['windows'] as Map).remove(
        (doc(r)['windows'] as Map).keys.first,
      ),
      'window in no tree': (r) => (doc(r)['windows'] as Map)['loose'] = {
        'back': [],
        'current': 'a',
        'forward': [],
      },
      'active window outside the tree': (r) =>
          firstTab(r)['activeWindow'] = 'x',
      'ratios not summing to one': (r) =>
          (firstTab(r)['root'] as Map)['ratios'] = [0.5, 0.6],
      'branch with one child': (r) {
        final root = firstTab(r)['root'] as Map;
        root['children'] = [(root['children'] as List).first];
        root['ratios'] = [1.0];
      },
      'window in a tree and floating': (r) {
        final w = (doc(r)['windows'] as Map).keys.first;
        doc(r)['floating'] = {
          w: {
            'scope': {'shell': (doc(r)['shells'] as Map).keys.first},
            'z': 1,
            'geometry': null,
          },
        };
      },
    };

    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        final record = good();
        value(record);
        store.save(_key, record);
        const buffer = BufferId.manual('a');
        store.save(buffer, {'title': 'kept'});
        record['extra'] = 'stale';
        store.save(_key, record);
        final initial = WindowingDoc.initial();
        final c = controller(initial: initial);
        expect(c.doc.value, initial);
        expect(c.extra, isNull, reason: 'a discarded record yields no extra');
        expect(store.load(_key), isNull);
        expect(store.load(buffer), {'title': 'kept'});
      });
    }
  });

  test('floating scopes in a cycle are invalid', () {
    final shell = ShellId.manual('s');
    final tab = TabId.manual('t');
    final w1 = WindowId.manual('w1');
    final w2 = WindowId.manual('w2');
    WindowingDoc withScope(FloatScope scope) => WindowingDoc(
      shells: {
        shell: ShellState(tabIds: [tab], activeTabId: tab),
      },
      tabs: {tab: const TabState()},
      windows: {
        for (final w in [w1, w2])
          w: WindowState(
            history: BufferHistory(current: const BufferId.manual('b')),
          ),
      },
      focusedShellId: shell,
      floating: {
        w1: FloatingState(scope: WindowScope(w2), zIndex: 1),
        w2: FloatingState(scope: scope, zIndex: 1),
      },
    );
    expect(withScope(TabScope(tab)).isValid, isTrue);
    expect(withScope(WindowScope(w1)).isValid, isFalse);
    expect(withScope(TabScope(TabId.manual('gone'))).isValid, isFalse);
  });

  testWidgets('a restored layout draws its windows', (tester) async {
    final first = controller();
    first.newTab(buffer: const BufferId.manual('restored'));
    final second = controller();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: second,
          bufferBuilder: (_, id) => Text(id.id),
          child: ShellProjection(second.doc.value.focusedShellId),
        ),
      ),
    );
    expect(find.text('restored'), findsOneWidget);
  });
}
