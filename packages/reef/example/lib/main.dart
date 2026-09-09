import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_auto_route/reef_auto_route.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/task_editor/_presentation/list/task_list_page.dart';
import 'package:reef_example/features/windowing/window_host.dart';

/// The app's routing (blueprint §10.3): one workspace route hosting the
/// split workspace; buffers are deep-linkable through the `?b=` query
/// (`kind:token` ids — `task-edit:<task>`). Codegen-free via
/// [RootStackRouter.build] + [NamedRouteDef].
///
/// The app is design-free (§5) — [WidgetsApp], no Material — so routes use
/// [RouteType.custom]: Material routes require MaterialLocalizations, which
/// a WidgetsApp doesn't provide.
/// The kind→page mapping, shared by the workspace registry (panes) and
/// popped-out OS windows (§10.4) — one mapping, two hosts.
final Map<String, Widget Function(BuildContext, BufferId)> bufferPages = {
  'task-list': (_, id) => TaskListPage(bufferId: id),
  'task-edit': (_, id) => TaskEditPage(
        bufferId: id,
        initial: TaskEditModel(title: id.id.substring('task-edit:'.length)),
        windowHost: RealWindowHost(contentBuilder: bufferPageFor),
      ),
};

/// Builds the page for any routable buffer id (windowed pop-outs; panes go
/// through [bufferPages] via the registry's own lookup).
Widget bufferPageFor(BuildContext context, BufferId id) =>
    bufferPages[id.kind]?.call(context, id) ?? const SizedBox.shrink();

final appRouter = RootStackRouter.build(
  defaultRouteType: RouteType.custom(
    transitionsBuilder: (_, _, _, child) => child,
  ),
  routes: [
    // The default tab is a deep link: the workspace opens with the list buffer.
    RedirectRoute(path: '/', redirectTo: '/w/main?b=task-list:all'),
    NamedRouteDef(
      name: 'WorkspaceRoute',
      path: '/w/:tabId',
      builder: (context, data) => WorkspaceShell(
        tabId: data.params.getString('tabId'),
        registry: WorkspaceRegistry(kinds: bufferPages),
      ),
    ),
  ],
);

void main() => runApp(const ReefExampleApp());

class ReefExampleApp extends StatelessWidget {
  const ReefExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProviderScope(child: ReefExampleRoutedApp());
}

/// The routed app without the root [ProviderScope] — the windowed entrypoint
/// puts one above the window manager so every view shares it (§10.4).
class ReefExampleRoutedApp extends StatelessWidget {
  const ReefExampleRoutedApp({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp.router(
        title: 'Reef example',
        color: const Color(0xFF00695C),
        routerConfig: appRouter.config(),
      );
}
