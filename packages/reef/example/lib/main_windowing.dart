// The windowing playground: a WindowingController driven by the controls of
// WindowingPlayground. One entry for every platform: multi-shell with
// `FLUTTER_WINDOWING=true`, the focused shell inline without it. Run (master
// channel; never enable windowing through the global Flutter config):
//   $env:FLUTTER_WINDOWING = "true"
//   fvm flutter run -t lib/main_windowing.dart -d windows
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';
import 'package:reef_example/main.dart' show exampleStore, runsOnDesktop;
import 'package:reef_example/undo_providers.dart';
import 'package:reef_multi_window/reef_multi_window.dart';

/// One shell with one tab showing [buffer]. Built on a throwaway controller so
/// the starting layout is not an undo step.
WindowingDoc startingLayout(BufferId buffer) {
  final seed = WindowingController();
  final empty = seed.doc.value.shells.values.single.activeTabId;
  seed
    ..newTab(buffer: buffer)
    ..closeTab(empty);
  final doc = seed.doc.value;
  seed.dispose();
  return doc;
}

void main() => runWidget(ProviderScope(
      child: PlaygroundApp(
        store: exampleStore(desktop: runsOnDesktop(), name: 'reef_playground'),
      ),
    ));

/// The playground on [ShellViews]: one [PlaygroundShell] per real shell. The
/// layout and the projection switch hibernate into [store].
class PlaygroundApp extends ConsumerStatefulWidget {
  const PlaygroundApp({super.key, this.store});

  final HibernationStore? store;

  @override
  ConsumerState<PlaygroundApp> createState() => _PlaygroundAppState();
}

class _PlaygroundAppState extends ConsumerState<PlaygroundApp> {
  final _platform = RealShellPlatform(title: 'Reef windowing');
  late final _controller = WindowingController(
    initial: startingLayout(const BufferId.manual('welcome')),
    undo: ref.read(undoControllerProvider),
    platform: _platform,
    store: widget.store,
  );

  @override
  void dispose() {
    _controller.dispose();
    _platform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WindowingPlayground(
    controller: _controller,
    child: ShellViews(
      controller: _controller,
      platform: _platform,
      shellBuilder: (_, shellId) => PlaygroundShell(shellId),
    ),
  );
}
