import 'package:flutter_test/flutter_test.dart';
import 'package:canting/core/models/local_food.dart';

void main() {
  test('explicit platform sugar wording maps to existing enums', () {
    expect(OrderSpec.parse('青青糯山三分糖大杯').sugar, 'low');
    expect(OrderSpec.parse('奶茶正常糖小杯').sugar, 'regular');
    expect(OrderSpec.parse('奶茶不另外加糖').sugar, 'unknown');
    expect(OrderSpec.parse('奶茶无糖正常糖').sugar, 'unknown');
    expect(OrderSpec.productName('奶茶三分糖大杯'), '奶茶');
  });
}
