import 'dart:core';

/// Representa um período de tempo entre duas datas
class DateRange {
  ///
  const DateRange({required this.start, required this.end});

  /// Data inicial
  final DateTime? start;

  /// Data final
  final DateTime? end;
}