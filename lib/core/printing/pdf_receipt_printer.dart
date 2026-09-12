import 'dart:typed_data';
import 'package:systock/core/utils/quantity.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:systock/core/utils/money.dart';
import 'package:printing/printing.dart';
import 'package:systock/core/printing/receipt.dart';

String _money(int minor) => formatMoneyMinor(minor);
Future<Uint8List> buildReceiptPdf(
  Receipt receipt, {
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      build: (_) => [
        pw.Center(
          child: pw.Text(
            receipt.company,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (receipt.taxId != null)
          pw.Center(child: pw.Text('NUIT ${receipt.taxId}')),
        if (receipt.address != null)
          pw.Center(child: pw.Text(receipt.address!)),
        pw.Divider(),
        ...receipt.lines.map(
          (l) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(l.description)),
              pw.Text(
                '${formatQuantity(l.quantityMilli)} × ${_money(l.unitPriceMinor)}',
              ),
              pw.SizedBox(width: 12),
              pw.Text(_money(l.totalMinor)),
            ],
          ),
        ),
        pw.Divider(),
        _total('Subtotal', receipt.subtotalMinor),
        _total('Desconto', receipt.discountMinor),
        _total('TOTAL', receipt.totalMinor, bold: true),
        pw.Divider(),
        ...receipt.payments.entries.map((p) => _total(p.key, p.value)),
        pw.SizedBox(height: 12),
        pw.Text('${receipt.documentNumber} - ${receipt.issuedAt.toLocal()}'),
        pw.SizedBox(height: 8),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: receipt.documentNumber,
          width: 42,
          height: 42,
        ),
        if (receipt.footer != null) pw.Center(child: pw.Text(receipt.footer!)),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _total(String label, int value, {bool bold = false}) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      label,
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
    pw.Text(
      _money(value),
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
  ],
);

class SystemReceiptPrinter implements ReceiptPrinter {
  @override
  Future<PrintResult> print(Receipt receipt) async {
    try {
      final bytes = await buildReceiptPdf(receipt);
      final ok = await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: receipt.documentNumber,
      );
      return ok
          ? const PrintSuccess()
          : const PrintFailure('A impressão foi cancelada.');
    } catch (e) {
      return PrintFailure('Não foi possível imprimir o recibo.', e);
    }
  }
}
