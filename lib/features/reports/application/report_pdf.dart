import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/core/utils/money.dart';

Future<Uint8List> buildStockReportPdf(
  List<StockReportRow> rows,
  String company,
) async {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      header: (_) => pw.Text(
        '$company · Relatório de stock',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: const ['Produto', 'SKU', 'Armazém', 'Qtd.', 'Valor'],
          data: [
            for (final row in rows)
              [
                row.name,
                row.sku ?? '',
                row.warehouse,
                (row.quantityMilli / 1000).toStringAsFixed(3),
                formatMoneyMinor(row.valueMinor),
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
  DateTime to,
) async {
  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$company · Relatório de vendas',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Período: ${date(from)} a ${date(to.subtract(const Duration(days: 1)))}',
          ),
        ],
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: const ['Data', 'Documento', 'Estado', 'Total'],
          data: [
            for (final row in rows)
              [
                date(row.createdAt.toLocal()),
                row.documentNumber,
                row.status,
                formatMoneyMinor(row.totalMinor),
              ],
          ],
        ),
      ],
    ),
  );
  return document.save();
}
