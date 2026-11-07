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
            Row(children: [
              Text('shells: ${doc.shells.length}'),
              GestureDetector(
                onTap: controller.attachShell,
                child: const Text('new shell'),
              ),
              // One per other shell: pulls its active tab into this one.
              for (final MapEntry(:key, :value) in doc.shells.entries)
                if (key != doc.focusedShellId)
                  GestureDetector(
                    onTap: () => controller.moveTab(value.activeTabId,
                        shellId: doc.focusedShellId, index: tabs.length),
                    child: const Text('take tab'),
                  ),
            ]),
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
                GestureDetector(
                  onTap: () => controller.moveWindow(window, tabId: tabs.first),
                  child: const Text('window to tab 1'),
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
                GestureDetector(
                  onTap: () => controller.floatWindow(window,
                      scope: TabScope(shell.activeTabId)),
                  child: const Text('float'),
                ),
              ]),
            // The active tab's floating windows, bottom to top: `raise`
            // lifts the bottom one, `dock` docks the top one.
            if ([
              for (final MapEntry(:key, :value) in doc.floating.entries)
                if (value.scope == TabScope(shell.activeTabId)) key,
            ]..sort((a, b) =>
                    doc.floating[a]!.zIndex.compareTo(doc.floating[b]!.zIndex))
                case [final bottom, ..., final top] || [final bottom && final top])
              Row(children: [
                Text('top: ${doc.windows[top]!.history.current.value}'),
                GestureDetector(
                  onTap: () => controller.raiseWindow(bottom),
                  child: const Text('raise'),
                ),
                GestureDetector(
                  onTap: () =>
                      controller.dockWindow(top, tabId: shell.activeTabId),
                  child: const Text('dock'),
                ),
              ]),
          ]);
        },
      );
}
