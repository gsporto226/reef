// The mail client's entrypoint, outside the coverage gate (ADR 0014).
// `flutter run -t lib/entry.dart`.
import 'package:flutter/widgets.dart';
import 'package:reef/reef.dart';

import 'main.dart';

void main() => runApp(MailApp(store: InMemoryHibernationStore()));
