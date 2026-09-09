/// Helpers [Duration]
class Durations {
  const Durations._();

  /// Lê uma duration de uma string formatada 'HH:MM:SS[.mmmmmm]'
  static Duration fromString(String input) {
    // 1. separa microssegundos
    final dotSplit = input.split('.');
    final timePart = dotSplit[0];
    final microseconds = dotSplit.length == 2 ? int.parse(dotSplit[1].padRight(6, '0')) : 0;

    // 2. separa H:MM:SS
    final hms = timePart.split(':');
    if (hms.length != 3) {
      throw FormatException('Invalid duration format: $input');
    }

    final hours = int.parse(hms[0]);
    final minutes = int.parse(hms[1]);
    final seconds = int.parse(hms[2]);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      microseconds: microseconds,
    );
  }
}