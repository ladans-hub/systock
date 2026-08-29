import 'dart:math' as math;
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/l10n/localized_text.dart';

enum AnalyticsPeriod { today, sevenDays, thirtyDays, month, custom }

enum ProductChartMode { moved, sold, received, stock, low, idle }

class ProductMovementTotal {
  const ProductMovementTotal({
    required this.name,
    required this.unit,
    required this.incomingMilli,
    required this.outgoingMilli,
    required this.soldMilli,
    required this.stockMilli,
    required this.minimumMilli,
  });
  final String name, unit;
  final int incomingMilli, outgoingMilli, soldMilli, stockMilli, minimumMilli;
}

class MovementBucket {
  const MovementBucket(this.day, this.incomingMilli, this.outgoingMilli);
  final DateTime day;
  final int incomingMilli, outgoingMilli;
}

class StockMovementAnalytics {
  const StockMovementAnalytics({
    required this.productCount,
    required this.incomingMilli,
    required this.outgoingMilli,
    required this.transferMilli,
    required this.products,
  });
  final int productCount, incomingMilli, outgoingMilli, transferMilli;
  int get netMilli => incomingMilli - outgoingMilli;
  final List<ProductMovementTotal> products;
}

DateTimeRange rangeForPeriod(AnalyticsPeriod period, [DateTimeRange? custom]) {
  final now = DateTime.now(),
      today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
  final end = today.add(const Duration(days: 1));
  return switch (period) {
    AnalyticsPeriod.today => DateTimeRange(start: today, end: end),
    AnalyticsPeriod.sevenDays => DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: end,
    ),
    AnalyticsPeriod.thirtyDays => DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: end,
    ),
    AnalyticsPeriod.month => DateTimeRange(
      start: DateTime(now.year, now.month),
      end: end,
    ),
    AnalyticsPeriod.custom =>
      custom ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: end,
          ),
  };
}

Stream<StockMovementAnalytics> watchStockMovementAnalytics(
  AppDatabase db,
  String companyId,
  DateTimeRange range,
) => db
    .customSelect(
      '''
 SELECT p.name,COALESCE(u.code,'') unit,p.minimum_stock_milli minimum_qty,
 COALESCE((SELECT SUM(b.quantity_milli) FROM inventory_balances b WHERE b.product_id=p.id),0) stock,
 COALESCE(SUM(CASE WHEN im.quantity_milli>0 AND im.movement_type NOT IN ('transferIn','transferOut') THEN im.quantity_milli ELSE 0 END),0) incoming,
 COALESCE(SUM(CASE WHEN im.quantity_milli<0 AND im.movement_type NOT IN ('transferIn','transferOut') THEN -im.quantity_milli ELSE 0 END),0) outgoing,
 COALESCE(SUM(CASE WHEN im.movement_type='sale' THEN -im.quantity_milli ELSE 0 END),0) sold,
 COALESCE(SUM(CASE WHEN im.movement_type='transferOut' THEN -im.quantity_milli ELSE 0 END),0) transfer_qty
 FROM products p LEFT JOIN units u ON u.id=p.unit_id LEFT JOIN inventory_movements im ON im.product_id=p.id AND im.company_id=? AND im.created_at>=? AND im.created_at<?
 WHERE p.company_id=? AND p.deleted_at IS NULL GROUP BY p.id,p.name,u.code,p.minimum_stock_milli
 ''',
      variables: [
        Variable(companyId),
        Variable(range.start),
        Variable(range.end),
        Variable(companyId),
      ],
      readsFrom: {
        db.products,
        db.units,
        db.inventoryBalances,
        db.inventoryMovements,
      },
    )
    .watch()
    .map((rows) {
      var incoming = 0, outgoing = 0, transfer = 0;
      final products = rows.map((r) {
        incoming += r.read<int>('incoming');
        outgoing += r.read<int>('outgoing');
        transfer += r.read<int>('transfer_qty');
        return ProductMovementTotal(
          name: r.read('name'),
          unit: r.read('unit'),
          incomingMilli: r.read('incoming'),
          outgoingMilli: r.read('outgoing'),
          soldMilli: r.read('sold'),
          stockMilli: r.read('stock'),
          minimumMilli: r.read('minimum_qty'),
        );
      }).toList();
      return StockMovementAnalytics(
        productCount: products.length,
        incomingMilli: incoming,
        outgoingMilli: outgoing,
        transferMilli: transfer,
        products: products,
      );
    });

