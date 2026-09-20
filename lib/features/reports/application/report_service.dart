import 'package:systock/core/utils/money.dart';
import 'package:systock/core/utils/quantity.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:excel_community/excel_community.dart';

class SalesKpis {
  const SalesKpis({
    required this.revenueMinor,
    required this.costMinor,
    required this.saleCount,
    required this.unitsMilli,
  });
  final int revenueMinor, costMinor, saleCount, unitsMilli;
  int get grossProfitMinor => revenueMinor - costMinor;
  double get margin => revenueMinor == 0 ? 0 : grossProfitMinor / revenueMinor;
  int get averageTicketMinor => saleCount == 0 ? 0 : revenueMinor ~/ saleCount;
}

class StockReportRow {
  const StockReportRow(
    this.name,
    this.warehouse,
    this.quantityMilli,
    this.valueMinor,
  );
  final String name, warehouse;
  final int quantityMilli, valueMinor;
}

class SalesReportRow {
  const SalesReportRow(
    this.documentNumber,
    this.createdAt,
    this.status,
    this.totalMinor, {
    this.product = '',
    this.quantityMilli = 0,
  });
  final String product;
  final int quantityMilli;
  final String documentNumber, status;
  final DateTime createdAt;
  final int totalMinor;
}

class ProductSalesRanking {
  const ProductSalesRanking(
    this.productId,
    this.name,
    this.quantityMilli,
    this.revenueMinor,
  );
  final String productId, name;
  final int quantityMilli, revenueMinor;
}

class PeriodOperationalTotals {
  const PeriodOperationalTotals({
    required this.cashInMinor,
    required this.cashOutMinor,
    required this.stockInMilli,
    required this.stockOutMilli,
  });
  final int cashInMinor, cashOutMinor, stockInMilli, stockOutMilli;
  int get cashNetMinor => cashInMinor - cashOutMinor;
}

class RevenueSeries {
  const RevenueSeries(this.values, this.bucketDays);
  final List<int> values;
  final int bucketDays;
}

class ReportService {
  const ReportService(this._db);
  final AppDatabase _db;

