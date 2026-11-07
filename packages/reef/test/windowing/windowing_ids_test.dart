import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

void main() {
  test('ids generate unique uuid v7 strings and compare by value', () {
    expect({for (var i = 0; i < 100; i++) ShellId.generate().id}.length, 100);
    expect({for (var i = 0; i < 100; i++) TabId.generate().id}.length, 100);
    expect({for (var i = 0; i < 100; i++) WindowId.generate().id}.length, 100);
    expect(ShellId.generate().id[14], '7', reason: 'uuid version nibble');
    expect(TabId.generate().id[14], '7');
    expect(WindowId.generate().id[14], '7');
    expect(ShellId.manual('s'), ShellId.manual('s'));
    expect(TabId.manual('t').id, 't');
    expect(WindowId.manual('w'), isNot(WindowId.manual('x')));
  });
}
