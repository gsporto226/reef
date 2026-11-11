import 'dart:convert';
import 'dart:io';

import 'package:reef/reef.dart';

/// A [HibernationStore] kept in one JSON file, keyed by buffer id. [load]
/// reads the file once, before the first frame, so the synchronous interface
/// never waits on disk; every save and delete rewrites the file.
// ponytail: rewrites the whole file on each change; debounce if it grows.
class JsonFileHibernationStore implements HibernationStore {
  JsonFileHibernationStore._(this._file, this._json);

  /// The store saved in [file]; empty when the file is missing or unreadable.
  factory JsonFileHibernationStore.load(File file) {
    var json = <String, dynamic>{};
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on Object {
      // A missing or unreadable file starts the app on its first-run layout.
    }
    return JsonFileHibernationStore._(file, json);
  }

  final File _file;
  final Map<String, dynamic> _json;

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
