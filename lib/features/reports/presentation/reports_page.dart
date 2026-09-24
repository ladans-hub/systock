import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/features/reports/application/report_service.dart';
import 'package:systock/features/reports/application/report_pdf.dart';
import 'package:systock/core/widgets/async_state_pane.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/files/file_save_service.dart';
import 'package:systock/core/files/selected_file_writer.dart';
import 'package:systock/features/customers/application/debt_service.dart';
import 'dart:io';
import 'package:flutter/services.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int days = 30;
  bool generatingPdf = false;

  Future<void> _exportPdf({
    required List<SalesReportRow> rows,
    required Company company,
    required DateTime from,
    required DateTime to,
    required SalesKpis kpis,
    required DebtSummary debts,
    required String locale,
    required String currency,
  }) async {
    if (generatingPdf) return;
    setState(() => generatingPdf = true);
    try {
      final watermark = await _watermarkBytes(company.logoPath);
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await buildSalesReportPdf(
        rows,
        company.tradeName,
        from,
        to,
        kpis: kpis,
        debts: debts,
        locale: locale,
        currency: currency,
        watermark: watermark,
      );
      if (!mounted) return;
      await _saveReport(
        bytes: bytes,
        extension: 'pdf',
        mimeType: 'application/pdf',
      );
    } catch (error, stackTrace) {
      debugPrint('Falha ao gerar relatório PDF: $error\n$stackTrace');
      if (!mounted) return;
      await showAppError(
        context,
        'Não foi possível gerar o relatório PDF. Tente novamente.',
      );
    } finally {
      if (mounted) setState(() => generatingPdf = false);
    }
  }

  Future<void> _saveReport({
    required List<int> bytes,
    required String extension,
    required String mimeType,
  }) async {
    try {
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final english = Localizations.localeOf(context).languageCode == 'en';
      final saved = await const FileSaveService().save(
        dialogTitle: english
            ? 'Save sales report'
            : 'Guardar relatório de vendas',
        fileName: english
            ? 'sales-report-$days-days-$date.$extension'
            : 'relatorio-vendas-$days-dias-$date.$extension',
        bytes: bytes,
        mimeType: mimeType,
      );
      if (!mounted) return;
      if (saved case Failure(:final error)) {
        await showAppFailure(context, error);
        return;
      }
      final uri = (saved as Success<Uri?>).value;
      if (uri == null) return;
      final location = uri.scheme == 'file'
          ? uri.toFilePath()
          : uri.scheme.isEmpty
          ? uri.path
          : uri.toString();
      // Some desktop file-picker versions return the selected path without
      // writing the supplied bytes. Ensure the exported document is persisted.
      if (uri.scheme == 'file' || uri.scheme.isEmpty) {
        await writeSelectedFile(location, bytes);
      }
      if (!mounted) return;
      await showAppAlert(context, 'Relatório guardado em $location');
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
      DebtSummary debts,
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
      debts: await DebtService(db).summary(company.id),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AppBarTitle('Relatórios'),
      actions: [
        DropdownButton<int>(
          value: days,
          items: const [1, 7, 30, 90, 180, 365]
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: LocalizedText(d == 1 ? 'Hoje' : '$d dias'),
                ),
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
        final locale = Localizations.localeOf(context).languageCode;
        final text = SalesReportText(locale, c);
        String date(DateTime value) =>
            '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 4
                    : constraints.maxWidth >= 500
                    ? 2
                    : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent:
                      150 * MediaQuery.textScalerOf(context).scale(14) / 14,
                  children: [
                    _Kpi('Receita', d.kpis.revenueMinor, c),
                    _Kpi('Custo dos produtos vendidos', d.kpis.costMinor, c),
                    _Kpi('Lucro bruto', d.kpis.grossProfitMinor, c),
                    _Kpi('Valor médio por venda', d.kpis.averageTicketMinor, c),
                    _Kpi('Valor liquidado', d.debts.paidMinor, c),
                    _Kpi('Saldo a receber', d.debts.outstandingMinor, c),
                  ],
                );
              },
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
                    text.english
                        ? 'Sales in period (${d.sales.map((r) => r.documentNumber).toSet().length})'
                        : 'Vendas no período (${d.sales.map((r) => r.documentNumber).toSet().length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final csv = ReportService(ref.read(databaseProvider))
                              .salesCsv(
                                d.sales,
                                from: d.from,
                                to: d.to,
                                locale: locale,
                                currency: c,
                              );
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
                          final bytes =
                              ReportService(
                                ref.read(databaseProvider),
                              ).salesXlsx(
                                d.sales,
                                from: d.from,
                                to: d.to,
                                locale: locale,
                                currency: c,
                              );
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
                        onPressed: generatingPdf
                            ? null
                            : () => _exportPdf(
                                rows: d.sales,
                                company: d.company,
                                from: d.from,
                                to: d.to,
                                kpis: d.kpis,
                                debts: d.debts,
                                locale: locale,
                                currency: c,
                              ),
                        icon: generatingPdf
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: LocalizedText(
                          generatingPdf ? 'A gerar PDF...' : 'PDF',
                        ),
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
                  columns: [
                    for (var i = 0; i < text.headers.length; i++)
                      DataColumn(label: Text(text.headers[i]), numeric: i >= 4),
                  ],
                  rows: d.sales
                      .take(200)
                      .map(
                        (row) => DataRow(
                          cells: text
                              .cells(row)
                              .map((value) => DataCell(Text(value)))
                              .toList(),
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

  Future<Uint8List> _watermarkBytes(String? path) async {
    if (path != null) {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    }
    final data = await rootBundle.load(
      'assets/branding/systock_logo_transparent.png',
    );
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.minor, this.currency);
  final String label, currency;
  final int minor;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(label),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoneyMinor(
                minor,
                symbol: currency == 'MZN' ? 'MT' : currency,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    ),
  );
}
