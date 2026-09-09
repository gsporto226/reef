// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter_test/flutter_test.dart';
import 'package:formularium/features/forms/_data_types/form_field_state.dart';
import 'package:formularium/features/forms/_data_types/form_field_status.dart';
import 'package:formularium/features/forms/_implementations/form_field_validators.dart';
import 'package:formularium/features/forms/_implementations/raw_formularium_form_field.dart';
import 'package:formularium/features/forms/_implementations/uncategorized_form_field_validator.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/formularium_bridge/_implementations/result_validation.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

class TextError implements ILocalizable {
  const TextError(this.message);

  final String message;

  @override
  String localize() => message;
}

class DateModel {
  const DateModel(this.dueDate);

  final DateTime dueDate;

  DateModel withDueDate(DateTime d) => DateModel(d);

  Result<String, DateModel> withFutureDueDate(DateTime d) =>
      d.isBefore(DateTime(2026, 1, 1)) ? const Err('past date') : Ok(DateModel(d));
}

typedef RawDateField = RawFormulariumFormField<DateTime, DateTime>;

class DateViewModel extends ViewModel<DateModel> {
  DateViewModel({DateModel? model})
    : super(model ?? DateModel(DateTime(2026, 6, 1))) {
    final base = model ?? DateModel(DateTime(2026, 6, 1));
    field = RawFormulariumFormField<DateTime, DateTime>(
      initialValue: base.dueDate,
      validator: modelValidator<DateModel, DateTime, String>(
        apply: (d) => base.withFutureDueDate(d),
        localize: (error) => TextError(error),
      ),
      enabled: true,
    );
    registerDisposal(field.dispose);
    bindField<DateTime, String>(
      field: field,
      modelValue: $model.select((m) => m.dueDate),
      apply: (d) => base.withFutureDueDate(d),
      via: dueDateOp,
    );
  }

  late final RawDateField field;
  late final dueDateOp = operation<Unit, String>();

  bool get isFieldDirty => field.state == FormFieldState.dirty;
}

DateTime fieldTransformedValue(RawDateField field) {
  final status = field.status;
  return status is Valid<DateTime> ? status.transformed : field.initialValue;
}

void main() {
  group('toValidation', () {
    test('Ok maps to a validation without a message', () {
      const result = Ok<String, int>(1);
      final validation = result.toValidation(7, localize: (e) => TextError(e));

      expect(validation.transformed, 7);
      expect(validation.validation, isNull);
    });

    test('Err maps to a validation with a localized message', () {
      const result = Err<String, int>('past date');
      final validation = result.toValidation(7, localize: (e) => TextError(e));

      expect(validation.transformed, 7);
      expect(validation.validation, isNotNull);
      expect(validation.validation!.localize(), 'past date');
    });
  });

  group('modelValidator', () {
    test('produces an invalidating error bundle delegating to the model method', () {
      final model = DateModel(DateTime(2026, 6, 1));
      final FormFieldValidatorBundle<DateTime, DateTime> bundle = modelValidator(
        apply: (d) => model.withFutureDueDate(d),
        localize: (error) => TextError(error),
      );

      expect(bundle.type, 'error');
      expect(bundle.invalidates, isTrue);

      final valid = bundle.validator(DateTime(2026, 5, 1)) as Validation<DateTime>;
      expect(valid.validation, isNull);
      expect(valid.transformed, DateTime(2026, 5, 1));

      final invalid = bundle.validator(DateTime(2025, 12, 31)) as Validation<DateTime>;
      expect(invalid.validation, isNotNull);
      expect(invalid.validation!.localize(), 'past date');
    });
  });

  group('bindField', () {
    late DateViewModel vm;

    setUp(() => vm = DateViewModel());
    tearDown(() => vm.dispose());

    test('Valid status applies the model method and publishes (apply-on-Valid)', () {
      final field = vm.field;
      field.value = DateTime(2026, 7, 1);
      field.validate(); // Raw field validates on command; FormulariumFormField autovalidates.

      expect(field.status, isA<Valid<DateTime>>());
      expect(vm.model.dueDate, DateTime(2026, 7, 1));
      expect(vm.dueDateOp.state, const Idle<Result<String, Unit>>());
      expect(vm.isFieldDirty, isTrue, reason: 'user change marks the field dirty');
    });

    test(r'Invalid status surfaces in $status without touching the model', () {
      final field = vm.field;
      field.value = DateTime(2025, 6, 1);
      field.validate();

      final status = field.status;
      expect(status, isA<Invalid<DateTime>>());
      final invalid = status as Invalid<DateTime>;
      expect(invalid.validation.validation.localize(), 'past date');
      expect(vm.model.dueDate, DateTime(2026, 6, 1), reason: 'invalid input never publishes');
    });

    test('external model change syncs the field without dirty marking', () {
      vm.publish(DateModel(DateTime(2026, 9, 9)));

      expect(fieldTransformedValue(vm.field), DateTime(2026, 9, 9));
      expect(vm.isFieldDirty, isFalse, reason: 'out-channel uses valueRaw (no dirty marking)');
      expect(vm.model.dueDate, DateTime(2026, 9, 9));
    });
  });
}

