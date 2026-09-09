// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/operation/_implementations/operation.dart';
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

  ValueListenable<int> get $count => $model.select((m) => m.count);

  /// Infallible in-binding (UI object drives the change).
  void setCount(int v) => publish(model.withCount(v));
}

/// A [ValueListenable<String>] standing in for a UI object (controller).
class FakeUiObject extends ValueNotifier<String> {
  FakeUiObject(super.value);
}

void main() {
  late CounterViewModel vm;
  late FakeUiObject ui;
  late Operation<Unit, String> op;
  late int applyCalls;
  late int uiNotifications;

  setUp(() {
    vm = CounterViewModel();
    ui = FakeUiObject('0');
    op = vm.operation<Unit, String>();
    applyCalls = 0;
    uiNotifications = 0;
    ui.addListener(() => uiNotifications++);
    vm.bind<String, int, String>(
      modelValue: vm.$count,
      uiValue: ui,
      toUi: (count) => '$count',
      fromUi: (text) => int.parse(text),
      writeUi: (text) => ui.value = text,
      apply: (count) {
        applyCalls++;
        return vm.model.withNonNegative(count);
      },
      via: op,
    );
  });

  tearDown(() => vm.dispose());

  group('bind — in-channel (UI → model)', () {
    test('applies the model method and publishes', () {
      ui.value = '5';
      expect(vm.model.count, 5);
      expect(applyCalls, 1);
      expect(op.state, const Idle<Result<String, Unit>>());
    });

    test('publishes exactly once — no echo from the out-channel', () {
      var modelNotifications = 0;
      vm.$model.addListener(() => modelNotifications++);

      ui.value = '5';

      expect(modelNotifications, 1, reason: 'single publish, no echo loop');
      expect(uiNotifications, 1, reason: 'out-write suppressed during in-processing');
    });

    test('failure keeps the model, surfaces the error and reconciles the UI object', () {
      ui.value = '-3';

      expect(vm.model.count, 0, reason: 'failed change never touches the model');
      expect(op.state, const Ready<Result<String, Unit>>(Err('negative')));
      expect(ui.value, '0', reason: 'rejected input snaps back to model state');
      expect(applyCalls, 1);
    });

    test('a successful change after a failure resets the operation', () {
      ui.value = '-3';
      ui.value = '4';
      expect(vm.model.count, 4);
      expect(op.state, const Idle<Result<String, Unit>>());
    });
  });

  group('bind — out-channel (model → UI)', () {
    test('writes external model changes into the UI object', () {
      vm.publish(const CounterModel(7));
      expect(ui.value, '7');
      expect(applyCalls, 0, reason: 'out-write is not re-applied to the model');
    });

    test('does not echo back into the model', () {
      var modelNotifications = 0;
      vm.$model.addListener(() => modelNotifications++);

      vm.publish(const CounterModel(7));

      expect(modelNotifications, 1);
      expect(applyCalls, 0, reason: 'in-channel suppressed during out-write');
    });
  });

  group('bind — disposal', () {
    test('detach stops the in-channel', () {
      vm.dispose();

      ui.value = '9';
      expect(vm.model.count, 0, reason: 'in-channel detached');

      ui.dispose();
      expect(
        () => vm.publish(const CounterModel(2)),
        throwsA(isA<Error>()),
        reason: 'model notifier is dead after dispose — out-channel lifecycle '
            'ends with the viewmodel (FlutterError on stable, StateError on master)',
      );
    });
  });
}

