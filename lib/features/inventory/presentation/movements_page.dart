import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/inventory/presentation/stock_movement_analytics.dart';
import 'package:systock/l10n/localized_text.dart';

class MovementViewRow {
  const MovementViewRow({
    required this.movement,
    required this.product,
    required this.warehouse,
    required this.unit,
    required this.user,
  });
  final InventoryMovement movement;
  final String product, warehouse, unit;
  final String? user;
}

class MovementsPage extends ConsumerStatefulWidget {
  const MovementsPage({super.key});
  @override
  ConsumerState<MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends ConsumerState<MovementsPage> {
  AnalyticsPeriod period = AnalyticsPeriod.thirtyDays;
  DateTimeRange? customRange;
  DateTimeRange get range => rangeForPeriod(period, customRange);
  Stream<List<MovementViewRow>> _movements(AppDatabase db, String companyId) =>
      db
          .customSelect(
            '''
    SELECT im.*,p.name product,COALESCE(u.code,'') unit,w.name warehouse,usr.name user_name
    FROM inventory_movements im JOIN products p ON p.id=im.product_id JOIN warehouses w ON w.id=im.warehouse_id
    LEFT JOIN units u ON u.id=p.unit_id LEFT JOIN users usr ON usr.id=im.user_id
    WHERE im.company_id=? AND im.created_at>=? AND im.created_at<? ORDER BY im.created_at DESC LIMIT 500
  ''',
            variables: [
              Variable(companyId),
              Variable(range.start),
              Variable(range.end),
            ],
            readsFrom: {
              db.inventoryMovements,
              db.products,
              db.warehouses,
              db.units,
              db.users,
            },
          )
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => MovementViewRow(
                    movement: db.inventoryMovements.map(r.data),
                    product: r.read('product'),
                    warehouse: r.read('warehouse'),
                    unit: r.read('unit'),
                    user: r.readNullable('user_name'),
                  ),
                )
                .toList(),
          );
  Future<void> _changePeriod(AnalyticsPeriod value) async {
    if (value == AnalyticsPeriod.custom) {
      final initial = customRange ?? range;
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(
          start: initial.start,
          end: initial.end.subtract(const Duration(days: 1)),
        ),
      );
      if (selected == null) return;
      setState(() {
        period = value;
        customRange = DateTimeRange(
          start: DateTime(
            selected.start.year,
            selected.start.month,
            selected.start.day,
          ),
          end: DateTime(
            selected.end.year,
            selected.end.month,
            selected.end.day,
          ).add(const Duration(days: 1)),
        );
      });
    } else {
      setState(() => period = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const AppBarTitle('Movimentos de stock'),
      ),
      body: FutureBuilder(
        future: db.select(db.companies).getSingleOrNull(),
        builder: (context, companySnapshot) {
          final company = companySnapshot.data;
          if (company == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<StockMovementAnalytics>(
            stream: watchStockMovementAnalytics(db, company.id, range),
            builder: (context, analytics) =>
                StreamBuilder<List<MovementBucket>>(
                  stream: watchMovementTimeline(db, company.id, range),
                  builder: (context, timeline) =>
                      StreamBuilder<List<MovementViewRow>>(
                        stream: _movements(db, company.id),
                        builder: (context, movements) {
                          if (!analytics.hasData ||
                              !timeline.hasData ||
                              !movements.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              AnalyticsPeriodPicker(
                                value: period,
                                range: range,
                                onChanged: _changePeriod,
                              ),
                              const SizedBox(height: 12),
                              StockMovementSummary(
                                data: analytics.data!,
                                timeline: timeline.data!,
                              ),
                              const SizedBox(height: 16),
                              if (movements.data!.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: LocalizedText(
                                      'Sem dados para este período.',
                                    ),
                                  ),
                                ),
                              for (final row in movements.data!) ...[
                                _MovementCard(row: row),
                                const SizedBox(height: 8),
                              ],
                            ],
                          );
                        },
                      ),
                ),
          );
        },
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.row});
  final MovementViewRow row;
  @override
  Widget build(BuildContext context) {
    final m = row.movement,
        incoming = m.quantityMilli > 0,
        color = incoming ? Colors.green : Colors.red,
        date = m.createdAt.toLocal();
    final details = <String>[
      row.warehouse,
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      if (row.user != null) row.user!,
      if (m.reason?.trim().isNotEmpty ?? false) m.reason!,
    ];
    return Card(
      color: color.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(
            incoming ? Icons.arrow_downward : Icons.arrow_upward,
            color: Colors.white,
          ),
        ),
        title: Text(
          row.product,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              _movementLabel(m.movementType),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            Text(details.join(' • ')),
            Text(
              'Stock: ${quantity(m.balanceBeforeMilli)} → ${quantity(m.balanceAfterMilli)}${row.unit.isEmpty ? '' : ' ${row.unit}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Text(
          '${incoming ? '+' : '−'}${quantity(m.quantityMilli.abs())}${row.unit.isEmpty ? '' : ' ${row.unit}'}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ),
    );
  }
}

String _movementLabel(String type) => switch (type) {
  'purchase' => 'Compra',
  'sale' => 'Venda',
  'adjustmentIn' => 'Ajuste de entrada',
  'adjustmentOut' => 'Ajuste de saída',
  'transferIn' => 'Transferência recebida',
  'transferOut' => 'Transferência expedida',
  'returnIn' => 'Devolução',
  'damaged' => 'Produto danificado',
  'expired' => 'Produto vencido',
  'initialStock' => 'Stock inicial',
  'production' => 'Produção',
  'cancellation' => 'Cancelamento',
  _ => type,
};
