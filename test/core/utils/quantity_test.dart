import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/utils/quantity.dart';

void main() {
  test('quantities parse exactly in grams with comma or dot', () {
    expect(parseQuantityMilli('0,5'), 500);
    expect(parseQuantityMilli('0.001'), 1);
    expect(parseQuantityMilli('50.125'), 50125);
    expect(parseQuantityMilli('0'), 0);
    expect(formatQuantity(49500), '49,5');
    expect(formatQuantity(1), '0,001');
    expect(formatQuantity(50000), '50');
  });
  test(
    'reject invalid quantities and excess precision instead of rounding',
    () {
      for (final input in [
        '-1',
        'NaN',
        'Infinity',
        '1e3',
        '0.0001',
        '1,2.3',
        '',
      ]) {
        expect(() => parseQuantityMilli(input), throwsFormatException);
      }
      expect(
        () => parseQuantityMilli('0.5', decimalPlaces: 0),
        throwsFormatException,
      );
      expect(parseQuantityMilli('2', decimalPlaces: 0), 2000);
    },
  );
}
