import 'package:formularium/features/forms/_implementations/form_field_validators.dart';
import 'package:formularium/features/forms/_implementations/uncategorized_form_field_validator.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef_fp/result.dart';

extension ResultValidationX<E, M> on Result<E, M> {
  /// Maps a fallible model-method result to a formularium [Validation].
  ///
  /// `Ok(model)` → valid with [transformed]; `Err(error)` → invalid with the
  /// [ILocalizable] produced by [localize]. This keeps the model method as the
  /// single source of truth for the invariant: the field validator delegates
  /// to it (see `docs/blueprint.md` §6).
  Validation<V> toValidation<V>(
    V transformed, {
    required ILocalizable Function(E error) localize,
  }) => switch (this) {
    Err(:final value) => Validation(validation: localize(value), transformed: transformed),
    Ok() => Validation(validation: null, transformed: transformed),
  };
}

/// Builds a formularium validator bundle that **delegates to a model method**.
///
/// ```dart
/// final dueDateField = FormulariumFormField<DateTime, DateTime>(
///   initialValue: model.dueDate ?? today,
///   validator: modelValidator(
///     (date) => model.dueDate(date),
///     localize: (error) => error.message,
///   ),
///   enabled: true,
///   autovalidateMode: AutovalidateMode.always,
/// );
/// ```
FormFieldValidatorBundle<V, V> modelValidator<M, V, E>({
  required Result<E, M> Function(V value) apply,
  required ILocalizable Function(E error) localize,
}) => CategorizedFormFieldValidators.instance.error<V, V>(
  (value) => apply(value).toValidation(value, localize: localize),
);
