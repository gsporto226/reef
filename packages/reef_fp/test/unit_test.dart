import 'package:reef_fp/unit.dart';
import 'package:test/test.dart';

void main() {
  test('unit is a single value', () {
    expect(Unit.unit, Unit.unit);
    expect(const Unit(), Unit.unit);
    expect(Unit.unit.toString(), 'unit');
  });
}