  Future<List<int>> dailyRevenue(String companyId, {int days = 7}) async {
    final today = DateTime.now().toUtc();
    final start = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days - 1));
    final sales =
        await (_db.select(_db.sales)
              ..where((s) => s.companyId.equals(companyId))
              ..where((s) => s.status.isIn(['paid', 'completed']))
              ..where((s) => s.createdAt.isBiggerOrEqualValue(start)))
            .get();
    final totals = List<int>.filled(days, 0);
    for (final sale in sales) {
      final date = sale.createdAt.toUtc();
      final day = DateTime.utc(date.year, date.month, date.day);
      final index = day.difference(start).inDays;
      if (index >= 0 && index < days) totals[index] += sale.totalMinor;
    }
    return totals;
  }

  Future<RevenueSeries> revenueSeries(
    String companyId,
    DateTime from,
    DateTime to, {
    int maximumBuckets = 24,
  }) async {
    final days = to.difference(from).inDays.clamp(1, 3660);
    final bucketDays = (days / maximumBuckets).ceil().clamp(1, days);
    final bucketCount = (days / bucketDays).ceil();
    final totals = List<int>.filled(bucketCount, 0);
    final sales =
        await (_db.select(_db.sales)
              ..where((s) => s.companyId.equals(companyId))
              ..where((s) => s.status.isIn(['paid', 'completed']))
              ..where((s) => s.createdAt.isBiggerOrEqualValue(from))
              ..where((s) => s.createdAt.isSmallerThanValue(to)))
            .get();
    for (final sale in sales) {
      final index =
          sale.createdAt.toUtc().difference(from).inDays ~/ bucketDays;
      if (index >= 0 && index < totals.length) totals[index] += sale.totalMinor;
    }
    return RevenueSeries(totals, bucketDays);
  }

  Future<SalesKpis> salesKpis(
    String companyId,
    DateTime from,
    DateTime to,
  ) async {
    final row = await _db
        .customSelect(
          '''SELECT COALESCE(SUM(total_minor),0) revenue, COALESCE(SUM(cost_minor),0) cost, COUNT(*) count FROM sales WHERE company_id=? AND status IN ('paid','completed') AND created_at>=? AND created_at<?''',
          variables: [Variable(companyId), Variable(from), Variable(to)],
        )
        .getSingle();
    final units = await _db
        .customSelect(
          '''SELECT COALESCE(SUM(si.quantity_milli),0) units FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.company_id=? AND s.status IN ('paid','completed') AND s.created_at>=? AND s.created_at<?''',
          variables: [Variable(companyId), Variable(from), Variable(to)],
        )
        .getSingle();
    return SalesKpis(
      revenueMinor: row.read<int>('revenue'),
      costMinor: row.read<int>('cost'),
      saleCount: row.read<int>('count'),
      unitsMilli: units.read<int>('units'),
    );
  }

  Future<PeriodOperationalTotals> operationalTotals(
    String companyId,
    DateTime from,
    DateTime to,
  ) async {
    final cash = await _db
        .customSelect(
          '''SELECT
        COALESCE(SUM(CASE WHEN cm.amount_minor > 0 THEN cm.amount_minor ELSE 0 END),0) cash_in,
        COALESCE(SUM(CASE WHEN cm.amount_minor < 0 THEN -cm.amount_minor ELSE 0 END),0) cash_out
      FROM cash_movements cm
      JOIN cash_sessions cs ON cs.id=cm.cash_session_id
      JOIN cash_registers cr ON cr.id=cs.cash_register_id
      WHERE cr.company_id=? AND cm.created_at>=? AND cm.created_at<?''',
          variables: [Variable(companyId), Variable(from), Variable(to)],
        )
        .getSingle();
    final stock = await _db
        .customSelect(
          '''SELECT
        COALESCE(SUM(CASE WHEN quantity_milli > 0 THEN quantity_milli ELSE 0 END),0) stock_in,
        COALESCE(SUM(CASE WHEN quantity_milli < 0 THEN -quantity_milli ELSE 0 END),0) stock_out
      FROM inventory_movements
      WHERE company_id=? AND created_at>=? AND created_at<?''',
          variables: [Variable(companyId), Variable(from), Variable(to)],
        )
        .getSingle();
    return PeriodOperationalTotals(
      cashInMinor: cash.read<int>('cash_in'),
      cashOutMinor: cash.read<int>('cash_out'),
      stockInMilli: stock.read<int>('stock_in'),
      stockOutMilli: stock.read<int>('stock_out'),
    );
  }

  Future<List<ProductSalesRanking>> productRanking(
    String companyId,
    DateTime from,
    DateTime to, {
    bool least = false,
    int limit = 5,
  }) async {
    final rows = await _db
        .customSelect(
          '''SELECT p.id,p.name,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity_milli ELSE 0 END),0) quantity,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.total_minor ELSE 0 END),0) revenue
      FROM products p
      LEFT JOIN sale_items si ON si.product_id=p.id
      LEFT JOIN sales s ON s.id=si.sale_id
        AND s.status IN ('paid','completed') AND s.created_at>=? AND s.created_at<?
      WHERE p.company_id=? AND p.deleted_at IS NULL
      GROUP BY p.id,p.name
      ORDER BY quantity ${least ? 'ASC' : 'DESC'},p.name COLLATE NOCASE
      LIMIT ?''',
          variables: [
            Variable(from),
            Variable(to),
            Variable(companyId),
            Variable(limit),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ProductSalesRanking(
          row.read<String>('id'),
          row.read<String>('name'),
          row.read<int>('quantity'),
          row.read<int>('revenue'),
        ),
    ];
  }

  Future<List<SalesReportRow>> sales(
    String companyId,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db
        .customSelect(
          '''SELECT s.document_number, s.created_at,
        CASE WHEN s.paid_minor >= s.total_minor THEN 'paid' ELSE 'unpaid' END payment_status,
        si.description product, si.quantity_milli, si.total_minor
        FROM sales s JOIN sale_items si ON si.sale_id = s.id
        WHERE s.company_id = ? AND s.deleted_at IS NULL
          AND s.status IN ('paid', 'completed', 'partially_paid', 'unpaid')
          AND s.created_at >= ? AND s.created_at < ?
        ORDER BY s.created_at DESC, s.id, si.id''',
          variables: [Variable(companyId), Variable(from), Variable(to)],
        )
        .get();
    return [
      for (final row in rows)
        SalesReportRow(
          row.read('document_number'),
          row.read('created_at'),
          row.read('payment_status'),
          row.read('total_minor'),
          product: row.read('product'),
          quantityMilli: row.read('quantity_milli'),
        ),
    ];
  }

  String salesCsv(
    List<SalesReportRow> rows, {
    required DateTime from,
    required DateTime to,
    String locale = 'pt',
    String currency = 'MZN',
  }) {
    final text = SalesReportText(locale, currency);
    return Csv.excel().encode([
      [
        text.period,
        text.date(from),
        text.date(to.subtract(const Duration(days: 1))),
      ],
      const [],
      text.headers,
      ...rows.map(text.cells),
    ]);
  }

  List<int> salesXlsx(
    List<SalesReportRow> rows, {
    required DateTime from,
    required DateTime to,
    String locale = 'pt',
    String currency = 'MZN',
  }) {
    final text = SalesReportText(locale, currency);
    final excel = Excel.createExcel(),
        sheet = excel[text.english ? 'Sales' : 'Vendas'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue(text.period),
      TextCellValue(text.date(from)),
      TextCellValue(text.date(to.subtract(const Duration(days: 1)))),
    ]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow(text.headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(text.dateTime(row.createdAt)),
        TextCellValue(row.documentNumber),
        TextCellValue(row.product),
        TextCellValue(text.status(row)),
        DoubleCellValue(row.quantityMilli / 1000),
        DoubleCellValue(row.totalMinor / 100),
      ]);
    }
    for (var index = 0; index < rows.length; index++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: index + 3))
          .cellStyle = CellStyle(
        numberFormat: NumFormat.custom(formatCode: '0.###'),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: index + 3))
          .cellStyle = CellStyle(
        numberFormat: NumFormat.custom(
          formatCode: '#,##0.00 "${currency == 'MZN' ? 'MT' : currency}"',
        ),
      );
    }
    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 24);
    sheet.setColumnWidth(2, 36);
    sheet.setColumnWidth(3, 16);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 20);
    return excel.save()!;
  }

  Future<List<StockReportRow>> stock(String companyId) async {
    final rows = await _db
        .customSelect(
          '''SELECT p.name,w.name warehouse,b.quantity_milli,(b.quantity_milli*p.cost_minor)/1000 value_minor FROM inventory_balances b JOIN products p ON p.id=b.product_id JOIN warehouses w ON w.id=b.warehouse_id WHERE p.company_id=? AND p.deleted_at IS NULL ORDER BY p.name''',
          variables: [Variable(companyId)],
        )
        .get();
    return [
      for (final r in rows)
        StockReportRow(
          r.read('name'),
          r.read('warehouse'),
          r.read('quantity_milli'),
          r.read('value_minor'),
        ),
    ];
  }

  String stockCsv(List<StockReportRow> rows) => Csv.excel().encode([
    ['Produto', 'Armazém', 'Quantidade (milésimos)', 'Valor (menor unidade)'],
    ...rows.map((r) => [r.name, r.warehouse, r.quantityMilli, r.valueMinor]),
  ]);

  List<int> stockXlsx(List<StockReportRow> rows) {
    final excel = Excel.createExcel(), sheet = excel['Stock'];
    excel.delete('Sheet1');
    sheet.appendRow(
      [
        'Produto',
        'Armazém',
        'Quantidade milésimos',
        'Valor menor unidade',
      ].map(TextCellValue.new).toList(),
    );
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(row.name),
        TextCellValue(row.warehouse),
        IntCellValue(row.quantityMilli),
        IntCellValue(row.valueMinor),
      ]);
    }
    return excel.save()!;
  }
}

