import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/utils/quantity.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/l10n/localized_text.dart';

class RecentEntry {
  const RecentEntry({
    required this.product,
    required this.barcode,
    required this.unit,
    required this.quantityMilli,
    required this.stockMilli,
    required this.createdAt,
  });

  final String product, barcode, unit;
  final int quantityMilli, stockMilli;
  final DateTime createdAt;
}

Stream<List<RecentEntry>> watchRecentEntries(
  AppDatabase db,
  String companyId,
) => db
    .customSelect(
      '''
      SELECT p.name product, COALESCE(u.code, '') unit,
        COALESCE((SELECT barcode FROM product_barcodes pb
          WHERE pb.product_id = p.id AND pb.deleted_at IS NULL
          ORDER BY pb.primary_barcode DESC, pb.created_at, pb.id LIMIT 1), '') barcode,
        m.quantity_milli quantity,
        COALESCE((SELECT SUM(b.quantity_milli) FROM inventory_balances b
          WHERE b.product_id = p.id), 0) stock,
        m.created_at
      FROM inventory_movements m
      JOIN products p ON p.id = m.product_id
      LEFT JOIN units u ON u.id = p.unit_id
      WHERE m.company_id = ? AND p.company_id = ?
        AND m.quantity_milli > 0 AND m.deleted_at IS NULL
        AND p.deleted_at IS NULL
      ORDER BY m.created_at DESC, m.id DESC LIMIT 100
      ''',
      variables: [Variable(companyId), Variable(companyId)],
      readsFrom: {
        db.inventoryMovements,
        db.products,
        db.units,
        db.productBarcodes,
        db.inventoryBalances,
      },
    )
    .watch()
    .map(
      (rows) => rows
          .map(
            (row) => RecentEntry(
              product: row.read('product'),
              barcode: row.read('barcode'),
              unit: row.read('unit'),
              quantityMilli: row.read('quantity'),
              stockMilli: row.read('stock'),
              createdAt: row.read('created_at'),
            ),
          )
          .toList(),
    );

final _recentEntriesProvider = StreamProvider<List<RecentEntry>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final company = await db.select(db.companies).getSingleOrNull();
  if (company == null) {
    yield const [];
    return;
  }
  yield* watchRecentEntries(db, company.id);
});

class RecentEntriesPage extends ConsumerWidget {
  const RecentEntriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: const AdaptiveBackButton(fallbackPath: '/inventory'),
      title: const LocalizedText('Entradas recentes'),
    ),
    body: ref
        .watch(_recentEntriesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: LocalizedText(
              'Não foi possível carregar as entradas recentes.',
            ),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return const Center(
                child: LocalizedText('Nenhuma entrada de stock registada.'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const LocalizedText(
                    'Últimas 100 entradas. Stock atual total em todos os armazéns.',
                  );
                }
                final entry = entries[index - 1];
                String quantity(int value) =>
                    '${formatQuantity(value)}${entry.unit.isEmpty ? '' : ' ${entry.unit}'}';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.product,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${'Código de barras'.localized(context)}: ${entry.barcode.isEmpty ? '—' : entry.barcode}',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            Text(
                              '${'Quantidade de entrada'.localized(context)}: ${quantity(entry.quantityMilli)}',
                            ),
                            Text(
                              '${'Stock atual'.localized(context)}: ${quantity(entry.stockMilli)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(entry.createdAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
  );
}
