import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';

/// The in-memory file system, seeded at boot.
final fileSystemProvider = Provider<Map<String, String>>((ref) => {
      'a.txt': 'alpha\nbeta gamma\ndelta',
      'b.txt': 'one two\nthree',
      'c.txt': 'see',
    });

final undoProvider = Provider((ref) => UndoController());
final bufferUndoProvider =
    Provider((ref) => BufferUndoHost(ref.watch(undoProvider)));

BufferId fileBuffer(String name) => BufferId.manual('file:$name');
String fileOf(BufferId buffer) => buffer.id.substring('file:'.length);

@immutable
class TextModel {
  const TextModel(this.lines);
  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is TextModel && listEquals(other.lines, lines);
  @override
  int get hashCode => Object.hashAll(lines);
}

class TextViewModel extends ViewModel<TextModel>
    with UndoableModel<TextModel> {
  TextViewModel(super.initialModel);

  void setLines(List<String> lines, {Object? coalesceKey}) =>
      publish(TextModel(lines), coalesceKey: coalesceKey);
}

/// One view model per buffer: every window on a buffer shares it.
final textViewModelProvider =
    Provider.family<TextViewModel, BufferId>((ref, buffer) {
  final text = ref.read(fileSystemProvider)[fileOf(buffer)] ?? '';
  final vm = TextViewModel(TextModel(text.split('\n')))
    ..attachUndo(ref.read(bufferUndoProvider), buffer);
  ref.onDispose(vm.dispose);
  return vm;
});

/// A doc with one shell and one tab showing [buffer].
WindowingDoc startingDoc(BufferId buffer) =>
    WindowingDoc.initial(buffer: buffer);

enum Mode { normal, insert, command }

/// The editor session: modes, the command line, per-window cursors, and the
/// mapping from vim keys to reef intents.
class Vim extends ChangeNotifier {
  Vim(this.container, {WindowingDoc? initial})
      : controller = WindowingController(
          initial: () => initial ?? startingDoc(fileBuffer('a.txt')),
          undo: container.read(undoProvider),
        ) {
    container.read(bufferUndoProvider);
    controller.doc.addListener(_list);
    _list();
  }

  void _list() {
    for (final s in doc.windows.values) {
      final h = s.history;
      for (final b in [...h.back, h.current, ...h.forward]) {
        if (!listed.contains(b.buffer)) listed.add(b.buffer);
      }
    }
  }

  final ProviderContainer container;
  final WindowingController controller;
  UndoController get undo => container.read(undoProvider);

  Mode mode = Mode.normal;
  String commandLine = '';
  String message = '';
  String _pending = '';
  int _insertRun = 0;
  final _cursors = <WindowId, (int, int)>{};

  /// Buffers in the order they were first opened, for `:ls` and `:b`.
  final listed = <BufferId>[];

  WindowingDoc get doc => controller.doc.value;
  ShellState get _shell => doc.shells[doc.focusedShellId]!;
  TabId get activeTab => _shell.activeTabId;
  WindowId? get activeWindow => doc.tabs[activeTab]!.activeWindowId;
  BufferId? bufferOf(WindowId w) => doc.windows[w]?.history.current.buffer;
  TextViewModel vmOf(BufferId b) => container.read(textViewModelProvider(b));

  /// [w]'s cursor, clamped to its buffer's current text.
  (int, int) cursorOf(WindowId w) {
    final lines = vmOf(bufferOf(w)!).model.lines;
    final (r, c) = _cursors[w] ?? (0, 0);
    final row = r.clamp(0, lines.length - 1);
    return (row, c.clamp(0, max(0, lines[row].length - (mode == Mode.insert ? 0 : 1))));
  }

  /// Feeds one key token: a character, or `<Esc>`, `<CR>`, `<BS>`, `<C-x>`.
  void input(String key) {
    switch (mode) {
      case Mode.insert:
        _insert(key);
      case Mode.command:
        _command(key);
      case Mode.normal:
        _normal(key);
    }
    notifyListeners();
  }

  /// Feeds [keys], with `<...>` tokens.
  void feed(String keys) {
    for (final m in RegExp(r'<[^>]+>|.').allMatches(keys)) {
      input(m[0]!);
    }
  }

  void _normal(String key) {
    final seq = _pending + key;
    _pending = '';
    final w = activeWindow;
    if (seq.startsWith('<C-w>') && seq.length > 5) return _windowCommand(seq.substring(5));
    switch (seq) {
      case ':':
        mode = Mode.command;
        commandLine = '';
      case 'g' || 'd' || '<C-w>':
        _pending = seq;
      case 'u':
        undo.undo();
      case '<C-r>':
        undo.redo();
      case '<C-o>' when w != null:
        controller.popBuffer(w);
      case '<C-i>' when w != null:
        controller.navigateForward(w);
      case _ when w != null:
        _edit(w, seq);
    }
  }

