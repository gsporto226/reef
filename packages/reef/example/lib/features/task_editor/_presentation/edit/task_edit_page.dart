import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formularium/features/forms/_data_types/form_field_status.dart';
import 'package:reef/features/page/_implementations/reef_buffer_scope.dart';
import 'package:reef/features/page/_implementations/reef_window.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/_kit/kit.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_provider.dart';
import 'package:reef_example/features/windowing/window_host.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

/// Page layer: layout + wiring only (blueprint §4) — defines the buffer type;
/// [ReefWindow] owns identity, scope and the provider watch (§4.4, §10).
class TaskEditPage extends ConsumerWidget {
  const TaskEditPage({super.key, this.bufferId, this.initial, this.windowHost});

  /// Opens this buffer; null materializes a fresh one.
  final BufferId? bufferId;

  /// Seed for a fresh buffer (the route's task token); a hibernated model
  /// wins over it (§10.2).
  final TaskEditModel? initial;

  /// Pops this buffer out into an OS window (§10.4); null = no affordance.
  final WindowHost? windowHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ReefWindow<TaskEditViewModel>(
        bufferId: bufferId,
        viewModel: (id) {
          if (initial case final seed?) {
            ref.read(taskEditSeedsProvider).putIfAbsent(id, () => seed);
          }
          return taskEditViewModelProvider(bufferId: id);
        },
        builder: (context, vm) =>
            _TaskEditLayout(viewModel: vm, windowHost: windowHost),
      );
}

class _TaskEditLayout extends StatelessWidget {
  const _TaskEditLayout({required this.viewModel, this.windowHost});

  final TaskEditViewModel viewModel;
  final WindowHost? windowHost;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KitHeader(title: 'Reef — task editor'),
          if (windowHost != null && windowHost!.isSupportedIn(context))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: KitButton(
                  label: 'Open in window',
                  onPressed: () {
                    final bufferId = ReefBufferScope.of(context);
                    windowHost!.open(
                      context,
                      BufferWindowRequest(
                        bufferId: bufferId,
                        title: bufferId.id,
                      ),
                    );
                  },
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title: widgets are pure views — the TextEditingController is
                  // bound by the viewmodel, no onChanged wiring.
                  KitField(
                    controller: viewModel.titleController,
                    label: 'Title',
                  ),
                  const SizedBox(height: 16),
                  // Due date: status (validation) from the formularium field;
                  // quick picks replace Material's showDatePicker.
                  ValueListenableBuilder(
                    valueListenable: viewModel.$dueDateStatus,
                    builder: (context, status, _) {
                      final message = switch (status) {
                        final Valid<DateTime?> v => v.transformed == null
                            ? 'Pick a due date'
                            : 'Due: ${kitFormatDate(v.transformed!)}',
                        final Invalid<DateTime?> i =>
                          i.validation.validation.localize(),
                        _ => 'Pick a due date',
                      };
                      final invalid = status is Invalid<DateTime>;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            style: TextStyle(
                              color: invalid
                                  ? const Color(0xFFB71C1C)
                                  : const Color(0xFF444444),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              KitButton(
                                label: 'Today',
                                onPressed: () => viewModel
                                    .onDueDatePicked(DateTime.now()),
                              ),
                              const SizedBox(width: 8),
                              KitButton(
                                label: '+1 week',
                                onPressed: () => viewModel.onDueDatePicked(
                                    DateTime.now().add(_oneWeek())),
                              ),
                              const SizedBox(width: 8),
                              KitButton(
                                label: 'Clear',
                                onPressed: () =>
                                    viewModel.onDueDatePicked(null),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Save: operation state rendered with the standard three-way switch.
                  ValueListenableBuilder(
                    valueListenable: viewModel.$save,
                    builder: (context, state, _) {
                      final message = state.when(
                        idle: () => 'Not saved yet',
                        pending: () => 'Saving…',
                        ready: (result) => switch (result) {
                          final Ok<TaskError, Unit> _ => 'Saved!',
                          final Err<TaskError, Unit> e => e.value.localize(),
                        },
                      );
                      return Text(
                        message,
                        style: TextStyle(
                          color: state.when(
                            idle: () => const Color(0xFF444444),
                            pending: () => const Color(0xFF444444),
                            ready: (result) => result.isErr
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  KitButton(
                    label: 'Save (submit style)',
                    filled: true,
                    onPressed: viewModel.onSubmit,
                  ),
                  const KitDivider(),
                  const _HibernateBar(),
                ],
              ),
            ),
          ),
        ],
      );

  Duration _oneWeek() => const Duration(days: 7);
}

/// Demo of the hibernation contract: snapshot the model JSON, dispose-free
/// restore via publish — the out-channel re-seeds every UI object.
/// Reaches its buffer through the scope — no constructor threading (§4.4).
class _HibernateBar extends ConsumerStatefulWidget {
  const _HibernateBar();

  @override
  ConsumerState<_HibernateBar> createState() => _HibernateBarState();
}

class _HibernateBarState extends ConsumerState<_HibernateBar> {
  Map<String, dynamic>? snapshot;

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(
      taskEditViewModelProvider(bufferId: ReefBufferScope.of(context)),
    );
    return Row(
      children: [
        KitButton(
          label: 'Hibernate',
          onPressed: () =>
              setState(() => snapshot = _decode(vm.model.toJson())),
        ),
        const SizedBox(width: 8),
        KitButton(
          label: 'Restore',
          onPressed: snapshot == null ? null : () => vm.restore(snapshot!),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            snapshot == null ? 'No snapshot' : 'Snapshot stored',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _decode(Map<String, dynamic> json) => json;
}
