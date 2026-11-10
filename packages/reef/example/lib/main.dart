import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/task_editor/_presentation/list/task_list_page.dart';
import 'package:reef_example/features/windowing/window_host.dart';
import 'package:reef_example/main_windowing.dart' show startingLayout;
import 'package:reef_example/undo_providers.dart';

/// The kind→page mapping, shared by the app's [WindowingRoot] (its buffer
/// builder) and popped-out OS windows (§10.4) — one mapping, two hosts.
final Map<String, Widget Function(BuildContext, BufferId)> bufferPages = {
  'task-list': (_, id) => TaskListPage(bufferId: id),
  'task-edit': (_, id) => TaskEditPage(
        bufferId: id,
        initial: TaskEditModel(title: id.id.substring('task-edit:'.length)),
        windowHost: RealWindowHost(contentBuilder: bufferPageFor),
      ),
};

/// Builds the page for any buffer id the app knows.
Widget bufferPageFor(BuildContext context, BufferId id) =>
    bufferPages[id.id.split(':').first]?.call(context, id) ?? const SizedBox.shrink();

void main() => runApp(const ReefExampleApp());

class ReefExampleApp extends StatelessWidget {
  const ReefExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProviderScope(child: ReefExampleRoutedApp());
}

/// The app without the root [ProviderScope] — the windowed entrypoint puts
/// one above the window manager so every view shares it (§10.4). Opens one
/// shell on the task list, drawn by the default projection policy.
///
/// The app is design-free (§5) — [WidgetsApp], no Material.
// Name kept for the spike entry main_windowed.dart until W4 replaces it.
class ReefExampleRoutedApp extends StatefulWidget {
  const ReefExampleRoutedApp({super.key});

  @override
  State<ReefExampleRoutedApp> createState() => _ReefExampleRoutedAppState();
}

class _ReefExampleRoutedAppState extends State<ReefExampleRoutedApp> {
  late final _controller = WindowingController(
    initial: startingLayout(const BufferId.manual('task-list:all')),
    undo: ProviderScope.containerOf(context, listen: false)
        .read(undoControllerProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidgetsApp(
        title: 'Reef example',
        color: const Color(0xFF00695C),
        builder: (_, _) => WindowingRoot(
          controller: _controller,
          bufferBuilder: bufferPageFor,
        ),
      );
}
