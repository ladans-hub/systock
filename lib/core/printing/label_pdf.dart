import 'dart:typed_data';
import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildProductLabels({
  required String name,
  required String barcode,
  required int priceMinor,
  int copies = 1,
  double widthMm = 50,
  double heightMm = 30,
}) async {
  if (copies < 1 || copies > 500) throw ArgumentError.value(copies, 'copies');
  final document = pw.Document();
  final format = PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginAll: 2 * PdfPageFormat.mm,
  );
  final symbology = _symbology(barcode);
  for (var i = 0; i < copies; i++) {
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              name,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${priceMinor ~/ 100},${(priceMinor.abs() % 100).toString().padLeft(2, '0')} MT',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.BarcodeWidget(
              barcode: symbology,
              data: barcode,
              width: format.availableWidth,
              height: 9 * PdfPageFormat.mm,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 6),
            ),
          ],
        ),
      ),
    );
  }
  return document.save();
}

bc.Barcode _symbology(String value) {
  if (RegExp(r'^\d{13}$').hasMatch(value)) return bc.Barcode.ean13();
  if (RegExp(r'^\d{8}$').hasMatch(value)) return bc.Barcode.ean8();
  return bc.Barcode.code128();
}
