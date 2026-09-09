import 'package:flutter/widgets.dart';
import 'package:reef/features/page/_implementations/reef_window.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_auto_route/reef_auto_route.dart';
import 'package:reef_example/_kit/kit.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart'
    show TaskError;
import 'package:reef_example/features/task_editor/_presentation/list/task_list_provider.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_widget.dart';

/// List page: layout + wiring only — a search field bound by the viewmodel
/// and the paginated list scaffold.
class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key, this.bufferId});

  /// Opens this buffer; null materializes a fresh one.
  final BufferId? bufferId;

  @override
  Widget build(BuildContext context) => ReefWindow(
        bufferId: bufferId,
        viewModel: (id) => taskListViewModelProvider(bufferId: id),
        builder: (context, vm) => _TaskListLayout(viewModel: vm),
      );
}

class _TaskListLayout extends StatelessWidget {
  const _TaskListLayout({required this.viewModel});

  final TaskListViewModel viewModel;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const KitHeader(title: 'Reef — tasks'),
          Padding(
            padding: const EdgeInsets.all(16),
            // Widgets are pure views: the controller is bound by the
            // viewmodel, no onChanged wiring (§5).
            child: KitField(
              controller: viewModel.queryController,
              label: 'Filter tasks',
            ),
          ),
          Expanded(
            child: InfiniteScrollWidget<String, String, TaskError>(
              controller: viewModel.scroll,
              loadingFirstBuilder: (_) => const Center(child: KitSpinner()),
              footerBuilder: (_) => const Center(child: KitSpinner(size: 14)),
              itemBuilder: (context, task, index) => _TaskRow(
                task: task,
                // The `:split` intent — pages inside a workspace open
                // buffers through the scope (§10.3); the router URL follows.
                onTap: () => WorkspaceScope.of(context).split(
                  BufferId.manual('task-edit:$task'),
                  axis: Axis.horizontal,
                ),
              ),
            ),
          ),
        ],
      );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});

  final String task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Text(task, style: const TextStyle(fontSize: 15)),
        ),
      );
}
