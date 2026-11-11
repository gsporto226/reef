import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/json_file_hibernation_store.dart';
import 'package:reef_example/main.dart' show exampleStore;

const _task = BufferId.manual('task-edit:Buy milk');
const _layout = BufferId.manual('windowing:');

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('reef_store_test');
    file = File('${dir.path}/nested/store.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a store loaded from the same file sees what the last one saved', () {
    JsonFileHibernationStore.load(file)
      ..save(_task, {'title': 'Buy bread'})
      ..save(_layout, {'version': 1})
      ..delete(_layout);

    final reopened = JsonFileHibernationStore.load(file);
    expect(reopened.load(_task), {'title': 'Buy bread'});
    expect(reopened.load(_layout), isNull);
  });

  test('a missing or unreadable file loads as an empty store', () {
    expect(JsonFileHibernationStore.load(file).load(_task), isNull);

    file
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');
    expect(JsonFileHibernationStore.load(file).load(_task), isNull);

    file.writeAsStringSync('{"task-edit:Buy milk": 3}');
    expect(JsonFileHibernationStore.load(file).load(_task), isNull);
  });

  test('desktop keeps the file store, web and tests the in-memory one', () {
    expect(exampleStore(desktop: false), isA<InMemoryHibernationStore>());
    expect(exampleStore(desktop: true, directory: dir),
        isA<JsonFileHibernationStore>());
  });
}
