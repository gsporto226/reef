import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page/_implementations/reef_buffer_scope.dart';
import 'package:reef/features/page/_implementations/reef_window.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/page_identity/_providers/reef_scope_provider.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';

class CounterModel {
  const CounterModel(this.count);

  final int count;

  CounterModel withCount(int v) => CounterModel(v);
}

class CounterViewModel extends ViewModel<CounterModel> {
  CounterViewModel() : super(const CounterModel(0));

  bool disposed = false;

  void setCount(int v) => publish(model.withCount(v));

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

final counterViewModelProvider = Provider.autoDispose.family<CounterViewModel,
    BufferId>((ref, id) {
  final vm = CounterViewModel();
  ref.onDispose(vm.dispose);
  return vm;
});

Widget app(List<Widget> windows) => ProviderScope(
      child: WidgetsApp(
        color: const Color(0xFF00695C),
        builder: (_, _) => Column(children: windows),
      ),
    );

ReefWindow<CounterViewModel> counterWindow({
  BufferId? bufferId,
  void Function(CounterViewModel vm)? onVm,
}) =>
    ReefWindow<CounterViewModel>(
      bufferId: bufferId,
      viewModel: (id) => counterViewModelProvider(id),
      builder: (context, vm) {
        onVm?.call(vm);
        return ValueListenableBuilder(
          valueListenable: vm.$model,
          builder: (_, model, _) => Text('count: ${model.count}'),
        );
      },
    );

void main() {
  testWidgets('ReefWindow watches the viewmodel provider and rebuilds on publish',
      (tester) async {
    CounterViewModel? captured;

    await tester.pumpWidget(app([counterWindow(onVm: (vm) => captured = vm)]));

    expect(find.text('count: 0'), findsOneWidget);
    expect(captured, isNotNull);

    captured!.setCount(5);
    await tester.pump();

    expect(find.text('count: 5'), findsOneWidget);
  });

  testWidgets('ReefWindow disposes the viewmodel on unmount', (tester) async {
    CounterViewModel? captured;

    await tester.pumpWidget(app([counterWindow(onVm: (vm) => captured = vm)]));

    final vm = captured!;
    expect(vm.disposed, isFalse);

    await tester.pumpWidget(app(const []));
    await tester.pump();
    expect(vm.disposed, isTrue, reason: 'autoDispose runs when the window unmounts');
  });

  testWidgets('windows without a buffer id get distinct buffers', (tester) async {
    final viewmodels = <CounterViewModel>[];

    await tester.pumpWidget(app([
      counterWindow(onVm: viewmodels.add),
      counterWindow(onVm: viewmodels.add),
    ]));

    expect(viewmodels.length, 2);
    expect(identical(viewmodels[0], viewmodels[1]), isFalse,
        reason: 'each window materializes its own buffer');
  });

  testWidgets('two windows on one buffer share the viewmodel and live-sync',
      (tester) async {
    final buffer = BufferId.manual('doc');
    final viewmodels = <CounterViewModel>[];

    await tester.pumpWidget(app([
      counterWindow(bufferId: buffer, onVm: viewmodels.add),
      counterWindow(bufferId: buffer, onVm: viewmodels.add),
    ]));

    expect(viewmodels.length, 2);
    expect(identical(viewmodels[0], viewmodels[1]), isTrue,
        reason: 'same bufferId → same family member → same viewmodel');

    // The neovim test: an edit in one window is instantly visible in the
    // other, because both render the same buffer's listenables.
    viewmodels.first.setCount(7);
    await tester.pump();

    expect(find.text('count: 7'), findsNWidgets(2));
  });

  testWidgets('ReefBufferScope.of(context) exposes the buffer id to descendants',
      (tester) async {
    final buffer = BufferId.manual('visible');
    BufferId? seen;

    await tester.pumpWidget(app([
      ReefWindow<CounterViewModel>(
        bufferId: buffer,
        viewModel: (id) => counterViewModelProvider(id),
        builder: (context, vm) {
          // A nested widget (layout, dialog, …) reaches the id via the scope.
          seen = ReefBufferScope.of(context);
          return const SizedBox();
        },
      ),
    ]));

    expect(seen, buffer);
  });

  testWidgets('the buffer scope dies with the buffer, not with one window',
      (tester) async {
    final buffer = BufferId.manual('scoped');
    var scopeDisposed = false;

    Widget scopeWatcher() => Consumer(builder: (context, ref, _) {
          final scope = ref.watch(reefScopeProvider(buffer));
          scope.registerOnDispose(() => scopeDisposed = true);
          return const SizedBox();
        });

    // Two windows on the buffer, plus a scope-watching widget.
    await tester.pumpWidget(app([
      counterWindow(bufferId: buffer),
      counterWindow(bufferId: buffer),
      scopeWatcher(),
    ]));
    expect(scopeDisposed, isFalse);

    // One window closes — the buffer (and its scope) is still alive.
    await tester.pumpWidget(app([counterWindow(bufferId: buffer), scopeWatcher()]));
    await tester.pump();
    expect(scopeDisposed, isFalse);

    // Last window gone — the buffer dies, the scope dies with it.
    await tester.pumpWidget(app(const []));
    await tester.pump();
    await tester.pump();
    expect(scopeDisposed, isTrue, reason: 'scope lifetime is the buffer lifetime');
  });
}
