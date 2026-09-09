// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

class CounterModel {
  const CounterModel(this.count);

  final int count;

  CounterModel withCount(int v) => CounterModel(v);

  Result<String, CounterModel> withNonNegative(int v) =>
      v < 0 ? const Err('negative') : Ok(CounterModel(v));
}

class CounterViewModel extends ViewModel<CounterModel> {
  CounterViewModel({CounterModel? model}) : super(model ?? const CounterModel(0));

  late final nonNegativeOp = operation<Unit, String>();

  void setNonNegative(int v) => edit(model.withNonNegative(v), via: nonNegativeOp);

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  group('ViewModel', () {
    test('owns the model and exposes it as a listenable', () {
      final vm = CounterViewModel();
      expect(vm.model, const CounterModel(0));
      expect(vm.$model.value, const CounterModel(0));
      vm.dispose();
    });

    test('publish replaces the model and notifies', () {
      final vm = CounterViewModel();
      var notifications = 0;
      vm.$model.addListener(() => notifications++);

      vm.publish(const CounterModel(7));
      expect(vm.model.count, 7);
      expect(notifications, 1);
      vm.dispose();
    });

    test('edit Ok publishes and resets the operation', () {
      final vm = CounterViewModel();
      vm.setNonNegative(5);
      expect(vm.model.count, 5);
      expect(vm.nonNegativeOp.state, const Idle<Result<String, Unit>>());
      vm.dispose();
    });

    test('edit Err surfaces the failure, keeps the model and runs onFail', () {
      final vm = CounterViewModel();
      var onFailRuns = 0;
      vm.edit(const Err('negative'), via: vm.nonNegativeOp, onFail: [() => onFailRuns++]);

      expect(vm.model.count, 0, reason: 'failed change never touches the model');
      expect(vm.nonNegativeOp.state, const Ready<Result<String, Unit>>(Err('negative')));
      expect(onFailRuns, 1);

      vm.setNonNegative(3);
      expect(vm.model.count, 3, reason: 'next success resets the operation');
      expect(vm.nonNegativeOp.state, const Idle<Result<String, Unit>>());
      vm.dispose();
    });

    test('operation() registers disposal', () {
      final vm = CounterViewModel();
      final op = vm.operation<int, String>();
      vm.dispose();
      expect(
        () => op.$state.addListener(() {}),
        throwsA(isA<Error>()),
        reason: 'operation notifier disposed with the viewmodel '
            '(FlutterError on stable, StateError on master)',
      );
    });

    test('dispose runs registered disposals in reverse order', () {
      final vm = CounterViewModel();
      final order = <int>[];
      vm.registerDisposal(() => order.add(1));
      vm.registerDisposal(() => order.add(2));
      vm.dispose();
      expect(order, [2, 1]);
      expect(vm.disposed, isTrue);
    });
  });
}

