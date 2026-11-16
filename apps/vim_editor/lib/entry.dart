// The vim editor's entrypoint, outside the coverage gate (ADR 0014).
// `flutter run -t lib/entry.dart`.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vim_editor/vim.dart';

import 'main.dart';

void main() => runApp(VimApp(Vim(ProviderContainer())));
