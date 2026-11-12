import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import 'link_nesting_test.dart' show tree;
import 'nesting_routes.dart';

const project = ProjectRoute('p1', page: 3);
const task = TaskRoute(project, 't9');

void main() {
  late WindowingController controller;
  late LinkNavigator<AppRoute> nav;

  setUp(() {
    controller = WindowingController(
      initial: () {
        final d = WindowingDoc.initial();
        return NewTab(
          shellId: d.focusedShellId,
          tabId: const TabId.manual('t'),
          buffer: (const WindowId.manual('w'), const BufferId.manual('home:')),
        ).apply(d);
      },
    );
    nav = LinkNavigator(tree, controller);
  });
  tearDown(() => controller.dispose());

  WindowingDoc doc() => controller.doc.value;
  HistoryEntry current() => doc().windows[doc().activeWindowId]!.history.current;
  HistoryEntry entryOf(AppRoute r) {
    final (:buffer, :arguments) = tree.linkOf(r);
    return HistoryEntry(buffer, arguments: arguments);
  }

  test('up is the parent route, with its query', () {
    expect(tree.parentOf(task), project);
    expect(tree.parentOf(const FileEditRoute(FilesRoute(['a']))),
        const FilesRoute(['a']));
    expect(tree.parentOf(project), isNull);
  });

  test('push and replace give the doc of PushBuffer and ReplaceBuffer', () {
    final w = doc().activeWindowId!;
    final (:buffer, :arguments) = tree.linkOf(task);
    final pushed = PushBuffer(w, buffer, arguments: arguments).apply(doc());
    nav.push(task);
    expect(current(), pushed.windows[w]!.history.current);
    expect(doc().windows[w]!.history.back, pushed.windows[w]!.history.back);

    nav.replace(project);
    expect(current(), entryOf(project));
    expect(doc().windows[w]!.history.back, pushed.windows[w]!.history.back);
  });

  test('up pushes the parent route', () {
    nav.push(task);
    expect(nav.up(), isTrue);
    expect(current(), entryOf(project));
    expect(doc().windows[doc().activeWindowId]!.history.back.last,
        entryOf(task));
    expect(nav.up(), isFalse);
  });

  test('go, new tab and split open through windowing', () async {
    await nav.go(task);
    expect(current(), entryOf(task));
    final tabs = doc().tabs.length;
    nav.openInNewTab(project);
    expect(doc().tabs, hasLength(tabs + 1));
    expect(current(), entryOf(project));
    nav.openInSplit(task);
    expect(doc().activeTab.root, isA<WindowBranch>());
    expect(current(), entryOf(task));
  });

  test('push with no focused window falls back to go', () {
    final empty = WindowingController();
    addTearDown(empty.dispose);
    LinkNavigator(tree, empty).push(task);
    expect(empty.doc.value.windows.values.single.history.current,
        entryOf(task));
  });

  testWidgets('widgets reach the navigator through the scope, and routes '
      'navigate through the mixin', (tester) async {
    await tester.pumpWidget(LinkScope<AppRoute>(
      navigator: nav,
      child: Builder(builder: (context) {
        expect(LinkNavigator.of<AppRoute>(context), same(nav));
        task.push(context);
        return const SizedBox();
      }),
    ));
    expect(current(), entryOf(task));
  });
}
