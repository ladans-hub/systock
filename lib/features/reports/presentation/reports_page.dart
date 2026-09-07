import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart' as picker;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/features/reports/application/report_pdf.dart';
import 'package:systock/core/widgets/async_state_pane.dart';
import 'package:systock/core/utils/money.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int days = 30;

  Future<void> _saveReport({
    required List<int> bytes,
    required String extension,
    required String mimeType,
  }) async {
    try {
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final uri = await picker.FilePicker.saveFile(
        dialogTitle: 'Guardar relatório de vendas',
        fileName: 'relatorio-vendas-$days-dias-$date.$extension',
        bytes: Uint8List.fromList(bytes),
        mimeType: mimeType,
      );
      if (!mounted || uri == null) return;
      final location = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('Relatório guardado em $location')),
      );
    } catch (error, stackTrace) {
      debugPrint('Falha ao guardar relatório: $error\n$stackTrace');
      if (!mounted) return;
      showAppError(context, 'Não foi possível guardar o relatório.');
    }
  }

  Future<
    ({
      Company company,
      SalesKpis kpis,
      List<StockReportRow> stock,
      List<SalesReportRow> sales,
      DateTime from,
      DateTime to,
    })
  >
  load(AppDatabase db) async {
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc(),
        service = ReportService(db);
    final today = DateTime.utc(now.year, now.month, now.day);
    final from = today.subtract(Duration(days: days - 1));
    final to = today.add(const Duration(days: 1));
    return (
      company: company,
      kpis: await service.salesKpis(company.id, from, to),
      stock: await service.stock(company.id),
      sales: await service.sales(company.id, from, to),
      from: from,
      to: to,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Relatórios'),
      actions: [
        DropdownButton<int>(
          value: days,
          items: const [7, 30, 90, 180, 365]
              .map(
                (d) =>
                    DropdownMenuItem(value: d, child: LocalizedText('$d dias')),
              )
              .toList(),
          onChanged: (v) => setState(() => days = v!),
        ),
        const SizedBox(width: 16),
      ],
    ),
    body: FutureBuilder(
      future: load(ref.watch(databaseProvider)),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AsyncErrorPane(onRetry: () => setState(() {}));
        }
        if (!snapshot.hasData) {
          return const AsyncLoadingPane();
        }
        final d = snapshot.data!, c = d.company.currencyCode;
        String date(DateTime value) =>
            '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Kpi('Receita', d.kpis.revenueMinor, c),
                _Kpi('Custo dos produtos vendidos', d.kpis.costMinor, c),
                _Kpi('Lucro bruto', d.kpis.grossProfitMinor, c),
                _Kpi('Valor médio por venda', d.kpis.averageTicketMinor, c),
              ],
            ),
            const SizedBox(height: 12),
            LocalizedText(
              'Período do relatório: ${date(d.from.toLocal())} a ${date(d.to.subtract(const Duration(days: 1)).toLocal())}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    'Vendas no período (${d.sales.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final csv = ReportService(
                            ref.read(databaseProvider),
                          ).salesCsv(d.sales, from: d.from, to: d.to);
                          await _saveReport(
                            bytes: [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)],
                            extension: 'csv',
                            mimeType: 'text/csv',
                          );
                        },
                        icon: const Icon(Icons.table_view),
                        label: const LocalizedText('Exportar CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final bytes = ReportService(
                            ref.read(databaseProvider),
                          ).salesXlsx(d.sales, from: d.from, to: d.to);
                          await _saveReport(
                            bytes: bytes,
                            extension: 'xlsx',
                            mimeType:
                                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                          );
                        },
                        icon: const Icon(Icons.grid_on),
                        label: const LocalizedText('XLSX'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final bytes = await buildSalesReportPdf(
                            d.sales,
                            d.company.tradeName,
                            d.from,
                            d.to,
                          );
                          await _saveReport(
                            bytes: bytes,
                            extension: 'pdf',
                            mimeType: 'application/pdf',
                          );
                        },
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const LocalizedText('PDF'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: LocalizedText('Data')),
                    DataColumn(label: LocalizedText('Documento')),
                    DataColumn(label: LocalizedText('Estado')),
                    DataColumn(label: LocalizedText('Total'), numeric: true),
                  ],
                  rows: d.sales
                      .take(200)
                      .map(
                        (r) => DataRow(
                          cells: [
                            DataCell(Text(date(r.createdAt.toLocal()))),
                            DataCell(Text(r.documentNumber)),
                            DataCell(Text(r.status)),
                            DataCell(
                              Text(
                                formatMoneyMinor(
                                  r.totalMinor,
                                  symbol: c == 'MZN' ? 'MT' : c,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            LocalizedText(
              'Posição actual do stock',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            LocalizedText(
              '${d.stock.length} produtos/armazéns com saldo registado.',
            ),
          ],
        );
      },
    ),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.minor, this.currency);
  final String label, currency;
  final int minor;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(
              formatMoneyMinor(
                minor,
                symbol: currency == 'MZN' ? 'MT' : currency,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );
}
