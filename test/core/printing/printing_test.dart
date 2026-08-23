import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/printing/esc_pos_encoder.dart';
import 'package:systock/core/printing/pdf_receipt_printer.dart';
import 'package:systock/core/printing/receipt.dart';

void main() {
  final receipt = Receipt(
    company: 'Loja',
    documentNumber: 'VEN-1',
    issuedAt: DateTime.utc(2026),
    lines: const [
      ReceiptLine(
        description: 'Arroz',
        quantityMilli: 1000,
        unitPriceMinor: 10000,
        totalMinor: 10000,
      ),
    ],
    subtotalMinor: 10000,
    discountMinor: 0,
    totalMinor: 10000,
    payments: const {'Dinheiro': 10000},
  );
  test('generates valid PDF', () async {
    final bytes = await buildReceiptPdf(receipt);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
  test('ESC/POS initializes and cuts paper', () {
    final bytes = const EscPosEncoder().encode(receipt);
    expect(bytes.take(2), [0x1b, 0x40]);
    expect(bytes.skip(bytes.length - 3), [0x1d, 0x56, 1]);
  });
}
