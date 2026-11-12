import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:vim_editor/vim.dart';

void main() => runApp(VimApp(Vim(ProviderContainer())));

class VimApp extends StatelessWidget {
  const VimApp(this.vim, {super.key});

  final Vim vim;

  static String? keyToken(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) return '<Esc>';
    if (key == LogicalKeyboardKey.enter) return '<CR>';
    if (key == LogicalKeyboardKey.backspace) return '<BS>';
    if (key == LogicalKeyboardKey.tab) return '<C-i>';
    if (HardwareKeyboard.instance.isControlPressed) {
      final label = key.keyLabel.toLowerCase();
      return label.length == 1 ? '<C-$label>' : null;
    }
    return event.character;
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
        container: vim.container,
        child: MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              final token = keyToken(event);
              if (token == null) return KeyEventResult.ignored;
              vim.input(token);
              return KeyEventResult.handled;
            },
            child: Material(
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                child: Column(children: [
                  Expanded(
                    child: WindowingRoot(
                      controller: vim.controller,
                      bufferBuilder: (_, buffer) => BufferView(vim, buffer),
                      delegate: WindowingDelegate(
                        projectionPolicy: (_, _, _) =>
                            (_, _, shell) => DesktopProjection(shell),
                        windowChrome: (_, windowId, focused, page) =>
                            WindowFrame(vim, windowId, focused, page),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: vim,
                    builder: (_, _) => Text(
                      key: const ValueKey('cmdline'),
                      switch (vim.mode) {
                        Mode.command => ':${vim.commandLine}',
                        Mode.insert => '-- INSERT --',
                        Mode.normal => vim.message,
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A window: the page over a status line naming its buffer.
class WindowFrame extends StatelessWidget {
  const WindowFrame(this.vim, this.windowId, this.focused, this.page,
      {super.key});

  final Vim vim;
  final WindowId windowId;
  final bool focused;
  final Widget page;

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: page),
        Container(
          color: focused ? Colors.black87 : Colors.black26,
          width: double.infinity,
          child: Text(
            fileOf(vim.bufferOf(windowId)!),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ]);
}

/// A buffer's text with the window's cursor.
class BufferView extends ConsumerWidget {
  const BufferView(this.vim, this.buffer, {super.key});

  final Vim vim;
  final BufferId buffer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = WindowHost.of(context);
    final vm = ref.watch(textViewModelProvider(buffer));
    return ListenableBuilder(
      listenable: Listenable.merge([vm.$model, vim]),
      builder: (_, _) {
        final (row, col) = vim.cursorOf(window);
        return Align(
          alignment: Alignment.topLeft,
          child: Text.rich(
            key: ValueKey('text:${window.value}'),
            TextSpan(children: [
              for (final (r, line) in vm.model.lines.indexed)
                if (r != row)
                  TextSpan(text: '$line\n')
                else ...[
                  TextSpan(text: line.substring(0, col.clamp(0, line.length))),
                  TextSpan(
                    text: col < line.length ? line[col] : ' ',
                    style: const TextStyle(backgroundColor: Colors.amber),
                  ),
                  TextSpan(
                      text: '${col < line.length ? line.substring(col + 1) : ''}\n'),
                ],
            ]),
          ),
        );
      },
    );
  }
}
