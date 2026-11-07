import 'package:flutter/widgets.dart';
import 'package:reef/reef.dart';

/// A bare tab strip over a [WindowingController]: `+` opens a tab, tapping
/// `tab N` activates it, `x N` closes it. Drives the windowing integration
/// flow.
class WindowingDemo extends StatelessWidget {
  const WindowingDemo({super.key, required this.controller});

  final WindowingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WindowingDoc>(
        valueListenable: controller.doc,
        builder: (context, doc, _) {
          final shell = doc.shells[doc.focusedShellId]!;
          final tabs = shell.tabIds;
          return Column(children: [
            Row(children: [
              for (final (i, tab) in tabs.indexed) ...[
                GestureDetector(
                  onTap: () => controller.activateTab(tab),
                  child: Text('tab ${i + 1}'),
                ),
                GestureDetector(
                  onTap: () => controller.closeTab(tab),
                  child: Text('x ${i + 1}'),
                ),
              ],
              GestureDetector(
                onTap: () => controller.newTab(),
                child: const Text('+'),
              ),
            ]),
            Text('active: ${tabs.indexOf(shell.activeTabId) + 1}'),
            if (doc.tabs[shell.activeTabId]!
                case TabState(:final root?, activeWindowId: final window?))
              Row(children: [
                Text('windows: ${root.windowIds.length}'),
                if (root case WindowBranch(:final ratios))
                  Text('ratios: ${ratios.join(' ')}'),
                GestureDetector(
                  onTap: () =>
                      controller.splitWindow(window, axis: Axis.horizontal),
                  child: const Text('split'),
                ),
                GestureDetector(
                  onTap: () => controller.resizeWindow(window, [0.25, 0.75]),
                  child: const Text('resize'),
                ),
                GestureDetector(
                  onTap: () => controller.closeWindow(window),
                  child: const Text('close window'),
                ),
                Text('buffer: ${doc.windows[window]!.history.current.value}'),
                GestureDetector(
                  onTap: () => controller.pushBuffer(
                      window, BufferId.manual('pushed')),
                  child: const Text('push'),
                ),
                GestureDetector(
                  onTap: () => controller.popBuffer(window),
                  child: const Text('back'),
                ),
                GestureDetector(
                  onTap: () => controller.navigateForward(window),
                  child: const Text('forward'),
                ),
              ]),
          ]);
        },
      );
}
