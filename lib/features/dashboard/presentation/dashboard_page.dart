import 'package:systock/core/widgets/notification_bell.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/utils/money.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/features/reports/application/report_service.dart';

class DashboardData {
  const DashboardData(
    this.company,
    this.kpis,
    this.products,
    this.low,
    this.out,
    this.stockValue,
    this.dailySales,
    this.operational,
    this.bestSelling,
    this.leastSelling,
    this.from,
    this.to,
    this.chartBucketDays,
  );
  final Company company;
  final SalesKpis kpis;
  final int products, low, out, stockValue;
  final List<int> dailySales;
  final PeriodOperationalTotals operational;
  final List<ProductSalesRanking> bestSelling, leastSelling;
  final DateTime from, to;
  final int chartBucketDays;
}

enum DashboardPeriod { week, month, quarter, semester, year }

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  late Future<DashboardData> _data;
  DashboardPeriod period = DashboardPeriod.week;

  @override
  void initState() {
    super.initState();
    _data = load(ref.read(databaseProvider));
  }

  Future<DashboardData> load(AppDatabase db) async {
    final company = await db.select(db.companies).getSingle();
    final range = _range(period);
    final from = range.$1, to = range.$2;
    final service = ReportService(db);
    final kpis = await service.salesKpis(company.id, from, to);
    final row = await db
        .customSelect(
          '''SELECT COUNT(*) products, COALESCE(SUM(CASE WHEN COALESCE(b.qty,0)<=p.minimum_stock_milli THEN 1 ELSE 0 END),0) low, COALESCE(SUM(CASE WHEN COALESCE(b.qty,0)=0 THEN 1 ELSE 0 END),0) out, COALESCE(SUM(COALESCE(b.qty,0)*p.cost_minor/1000),0) value FROM products p LEFT JOIN (SELECT product_id,SUM(quantity_milli) qty FROM inventory_balances GROUP BY product_id)b ON b.product_id=p.id WHERE p.company_id=? AND p.deleted_at IS NULL''',
          variables: [Variable(company.id)],
          readsFrom: {db.products, db.inventoryBalances},
        )
        .getSingle();
    final chart = await service.revenueSeries(company.id, from, to);
    return DashboardData(
      company,
      kpis,
      row.read('products'),
      row.read('low'),
      row.read('out'),
      row.read('value'),
      chart.values,
      await service.operationalTotals(company.id, from, to),
      await service.productRanking(company.id, from, to),
      await service.productRanking(company.id, from, to, least: true),
      from,
      to,
      chart.bucketDays,
    );
  }

  (DateTime, DateTime) _range(DashboardPeriod value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day + 1).toUtc();
    final from = switch (value) {
      DashboardPeriod.week => today.subtract(const Duration(days: 6)),
      DashboardPeriod.month => DateTime(now.year, now.month),
      DashboardPeriod.quarter => DateTime(
        now.year,
        ((now.month - 1) ~/ 3) * 3 + 1,
      ),
      DashboardPeriod.semester => DateTime(now.year, now.month <= 6 ? 1 : 7),
      DashboardPeriod.year => DateTime(now.year),
    };
    return (from.toUtc(), to);
  }

  void _selectPeriod(DashboardPeriod value) {
    setState(() {
      period = value;
      _data = load(ref.read(databaseProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: mobile
          ? null
          : AppBar(
              title: const LocalizedText('Visão geral'),
              actions: [
                const NotificationBell(),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Chip(
                    avatar: Icon(Icons.offline_bolt_outlined, size: 18),
                    label: LocalizedText('SQLite local'),
                  ),
                ),
              ],
            ),
      body: FutureBuilder<DashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DashboardError(
              onRetry: () {
                setState(() => _data = load(ref.read(databaseProvider)));
              },
            );
          }
          final d = snapshot.data!, currency = d.company.currencyCode;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                d.company.tradeName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              LocalizedText(
                'Desempenho de ${_date(d.from)} a ${_date(d.to.subtract(const Duration(days: 1)))}.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in DashboardPeriod.values)
                    _PeriodOption(
                      label: _periodLabel(value),
                      selected: period == value,
                      onTap: () => _selectPeriod(value),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1050
                      ? 4
                      : constraints.maxWidth >= 560
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 14) / columns;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _Metric(
                        'Total de vendas',
                        formatMoneyMinor(
                          d.kpis.revenueMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.trending_up,
                        width,
                      ),
                      _Metric(
                        'Quantidade de vendas',
                        '${d.kpis.saleCount}',
                        Icons.receipt_long_outlined,
                        width,
                      ),
                      _Metric(
                        'Valor médio por venda',
                        formatMoneyMinor(
                          d.kpis.averageTicketMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.calculate_outlined,
                        width,
                      ),
                      _Metric(
                        'Total no caixa',
                        formatMoneyMinor(
                          d.operational.cashNetMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.account_balance_wallet_outlined,
                        width,
                      ),
                      _Metric(
                        'Entradas no caixa',
                        formatMoneyMinor(
                          d.operational.cashInMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.south_west_rounded,
                        width,
                      ),
                      _Metric(
                        'Saídas do caixa',
                        formatMoneyMinor(
                          d.operational.cashOutMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.north_east_rounded,
                        width,
                      ),
                      _Metric(
                        'Entradas de stock',
                        _quantity(d.operational.stockInMilli),
                        Icons.move_to_inbox_outlined,
                        width,
                      ),
                      _Metric(
                        'Saídas de stock',
                        _quantity(d.operational.stockOutMilli),
                        Icons.outbox_outlined,
                        width,
                      ),
                      _Metric(
                        'Lucro bruto',
                        formatMoneyMinor(
                          d.kpis.grossProfitMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.paid_outlined,
                        width,
                      ),
                      _Metric(
                        'Produtos',
                        '${d.products}',
                        Icons.inventory_2_outlined,
                        width,
                      ),
                      _Metric(
                        'Stock baixo',
                        '${d.low}',
                        Icons.warning_amber,
                        width,
                      ),
                      _Metric(
                        'Sem stock',
                        '${d.out}',
                        Icons.remove_shopping_cart_outlined,
                        width,
                      ),
                      _Metric(
                        'Valor do stock',
                        formatMoneyMinor(
                          d.stockValue,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                        Icons.account_balance_wallet_outlined,
                        width,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _SalesChart(
                values: d.dailySales,
                currency: currency,
                title: 'Vendas por dia · ${_periodLabel(period)}',
                start: d.from,
                bucketDays: d.chartBucketDays,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    _RankingCard(
                      title: 'Produtos mais vendidos',
                      rows: d.bestSelling,
                      currency: currency,
                    ),
                    _RankingCard(
                      title: 'Produtos menos vendidos',
                      rows: d.leastSelling,
                      currency: currency,
                    ),
                  ];
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        cards.first,
                        const SizedBox(height: 12),
                        cards.last,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards.first),
                      const SizedBox(width: 14),
                      Expanded(child: cards.last),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        'Atenção necessária',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.warning_amber),
                        title: LocalizedText('${d.low} produtos no mínimo'),
                        trailing: TextButton(
                          onPressed: () => context.go('/inventory'),
                          child: const LocalizedText('Ver stock'),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.sync),
                        title: const LocalizedText(
                          'Operações locais protegidas',
                        ),
                        subtitle: const LocalizedText(
                          'A indisponibilidade do Drive nunca bloqueia vendas.',
                        ),
                        trailing: TextButton(
                          onPressed: () => context.go('/settings/sync'),
                          child: const LocalizedText('Sincronização'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _periodLabel(DashboardPeriod value) => switch (value) {
    DashboardPeriod.week => 'Semana',
    DashboardPeriod.month => 'Mês',
    DashboardPeriod.quarter => 'Trimestre',
    DashboardPeriod.semester => 'Semestre',
    DashboardPeriod.year => 'Ano',
  };

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _quantity(int milli) {
    final value = milli / 1000;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({
    required this.values,
    required this.currency,
    required this.title,
    required this.start,
    required this.bucketDays,
  });
  final List<int> values;
  final String currency;
  final String title;
  final DateTime start;
  final int bucketDays;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < values.length; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Tooltip(
                              message: formatMoneyMinor(
                                values[index],
                                symbol: currency == 'MZN' ? 'MT' : currency,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                height: 120 * values[index] / maximum + 3,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              bucketDays == 1 && values.length <= 14
                                  ? _weekday(
                                      start
                                          .add(
                                            Duration(days: index * bucketDays),
                                          )
                                          .weekday,
                                    )
                                  : '${start.add(Duration(days: index * bucketDays)).day}/${start.add(Duration(days: index * bucketDays)).month}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekday(int value) =>
      const ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][value - 1];
}

class _PeriodOption extends StatelessWidget {
  const _PeriodOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.rows,
    required this.currency,
  });
  final String title, currency;
  final List<ProductSalesRanking> rows;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LocalizedText('Sem vendas neste período.'),
            )
          else
            for (var index = 0; index < rows.length; index++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  child: LocalizedText('${index + 1}'),
                ),
                title: Text(
                  rows[index].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: LocalizedText(
                  '${_quantity(rows[index].quantityMilli)} vendidos',
                ),
                trailing: Text(
                  formatMoneyMinor(
                    rows[index].revenueMinor,
                    symbol: currency == 'MZN' ? 'MT' : currency,
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  String _quantity(int milli) {
    final value = milli / 1000;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(3);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.width);
  final String label, value;
  final IconData icon;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 44,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          LocalizedText(
            'Não foi possível carregar a visão geral.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const LocalizedText('Os seus dados locais continuam seguros.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const LocalizedText('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}
