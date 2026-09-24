import 'package:pdf/pdf.dart';
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/features/customers/application/debt_service.dart';
import 'package:systock/features/reports/application/pdf_watermark.dart';

Future<Uint8List> buildStockReportPdf(
  List<StockReportRow> rows,
  String company, {
  String locale = 'pt',
  required Uint8List watermark,
}) async {
  final text = SalesReportText(locale);
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageTheme: pw.PageTheme(
        buildBackground: (_) => pdfPageBackground(watermark),
      ),
      header: (_) => pw.Text(
        '$company · ${text.english ? 'Stock report' : 'Relatório de stock'}',
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      footer: (_) => _reportFooter(text),
      build: (_) => [
        for (final chunk in _chunks(rows, 32)) ...[
          _stockTable(chunk, text, locale),
          if (chunk.lastOrNull != rows.lastOrNull) pw.NewPage(),
        ],
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
  required SalesKpis kpis,
  required DebtSummary debts,
  String locale = 'pt',
  String currency = 'MZN',
  required Uint8List watermark,
}) async {
  final text = SalesReportText(locale, currency);
  final document = pw.Document();
  final oneDay = to.difference(from).inDays == 1;
  String money(int value) => formatMoneyMinor(
    value,
    locale: locale,
    symbol: currency == 'MZN' ? 'MT' : currency,
  );
  final metrics = [
    (
      text.english ? 'Total sales' : 'Total de vendas',
      money(kpis.revenueMinor),
    ),
    (
      text.english ? 'Cost of goods sold' : 'Custo dos produtos vendidos',
      money(kpis.costMinor),
    ),
    (
      text.english ? 'Gross profit' : 'Lucro bruto',
      money(kpis.grossProfitMinor),
    ),
    (
      text.english ? 'Profit margin' : 'Margem de lucro',
      '${(kpis.margin * 100).toStringAsFixed(1)}%',
    ),
    (
      text.english ? 'Number of sales' : 'Número de vendas',
      '${kpis.saleCount}',
    ),
    (
      text.english ? 'Average sale value' : 'Valor médio por venda',
      money(kpis.averageTicketMinor),
    ),
    (text.english ? 'Debt paid' : 'Valor liquidado', money(debts.paidMinor)),
    (
      text.english ? 'Accounts receivable' : 'Saldo a receber',
      money(debts.outstandingMinor),
    ),
  ];
  document.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        buildBackground: (_) => pdfPageBackground(watermark),
      ),
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
              oneDay
                  ? '${text.period}: ${text.english ? 'Today' : 'Hoje'} (${text.date(from)})'
                  : '${text.period}: ${text.date(from)} ${text.english ? 'to' : 'a'} ${text.date(to.subtract(const Duration(days: 1)))}',
            ),
          ],
        ),
      ),
      footer: (_) => _reportFooter(text),
      build: (_) => [
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              pw.Container(
                width: 225,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      metric.$1,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      metric.$2,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 18),
        if (rows.isEmpty)
          pw.Text(
            text.english
                ? 'No sales were found in this period.'
                : 'Nenhuma venda encontrada neste período.',
          )
        else
          for (final chunk in _chunks(rows, 28)) ...[
            _salesTable(chunk, text),
            if (chunk.lastOrNull != rows.lastOrNull) pw.NewPage(),
          ],
      ],
    ),
  );
  return document.save();
}

List<List<T>> _chunks<T>(List<T> values, int size) => [
  for (var start = 0; start < values.length; start += size)
    values.sublist(start, (start + size).clamp(0, values.length)),
];

pw.Widget _stockTable(
  List<StockReportRow> rows,
  SalesReportText text,
  String locale,
) => pw.TableHelper.fromTextArray(
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
  headerAlignment: pw.Alignment.centerLeft,
  cellAlignment: pw.Alignment.centerLeft,
);

pw.Widget _salesTable(List<SalesReportRow> rows, SalesReportText text) =>
    pw.TableHelper.fromTextArray(
      headers: text.headers,
      data: rows.map(text.cells).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.all(7),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      border: null,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.3),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(.7),
        5: const pw.FlexColumnWidth(1.2),
      },
    );

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
