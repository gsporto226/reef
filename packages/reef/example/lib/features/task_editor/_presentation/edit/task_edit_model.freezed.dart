// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_edit_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskEditModel {

 String get title; DateTime? get dueDate;
/// Create a copy of TaskEditModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskEditModelCopyWith<TaskEditModel> get copyWith => _$TaskEditModelCopyWithImpl<TaskEditModel>(this as TaskEditModel, _$identity);

  /// Serializes this TaskEditModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TaskEditModel;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskEditModel&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.dueDate, _this.dueDate) || other.dueDate == _this.dueDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TaskEditModel;
  return Object.hash(runtimeType,_this.title,_this.dueDate);
}

@override
String toString() {
  final _this = this as TaskEditModel;
  return 'TaskEditModel(title: ${_this.title}, dueDate: ${_this.dueDate})';
}


}

/// @nodoc
abstract mixin class $TaskEditModelCopyWith<$Res>  {
  factory $TaskEditModelCopyWith(TaskEditModel value, $Res Function(TaskEditModel) _then) = _$TaskEditModelCopyWithImpl;
@useResult
$Res call({
 String title, DateTime? dueDate
});




}
/// @nodoc
class _$TaskEditModelCopyWithImpl<$Res>
    implements $TaskEditModelCopyWith<$Res> {
  _$TaskEditModelCopyWithImpl(this._self, this._then);

  final TaskEditModel _self;
  final $Res Function(TaskEditModel) _then;

/// Create a copy of TaskEditModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? dueDate = freezed,}) {
  return _then(TaskEditModel(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskEditModel].
extension TaskEditModelPatterns on TaskEditModel {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskEditModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskEditModel() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskEditModel value)  $default,){
final _that = this;
switch (_that) {
case _TaskEditModel():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskEditModel value)?  $default,){
final _that = this;
switch (_that) {
case _TaskEditModel() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  DateTime? dueDate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskEditModel() when $default != null:
return $default(_that.title,_that.dueDate);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  DateTime? dueDate)  $default,) {final _that = this;
switch (_that) {
case _TaskEditModel():
return $default(_that.title,_that.dueDate);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  DateTime? dueDate)?  $default,) {final _that = this;
switch (_that) {
case _TaskEditModel() when $default != null:
return $default(_that.title,_that.dueDate);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskEditModel extends TaskEditModel {
  const _TaskEditModel({this.title = '', this.dueDate}): super._();
  factory _TaskEditModel.fromJson(Map<String, dynamic> json) => _$TaskEditModelFromJson(json);

@override@JsonKey() final  String title;
@override final  DateTime? dueDate;

/// Create a copy of TaskEditModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskEditModelCopyWith<_TaskEditModel> get copyWith => __$TaskEditModelCopyWithImpl<_TaskEditModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskEditModelToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskEditModel&&(identical(other.title, title) || other.title == title)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,title,dueDate);
}

@override
String toString() {
    return 'TaskEditModel(title: $title, dueDate: $dueDate)';
}


}

/// @nodoc
abstract mixin class _$TaskEditModelCopyWith<$Res> implements $TaskEditModelCopyWith<$Res> {
  factory _$TaskEditModelCopyWith(_TaskEditModel value, $Res Function(_TaskEditModel) _then) = __$TaskEditModelCopyWithImpl;
@override @useResult
$Res call({
 String title, DateTime? dueDate
});




}
/// @nodoc
class __$TaskEditModelCopyWithImpl<$Res>
    implements _$TaskEditModelCopyWith<$Res> {
  __$TaskEditModelCopyWithImpl(this._self, this._then);

  final _TaskEditModel _self;
  final $Res Function(_TaskEditModel) _then;

/// Create a copy of TaskEditModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? dueDate = freezed,}) {
  return _then(_TaskEditModel(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
