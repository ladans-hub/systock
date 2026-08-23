import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/scanner/barcode_keyboard_decoder.dart';

void main() {
  test('fast HID sequence ending in enter emits barcode', () {
    final d = BarcodeKeyboardDecoder();
    final start = DateTime.utc(2026);
    String? value;
    for (var i = 0; i < '5601234'.length; i++) {
      value = d.add('5601234'[i], start.add(Duration(milliseconds: i * 10)));
    }
    value = d.add('\n', start.add(const Duration(milliseconds: 80)));
    expect(value, '5601234');
  });
  test('slow typing is not interpreted as scanner input', () {
    final d = BarcodeKeyboardDecoder();
    final t = DateTime.utc(2026);
    d.add('1', t);
    d.add('2', t.add(const Duration(seconds: 1)));
    expect(d.add('\n', t.add(const Duration(milliseconds: 1010))), isNull);
  });
}
