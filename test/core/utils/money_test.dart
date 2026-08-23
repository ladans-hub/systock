import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/utils/money.dart';

void main() {
  test('localized money is parsed exactly into minor units', () {
    expect(parseMoneyMinor('1 250,50 MT'), 125050);
    expect(parseMoneyMinor('1250.05'), 125005);
    expect(parseMoneyMinor('-10,01'), -1001);
  });
  test('formats metical with decimal comma and grouped thousands', () {
    expect(formatMoneyMinor(100), '1,00 MT');
    expect(formatMoneyMinor(100000), '1.000,00 MT');
    expect(formatMoneyMinor(-125050), '-1.250,50 MT');
  });
}