/// Shared labels and formatting keep the screen and all exports consistent.
class SalesReportText {
  const SalesReportText(this.locale, [this.currency = 'MZN']);
  final String locale, currency;
  bool get english => locale.startsWith('en');
  String get title => english ? 'Sales report' : 'Relatório de vendas';
  String get period => english ? 'Period' : 'Período';
  String get footer => english
      ? 'Computer processed - Systock'
      : 'Processado por computador - Systock';
  List<String> get headers => english
      ? ['Date and time', 'Document', 'Product', 'Status', 'Qty.', 'Total']
      : ['Data e Hora', 'Documento', 'Produto', 'Estado', 'Qtde.', 'Total'];
  String status(SalesReportRow row) => row.status == 'paid'
      ? (english ? 'Paid' : 'Pago')
      : (english ? 'Unpaid' : 'Não pago');
  String date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String dateTime(DateTime value) =>
      '${date(value)} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
  String quantity(int milli) => english
      ? formatQuantity(milli).replaceAll(',', '.')
      : formatQuantity(milli);
  List<String> cells(SalesReportRow row) => [
    dateTime(row.createdAt),
    row.documentNumber,
    row.product,
    status(row),
    quantity(row.quantityMilli),
    formatMoneyMinor(
      row.totalMinor,
      locale: locale,
      symbol: currency == 'MZN' ? 'MT' : currency,
    ),
  ];
}
