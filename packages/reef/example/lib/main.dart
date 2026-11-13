import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/task_editor/_presentation/list/task_list_page.dart';
import 'package:reef_example/_kit/kit.dart';
import 'package:reef_example/json_file_hibernation_store.dart';
import 'package:reef_example/links.dart';
import 'package:reef_multi_window/reef_multi_window.dart';
import 'package:reef_router/reef_router.dart';
import 'package:reef_example/main_windowing.dart' show startingLayout;
import 'package:reef_example/undo_providers.dart';

/// Builds the page for any buffer id the app knows, shared by every shell.
Widget bufferPageFor(BuildContext context, BufferId id) =>
    switch (exampleLinks.routeOfBuffer(id)) {
      TaskListRoute() => TaskListPage(bufferId: id),
      TaskEditRoute(:final title) => TaskEditPage(
        bufferId: id,
        initial: TaskEditModel(title: title),
      ),
      _ => const SizedBox.shrink(),
    };

/// One entry for every platform: multi-shell with `FLUTTER_WINDOWING=true`,
/// the focused shell inline without it. Run (master channel; never enable
/// windowing through the global Flutter config):
///   $env:FLUTTER_WINDOWING = "true"
///   fvm flutter run -d windows
/// A task path given as the first launch argument opens that editor:
///   fvm flutter run -d windows -a "/tasks/Buy milk/edit"
void main([List<String> args = const []]) => runWidget(
  ReefExampleApp(
    store: exampleStore(desktop: runsOnDesktop()),
    launchArgs: args,
  ),
);

/// Whether this run is a desktop app outside tests.
bool runsOnDesktop() =>
    !kIsWeb &&
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
    // A test binding is already up when a test calls main.
    BindingBase.debugBindingType() == null;

/// The app's store: the JSON file `[name]_hibernation.json` in [directory]
/// (next to the executable by default) on [desktop], in memory on web and in
/// tests.
HibernationStore exampleStore({
  required bool desktop,
  Directory? directory,
  String name = 'reef_example',
}) => desktop
    ? JsonFileHibernationStore.load(
        File(
          '${(directory ?? File(Platform.resolvedExecutable).parent).path}'
          '/${name}_hibernation.json',
        ),
      )
    : InMemoryHibernationStore();

/// One [ProviderScope] above every shell, so a buffer shown in two shells is
/// the same viewmodel. Buffers and the layout hibernate into [store]. The
/// first of [launchArgs], a path in [exampleLinks], opens on top of the
/// restored layout. The focused task's path is reported to
/// [routeInformationProvider] (the platform's by default: the browser URL on
/// web).
class ReefExampleApp extends StatefulWidget {
  const ReefExampleApp({
    super.key,
    this.store,
    this.launchArgs = const [],
    this.routeInformationProvider,
  });

  final HibernationStore? store;
  final List<String> launchArgs;
  final RouteInformationProvider? routeInformationProvider;

  @override
  State<ReefExampleApp> createState() => _ReefExampleAppState();
}

class _ReefExampleAppState extends State<ReefExampleApp> {
  /// Bumped by "Reset layout": a fresh controller starts on the first-run
  /// layout while the buffers above it stay.
  var _layout = 0;

  late final _container = ProviderContainer(
    overrides: [
      if (widget.store case final store?)
        hibernationStoreProvider.overrideWithValue(store),
    ],
  );

  /// A closing desktop app may never dispose its tree, so the buffers are
  /// disposed, and so hibernated, when the app is asked to exit or detaches.
  late final AppLifecycleListener _exit;

  @override
  void initState() {
    super.initState();
    _exit = AppLifecycleListener(
      onExitRequested: () async {
        _disposeContainer();
        return AppExitResponse.exit;
      },
      onDetach: _disposeContainer,
    );
  }

  var _disposed = false;

  /// An exit request, a detach and the state's dispose may all arrive.
  void _disposeContainer() {
    if (_disposed) return;
    _disposed = true;
    _container.dispose();
  }

  @override
  void dispose() {
    _exit.dispose();
    _disposeContainer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: _ExampleShells(
      key: ValueKey(_layout),
      // The launch link applies once, not again after "Reset layout".
      link: _layout == 0 ? widget.launchArgs.firstOrNull : null,
      routeInformationProvider: widget.routeInformationProvider,
      onResetLayout: () => setState(() => _layout++),
    ),
  );
}

class _ExampleShells extends StatefulWidget {
  const _ExampleShells({
    super.key,
    required this.link,
    required this.onResetLayout,
    required this.routeInformationProvider,
  });

  final String? link;
  final RouteInformationProvider? routeInformationProvider;
  final VoidCallback onResetLayout;

  @override
  State<_ExampleShells> createState() => _ExampleShellsState();
}

class _ExampleShellsState extends State<_ExampleShells> {
  final _platform = RealShellPlatform(title: 'Reef example');
  late final _container = ProviderScope.containerOf(context, listen: false);
  late final _controller = WindowingController(
    initial: () => startingLayout(taskListBuffer),
    undo: _container.read(undoControllerProvider),
    platform: _platform,
    store: _container.read(hibernationStoreProvider),
    // Editors open beside the list, the launch link's too.
    openPolicy: splitBesideOpenPolicy,
  );
  late final _nav = LinkNavigator(exampleLinks, _controller);

  @override
  void initState() {
    super.initState();
    // Restored first, then the link on top (spec §9 cold start).
    if (widget.link case final link?) {
      _nav.go(exampleLinks.routeOf(Uri.parse(link)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _platform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LinkScope(
    navigator: _nav,
    child: WindowingRoot(
      controller: _controller,
      bufferBuilder: bufferPageFor,
      child: WindowingLinkSync(
        tree: exampleLinks,
        routeInformationProvider: widget.routeInformationProvider,
        child: WindowingSystemBack(
          child: ShellViews(
            controller: _controller,
            platform: _platform,
            shellBuilder: (_, shellId) => ExampleShell(
              shellId,
              onResetLayout: () {
                _controller.discardSavedLayout();
                widget.onResetLayout();
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shell [shellId]'s surface: the shell controls over the shell drawn by the
/// projection policy. The app is design-free (§5): [WidgetsApp], no Material.
class ExampleShell extends StatelessWidget {
  const ExampleShell(this.shellId, {super.key, required this.onResetLayout});

  final ShellId shellId;

  /// Discards the saved layout and returns to the first-run layout.
  final VoidCallback onResetLayout;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Reef example',
    color: const Color(0xFF00695C),
    builder: (context, _) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              KitButton(label: 'Reset layout', onPressed: onResetLayout),
              if (WindowingScope.of(
                context,
              ).controller.capabilities.canPopOut) ...[
                const SizedBox(width: 8),
                _ShellBar(shellId),
              ],
            ],
          ),
        ),
        Expanded(child: ShellProjection(shellId)),
      ],
    ),
  );
}

/// Shown only where the platform can open shells.
class _ShellBar extends StatelessWidget {
  const _ShellBar(this.shellId);

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final controller = WindowingScope.of(context).controller;
    return Row(
      children: [
        KitButton(label: 'New shell', onPressed: controller.openShell),
        const SizedBox(width: 8),
        KitButton(
          label: 'Pop out tab',
          onPressed: () => controller.popOutTab(
            controller.doc.value.shells[shellId]!.activeTabId,
          ),
        ),
        const SizedBox(width: 8),
        KitButton(
          label: 'Close shell',
          onPressed: () => controller.closeShell(shellId),
        ),
      ],
    );
  }
}
