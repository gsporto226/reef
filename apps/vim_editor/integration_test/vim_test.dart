import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:vim_editor/main.dart';
import 'package:vim_editor/vim.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Vim> boot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final vim = Vim(ProviderContainer());
    addTearDown(vim.container.dispose);
    await tester.pumpWidget(VimApp(vim));
    await tester.pumpAndSettle();
    return vim;
  }

  const specials = {
    '<Esc>': LogicalKeyboardKey.escape,
    '<CR>': LogicalKeyboardKey.enter,
    '<BS>': LogicalKeyboardKey.backspace,
  };

  /// Types [keys] as real key events; `<C-x>` holds Control.
  Future<void> keys(WidgetTester tester, String keys) async {
    for (final m in RegExp(r'<[^>]+>|.').allMatches(keys)) {
      final t = m[0]!;
      if (specials[t] case final key?) {
        await tester.sendKeyEvent(key);
      } else if (t.startsWith('<C-')) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey(t.codeUnitAt(3)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      } else {
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyA, // the character carries the meaning
          character: t,
          physicalKey: PhysicalKeyboardKey.keyA,
        );
      }
    }
    await tester.pumpAndSettle();
  }

  String textOf(WindowId w) => find
      .byKey(ValueKey('text:${w.value}'))
      .evaluate()
      .map((e) => (e.widget as Text).textSpan!.toPlainText())
      .single;

  List<WindowId> treeWindows(Vim vim) =>
      vim.doc.tabs[vim.activeTab]!.root?.windowIds.toList() ?? [];

  testWidgets('1. :vsplit shows one buffer twice, live', (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':vsplit<CR>');
    final [left, right] = treeWindows(vim);
    expect(vim.bufferOf(left), vim.bufferOf(right));
    await keys(tester, 'iX<Esc>');
    expect(textOf(left), startsWith('Xalpha'));
    expect(textOf(right), startsWith('Xalpha'));
  });

  testWidgets('2. :split copies the window history', (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':e b.txt<CR>:split<CR>');
    final original = treeWindows(vim).first;
    final copy = vim.activeWindow!;
    expect(copy, isNot(original));
    await keys(tester, '<C-o>');
    expect(vim.bufferOf(copy), fileBuffer('a.txt'));
    await keys(tester, '<C-w>k<C-o>');
    expect(vim.activeWindow, original);
    expect(vim.bufferOf(original), fileBuffer('a.txt'));
  });

  testWidgets('3. u undoes splits and edits on one timeline',
      (tester) async {
    final vim = await boot(tester);
    await keys(tester, 'x:vsplit<CR>');
    expect(treeWindows(vim), hasLength(2));
    await keys(tester, 'u');
    expect(treeWindows(vim), hasLength(1));
    await keys(tester, 'u');
    expect(textOf(vim.activeWindow!), startsWith('alpha'));
    await keys(tester, '<C-r><C-r>');
    expect(treeWindows(vim), hasLength(2));
    expect(textOf(vim.activeWindow!), startsWith('lpha'));
  });

  testWidgets('4. :q on the last window leaves the tab empty',
      (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':tabnew b.txt<CR>');
    final second = vim.activeTab;
    await keys(tester, ':q<CR>');
    expect(vim.activeTab, second);
    expect(vim.doc.tabs[second]!.root, isNull);
    await keys(tester, ':tabn<CR>');
    expect(vim.activeTab, isNot(second));
    await keys(tester, ':tabn<CR>');
    expect(vim.activeTab, second);
  });

  testWidgets('5. :e on a buffer open elsewhere reuses it', (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':vsplit<CR>:e b.txt<CR>');
    final right = vim.activeWindow!;
    await keys(tester, '<C-w>h');
    final left = vim.activeWindow!;
    await keys(tester, ':e b.txt<CR>');
    expect(vim.activeWindow, right);
    expect(vim.bufferOf(left), fileBuffer('a.txt'));
  });

  testWidgets('o + typing is one undo step', (tester) async {
    final vim = await boot(tester);
    await keys(tester, 'onew<Esc>');
    expect(textOf(vim.activeWindow!), contains('new'));
    await keys(tester, 'u');
    expect(textOf(vim.activeWindow!), 'alpha\nbeta gamma\ndelta\n');
  });

  testWidgets('<C-w>o keeps only the active window', (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':vsplit<CR>:split<CR><C-w>o');
    expect(treeWindows(vim), [vim.activeWindow]);
  });

  testWidgets(':ls and :b', (tester) async {
    final vim = await boot(tester);
    await keys(tester, ':e b.txt<CR>:e c.txt<CR>:ls<CR>');
    expect(find.text('1 "a.txt"  2 "b.txt"  3 "c.txt"'), findsOneWidget);
    await keys(tester, ':b 1<CR>');
    expect(vim.bufferOf(vim.activeWindow!), fileBuffer('a.txt'));
  });

  testWidgets('u after :e undoes the edit before it, not the :e',
      (tester) async {
    final vim = await boot(tester);
    await keys(tester, 'x:e b.txt<CR>u');
    expect(vim.bufferOf(vim.activeWindow!), fileBuffer('b.txt'));
  });
}
