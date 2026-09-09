import 'package:reef_utils/date_time/_data_types/time_unit.dart';

/// Extensões para a classe [DateTime].
extension DateTimeExtensions on DateTime {
  /// Retorna a última [TimeUnit] definida no [DateTime], onde 0 é considerada a falta de um valor.
  ///
  /// Exemplo: 16/12/2025 00:00:00 => day
  /// Exemplo: 16/12/2025 08:00:00 => hour
  /// Exemplo: 16/12/2025 08:30:00 => minute
  /// Exemplo: 16/12/2025 08:30:55 => second
  TimeUnit detect() {
    TimeUnit detected = .day;
    if (hour != 0) {
      detected = .hour;
    }
    if (minute != 0) {
      detected = .minute;
    }
    if (second != 0) {
      detected = .second;
    }
    return detected;
  }

  /// Retorna a data e hora do início da unidade de tempo especificada.
  ///
  /// Por exemplo, se a unidade for [TimeUnit.day], a função retornará a data
  /// e hora do início do dia (DD/MM/YYYY 00:00:00.000).
  /// Se a unidade for [TimeUnit.second], retornará a data e hora do início do
  /// segundo (DD/MM/YYYY HH:MM:SS.000).
  DateTime startOf(TimeUnit unit) {
    switch (unit) {
      case TimeUnit.second:
        return DateTime(year, month, day, hour, minute, second);
      case TimeUnit.minute:
        return DateTime(year, month, day, hour, minute);
      case TimeUnit.hour:
        return DateTime(year, month, day, hour);
      case TimeUnit.day:
        return DateTime(year, month, day);
      case TimeUnit.week:
        final weekday = this.weekday;
        return DateTime(year, month, day).subtract(Duration(days: weekday - 1));
      case TimeUnit.month:
        return DateTime(year, month);
      case TimeUnit.year:
        return DateTime(year);
    }
  }

  /// Retorna a data e hora do final da unidade de tempo especificada.
  ///
  /// Por exemplo, se a unidade for [TimeUnit.day], a função retornará a data
  /// e hora do final do dia (DD/MM/YYYY 23:59:59.999).
  /// Se a unidade for [TimeUnit.second], retornará a data e hora do final do
  /// segundo (DD/MM/YYYY HH:MM:SS.999).
  DateTime endOf(TimeUnit unit) {
    switch (unit) {
      case TimeUnit.second:
        return DateTime(year, month, day, hour, minute, second, 999);
      case TimeUnit.minute:
        return DateTime(year, month, day, hour, minute, 59, 999);
      case TimeUnit.hour:
        return DateTime(year, month, day, hour, 59, 59, 999);
      case TimeUnit.day:
        return DateTime(year, month, day, 23, 59, 59, 999);
      case TimeUnit.week:
        final weekday = this.weekday;
        final diffToEndOfWeek = 7 - weekday;
        return DateTime(
          year,
          month,
          day,
        ).add(Duration(days: diffToEndOfWeek)).endOf(TimeUnit.day);
      case TimeUnit.month:
        return DateTime(
          year,
          month + 1,
        ).subtract(const Duration(days: 1)).endOf(TimeUnit.day);
      case TimeUnit.year:
        return DateTime(
          year + 1,
        ).subtract(const Duration(days: 1)).endOf(TimeUnit.month);
    }
  }

  /// Mesmo que [add], mas com suporte ao [TimeUnit]
  DateTime addUnit(TimeUnit unit, int quantity) => switch (unit) {
    TimeUnit.second => add(Duration(seconds: quantity)),
    TimeUnit.minute => add(Duration(minutes: quantity)),
    TimeUnit.hour => add(Duration(hours: quantity)),
    TimeUnit.day => add(Duration(days: quantity)),
    TimeUnit.week => add(Duration(days: quantity * 7)),
    TimeUnit.month => DateTime(
      year,
      month + quantity,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    ),
    TimeUnit.year => DateTime(
      year + quantity,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    ),
  };

  /// Mesmo que [subtract], mas com suporte ao [TimeUnit]
  DateTime subtractUnit(TimeUnit unit, int quantity) => switch (unit) {
    TimeUnit.second => subtract(Duration(seconds: quantity)),
    TimeUnit.minute => subtract(Duration(minutes: quantity)),
    TimeUnit.hour => subtract(Duration(hours: quantity)),
    TimeUnit.day => subtract(Duration(days: quantity)),
    TimeUnit.week => subtract(Duration(days: quantity * 7)),
    TimeUnit.month => DateTime(
      year,
      month - quantity,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    ),
    TimeUnit.year => DateTime(
      year - quantity,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    ),
  };

  /// Compara se dois [DateTime] são iguais até a [unit] passada.
  ///
  /// A comparação por [TimeUnit.week] é igual a uma comparação por mês.
  bool isSameMomentAs(DateTime other, {TimeUnit unit = TimeUnit.second}) {
    switch (unit) {
      case TimeUnit.second:
        return year == other.year &&
            month == other.month &&
            day == other.day &&
            hour == other.hour &&
            minute == other.minute &&
            second == other.second;
      case TimeUnit.minute:
        return year == other.year &&
            month == other.month &&
            day == other.day &&
            hour == other.hour &&
            minute == other.minute;
      case TimeUnit.hour:
        return year == other.year && month == other.month && day == other.day && hour == other.hour;
      case TimeUnit.day:
        return year == other.year && month == other.month && day == other.day;
      // Comparação por semana não faz muito sentido
      case TimeUnit.week:
      case TimeUnit.month:
        return year == other.year && month == other.month;
      case TimeUnit.year:
        return year == other.year;
    }
  }
}