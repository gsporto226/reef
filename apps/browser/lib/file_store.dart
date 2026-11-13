import 'dart:convert';
import 'dart:io';

import 'package:reef/reef.dart';

/// A [HibernationStore] kept in one JSON file, keyed by buffer id. The file
/// is read once, before the first frame, so the synchronous interface never
/// waits on disk; every save and delete rewrites it.
// ponytail: rewrites the whole file on each change; debounce if it grows.
class JsonFileHibernationStore implements HibernationStore {
  JsonFileHibernationStore(this._file) {
    try {
      _json.addAll(
        jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on Object {
      // Missing or unreadable: a first run.
    }
  }

  final File _file;
  final _json = <String, dynamic>{};

  @override
  Map<String, dynamic>? load(BufferId bufferId) => switch (_json[bufferId.id]) {
    final Map<String, dynamic> json => json,
    _ => null,
  };

  @override
  void save(BufferId bufferId, Map<String, dynamic> json) {
    _json[bufferId.id] = json;
    _write();
  }

  @override
  void delete(BufferId bufferId) {
    _json.remove(bufferId.id);
    _write();
  }

  void _write() => _file
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(_json));
}

/// The session file under the app's support directory (`%APPDATA%`; the
/// browser runs on Windows only).
File sessionFile() => File(
  '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}'
  r'\reef\browser\session.json',
);
