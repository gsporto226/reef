// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_edit_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskEditModel _$TaskEditModelFromJson(Map<String, dynamic> json) =>
    _TaskEditModel(
      title: json['title'] as String? ?? '',
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.parse(json['dueDate'] as String),
    );

Map<String, dynamic> _$TaskEditModelToJson(_TaskEditModel instance) =>
    <String, dynamic>{
      'title': instance.title,
      'dueDate': instance.dueDate?.toIso8601String(),
    };