Stream<List<MovementBucket>> watchMovementTimeline(
  AppDatabase db,
  String companyId,
  DateTimeRange range,
) => db
    .customSelect(
      '''
 SELECT strftime('%Y-%m-%d',created_at,'unixepoch','localtime') day,
 COALESCE(SUM(CASE WHEN quantity_milli>0 AND movement_type NOT IN ('transferIn','transferOut') THEN quantity_milli ELSE 0 END),0) incoming,
 COALESCE(SUM(CASE WHEN quantity_milli<0 AND movement_type NOT IN ('transferIn','transferOut') THEN -quantity_milli ELSE 0 END),0) outgoing
 FROM inventory_movements WHERE company_id=? AND created_at>=? AND created_at<? GROUP BY day ORDER BY day
 ''',
      variables: [
        Variable(companyId),
        Variable(range.start),
        Variable(range.end),
      ],
      readsFrom: {db.inventoryMovements},
    )
    .watch()
    .map(
      (rows) => rows
          .map(
            (r) => MovementBucket(
              DateTime.parse(r.read('day')),
              r.read('incoming'),
              r.read('outgoing'),
            ),
          )
          .toList(),
    );

class AnalyticsPeriodPicker extends StatelessWidget {
  const AnalyticsPeriodPicker({
    required this.value,
    required this.range,
    required this.onChanged,
    super.key,
  });
  final AnalyticsPeriod value;
  final DateTimeRange range;
  final ValueChanged<AnalyticsPeriod> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final option in AnalyticsPeriod.values)
        ChoiceChip(
          label: LocalizedText(switch (option) {
            AnalyticsPeriod.today => 'Hoje',
            AnalyticsPeriod.sevenDays => '7 dias',
            AnalyticsPeriod.thirtyDays => '30 dias',
            AnalyticsPeriod.month => 'Este mês',
            AnalyticsPeriod.custom => 'Personalizado',
          }),
          selected: value == option,
          onSelected: (_) => onChanged(option),
        ),
      Text(
        '${_date(range.start)} – ${_date(range.end.subtract(const Duration(days: 1)))}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class StockMovementSummary extends StatelessWidget {
  const StockMovementSummary({
    required this.data,
    this.timeline = const [],
    this.showProductCount = false,
    this.productMode,
    super.key,
  });
  final StockMovementAnalytics data;
  final List<MovementBucket> timeline;
  final bool showProductCount;
  final ProductChartMode? productMode;
  @override
  Widget build(BuildContext context) {
    final netColor = data.netMilli >= 0 ? Colors.green : Colors.red;
    final cards = <Widget>[
      if (showProductCount)
        _MetricCard(
          'Total de produtos',
          '${data.productCount}',
          Icons.inventory_2_outlined,
          Theme.of(context).colorScheme.primary,
        ),
      _MetricCard(
        'Entradas externas',
        quantity(data.incomingMilli),
        Icons.south_west_rounded,
        Colors.green,
      ),
      _MetricCard(
        'Saídas externas',
        quantity(data.outgoingMilli),
        Icons.north_east_rounded,
        Colors.red,
      ),
      _MetricCard(
        'Transferências internas',
        quantity(data.transferMilli),
        Icons.swap_horiz_rounded,
        Colors.orange,
      ),
      _MetricCard(
        'Saldo líquido',
        '${data.netMilli >= 0 ? '+' : ''}${quantity(data.netMilli)}',
        Icons.balance_rounded,
        netColor,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 900
                ? cards.length
                : c.maxWidth >= 360
                ? 2
                : 1;
            final width = (c.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (productMode == null)
          _TimelineChart(items: timeline)
        else
          ProductMovementChart(data: data, mode: productMode!),
      ],
    );
  }
}

class ProductMovementChart extends StatelessWidget {
  const ProductMovementChart({
    required this.data,
    required this.mode,
    super.key,
  });
  final StockMovementAnalytics data;
  final ProductChartMode mode;
  @override
  Widget build(BuildContext context) {
    final products = [...data.products];
    int value(ProductMovementTotal p) => switch (mode) {
      ProductChartMode.moved => p.incomingMilli + p.outgoingMilli,
      ProductChartMode.sold => p.soldMilli,
      ProductChartMode.received => p.incomingMilli,
      ProductChartMode.stock => p.stockMilli,
      ProductChartMode.low => math.max(0, p.minimumMilli - p.stockMilli),
      ProductChartMode.idle =>
        p.incomingMilli + p.outgoingMilli == 0 ? p.stockMilli : 0,
    };
    products.sort((a, b) => value(b).compareTo(value(a)));
    final items = products
        .where(
          (p) => mode == ProductChartMode.idle
              ? p.incomingMilli + p.outgoingMilli == 0
              : value(p) > 0,
        )
        .take(6)
        .toList();
    final maximum = math.max(
      1,
      items.fold<int>(0, (v, p) => math.max(v, value(p))),
    );
    return _ChartCard(
      title: productModeLabel(mode),
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: LocalizedText('Sem dados para este período.'),
              ),
            )
          : Column(
              children: [
                for (final p in items)
                  _NamedBar(
                    name: p.name,
                    value: value(p),
                    maximum: maximum,
                    unit: p.unit,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
    );
  }
}

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.items});
  final List<MovementBucket> items;
  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      1,
      items.fold<int>(
        0,
        (v, p) => math.max(v, math.max(p.incomingMilli, p.outgoingMilli)),
      ),
    );
    return _ChartCard(
      title: 'Evolução de entradas e saídas',
      child: Column(
        children: [
          const Row(
            children: [
              _Legend(Colors.green, 'Entradas'),
              SizedBox(width: 16),
              _Legend(Colors.red, 'Saídas'),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LocalizedText('Sem dados para este período.'),
            ),
          for (final item in items) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${item.day.day}/${item.day.month}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _PlainBar(
              value: item.incomingMilli,
              maximum: maximum,
              color: Colors.green,
            ),
            const SizedBox(height: 3),
            _PlainBar(
              value: item.outgoingMilli,
              maximum: maximum,
              color: Colors.red,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .14),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _NamedBar extends StatelessWidget {
  const _NamedBar({
    required this.name,
    required this.value,
    required this.maximum,
    required this.unit,
    required this.color,
  });
  final String name, unit;
  final int value, maximum;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        _PlainBar(value: value, maximum: maximum, color: color, suffix: unit),
      ],
    ),
  );
}

class _PlainBar extends StatelessWidget {
  const _PlainBar({
    required this.value,
    required this.maximum,
    required this.color,
    this.suffix = '',
  });
  final int value, maximum;
  final Color color;
  final String suffix;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Row(
      children: [
        Container(
          width: value == 0
              ? 3
              : math.max(3, (c.maxWidth - 72) * value / maximum),
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${quantity(value)}${suffix.isEmpty ? '' : ' $suffix'}',
            style: Theme.of(context).textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      LocalizedText(label),
    ],
  );
}

String productModeLabel(ProductChartMode mode) => switch (mode) {
  ProductChartMode.moved => 'Mais movimentados',
  ProductChartMode.sold => 'Mais vendidos',
  ProductChartMode.received => 'Mais recebidos',
  ProductChartMode.stock => 'Maior stock atual',
  ProductChartMode.low => 'Stock baixo',
  ProductChartMode.idle => 'Sem movimento',
};
String quantity(int milli) {
  final v = milli / 1000;
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