  void _edit(WindowId w, String key) {
    final vm = vmOf(bufferOf(w)!);
    final lines = vm.model.lines;
    var (r, c) = cursorOf(w);
    final line = lines[r];
    switch (key) {
      case 'h':
        c--;
      case 'l':
        c++;
      case 'j':
        r++;
      case 'k':
        r--;
      case '0':
        c = 0;
      case r'$':
        c = line.length;
      case 'gg':
        r = 0;
      case 'G':
        r = lines.length - 1;
      case 'w':
        final next = RegExp(r'\s\S').firstMatch(line.substring(min(c, line.length)));
        if (next != null) c += next.start + 1;
      case 'b':
        final prev = RegExp(r'\S+\s*$').firstMatch(line.substring(0, c));
        c = prev?.start ?? 0;
      case 'x' when line.isNotEmpty:
        vm.setLines([...lines]..[r] = line.replaceRange(c, c + 1, ''));
      case 'dd':
        vm.setLines(lines.length == 1 ? [''] : ([...lines]..removeAt(r)));
      case 'i':
        _startInsert();
      case 'a':
        _startInsert();
        c++;
      case 'o':
        _startInsert();
        vm.setLines([...lines]..insert(r + 1, ''), coalesceKey: _insertKey);
        (r, c) = (r + 1, 0);
    }
    _cursors[w] = (r, c);
  }

  Object get _insertKey => (#insert, _insertRun);

  void _startInsert() {
    mode = Mode.insert;
    _insertRun++;
  }

  void _insert(String key) {
    final w = activeWindow;
    if (key == '<Esc>') {
      mode = Mode.normal;
      undo.sealCoalescing();
      if (w != null) _cursors[w] = (cursorOf(w).$1, cursorOf(w).$2 - 1);
      return;
    }
    if (w == null) return;
    final vm = vmOf(bufferOf(w)!);
    final lines = [...vm.model.lines];
    final (r, c) = cursorOf(w);
    switch (key) {
      case '<CR>':
        lines
          ..insert(r + 1, lines[r].substring(c))
          ..[r] = lines[r].substring(0, c);
        _cursors[w] = (r + 1, 0);
      case '<BS>' when c > 0:
        lines[r] = lines[r].replaceRange(c - 1, c, '');
        _cursors[w] = (r, c - 1);
      case _ when key.length == 1:
        lines[r] = lines[r].replaceRange(c, c, key);
        _cursors[w] = (r, c + 1);
      default:
        return;
    }
    vm.setLines(lines, coalesceKey: _insertKey);
  }

  void _command(String key) {
    switch (key) {
      case '<Esc>':
        mode = Mode.normal;
      case '<CR>':
        mode = Mode.normal;
        message = '';
        run(commandLine);
      case '<BS>':
        if (commandLine.isEmpty) mode = Mode.normal;
        commandLine = commandLine.substring(0, max(0, commandLine.length - 1));
      case _ when key.length == 1:
        commandLine += key;
    }
  }

  /// Runs an ex command line (without the `:`).
  void run(String line) {
    final [cmd, ...args] = line.trim().split(RegExp(r'\s+'));
    final arg = args.join(' ');
    final w = activeWindow;
    switch (cmd) {
      case 'e' when arg.isNotEmpty:
        controller.openBuffer(fileBuffer(arg));
      case 'w' when w != null:
        final b = bufferOf(w)!;
        container.read(fileSystemProvider)[fileOf(b)] =
            vmOf(b).model.lines.join('\n');
        message = '"${fileOf(b)}" written';
      case 'q' when w != null:
        controller.closeWindow(w);
      case 'split' when w != null:
        controller.splitWindow(w, axis: Axis.vertical);
      case 'vsplit' when w != null:
        controller.splitWindow(w, axis: Axis.horizontal);
      case 'tabnew':
        controller.newTab(buffer: fileBuffer(arg.isEmpty ? '[No Name]' : arg));
      case 'tabn' || 'tabp':
        final tabs = _shell.tabIds;
        final step = cmd == 'tabn' ? 1 : -1;
        controller.activateTab(
            tabs[(tabs.indexOf(activeTab) + step) % tabs.length]);
      case 'ls':
        message = [
          for (final (i, b) in listed.indexed) '${i + 1} "${fileOf(b)}"'
        ].join('  ');
      case 'b':
        final i = int.tryParse(arg);
        if (i != null && i >= 1 && i <= listed.length) {
          controller.openBuffer(listed[i - 1]);
        } else {
          message = 'E86: Buffer $arg does not exist';
        }
      default:
        message = 'E492: Not an editor command: $line';
    }
  }

  void _windowCommand(String key) {
    final w = activeWindow;
    if (w == null) return;
    switch (key) {
      case 'c':
        controller.closeWindow(w);
      case 'o':
        controller.dispatchAll([
          for (final other in doc.tabs[activeTab]!.root!.windowIds)
            if (other != w) CloseWindow(other),
        ]);
      case 'h' || 'j' || 'k' || 'l':
        final target = doc.neighbour(w, switch (key) {
          'h' => AxisDirection.left,
          'l' => AxisDirection.right,
          'k' => AxisDirection.up,
          _ => AxisDirection.down,
        });
        if (target != null) controller.activateWindow(target);
    }
  }
}
