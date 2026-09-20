import 'package:pdf/pdf.dart';
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/core/utils/money.dart';

Future<Uint8List> buildStockReportPdf(
  List<StockReportRow> rows,
  String company, {
  String locale = 'pt',
}) async {
  final text = SalesReportText(locale);
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      header: (_) => pw.Text(
        '$company · ${text.english ? 'Stock report' : 'Relatório de stock'}',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      footer: (_) => _reportFooter(text),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: text.english
              ? ['Product', 'Warehouse', 'Qty.', 'Value']
              : ['Produto', 'Armazém', 'Qtde.', 'Valor'],
          data: [
            for (final row in rows)
              [
                row.name,
                row.warehouse,
                text.quantity(row.quantityMilli),
                formatMoneyMinor(row.valueMinor, locale: locale),
              ],
          ],
        ),
      ],
    ),
  );
  return document.save();
}

Future<Uint8List> buildSalesReportPdf(
  List<SalesReportRow> rows,
  String company,
  DateTime from,
  DateTime to, {
  String locale = 'pt',
  String currency = 'MZN',
}) async {
  final text = SalesReportText(locale, currency);
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              company,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(text.title, style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 4),
            pw.Text(
              '${text.period}: ${text.date(from)} ${text.english ? 'to' : 'a'} ${text.date(to.subtract(const Duration(days: 1)))}',
            ),
          ],
        ),
      ),
      footer: (_) => _reportFooter(text),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: text.headers,
          data: rows.map(text.cells).toList(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey800,
          ),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(7),
          border: null,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(2.5),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FlexColumnWidth(.7),
            5: const pw.FlexColumnWidth(1.2),
          },
          cellAlignments: {
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
        ),
      ],
    ),
  );
  return document.save();
}

pw.Widget _reportFooter(SalesReportText text) => pw.Column(
  mainAxisSize: pw.MainAxisSize.min,
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(height: 12),
    pw.Divider(color: PdfColors.grey300, thickness: .5),
    pw.SizedBox(height: 4),
    pw.Text(
      text.footer,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
    ),
  ],
);
