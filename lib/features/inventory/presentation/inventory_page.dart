import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';

class InventoryRow {
  const InventoryRow(
    this.productId,
    this.product,
    this.unit,
    this.quantityMilli,
  );
  final String productId, product, unit;
  final int quantityMilli;
}

class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});
  Stream<List<InventoryRow>> rows(AppDatabase db, String company) => db
      .customSelect(
        '''SELECT p.id,p.name product,COALESCE(u.code,'') unit,COALESCE(SUM(b.quantity_milli),0) quantity FROM products p LEFT JOIN units u ON u.id=p.unit_id LEFT JOIN inventory_balances b ON b.product_id=p.id WHERE p.company_id=? AND p.deleted_at IS NULL GROUP BY p.id,p.name,u.code ORDER BY p.name''',
        variables: [Variable(company)],
        readsFrom: {db.products, db.units, db.inventoryBalances},
      )
      .map(
        (r) => InventoryRow(
          r.read('id'),
          r.read('product'),
          r.read('unit'),
          r.read('quantity'),
        ),
      )
      .watch();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Stock')),
      body: FutureBuilder(
        future: db.select(db.companies).getSingleOrNull(),
        builder: (context, company) {
          if (company.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _adjust(context, db),
                      icon: const Icon(Icons.tune),
                      label: const LocalizedText('Ajustar'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: rows(db, company.data!.id),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snapshot.data!;
                    if (data.isEmpty) {
                      return const Center(
                        child: LocalizedText(
                          'Cadastre produtos para controlar o stock.',
                        ),
                      );
                    }
                    final total = data.fold<int>(
                      0,
                      (sum, row) => sum + row.quantityMilli,
                    );
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: data.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Card(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: ListTile(
                              leading: const Icon(Icons.inventory_outlined),
                              title: const LocalizedText(
                                'Quantidade geral em stock',
                              ),
                              trailing: Text(
                                _quantity(total),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ),
                          );
                        }
                        final row = data[i - 1];
                        return Card(
                          child: ListTile(
                            onTap: () => context.go(
                              '/inventory/product/${row.productId}',
                            ),
                            title: Text(row.product),
                            subtitle: LocalizedText(
                              'Stock disponível${row.unit.isEmpty ? '' : ' · ${row.unit}'}',
                            ),
                            trailing: Text(
                              _quantity(row.quantityMilli),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            leading: const Icon(Icons.inventory_2_outlined),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _quantity(int milli) {
    final value = milli / 1000;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  Future<void> _adjust(BuildContext context, AppDatabase db) async {
    final products = await (db.select(
          db.products,
        )..where((p) => p.deletedAt.isNull())).get(),
        warehouses = await db.select(db.warehouses).get(),
        company = await db.select(db.companies).getSingle(),
        user = await currentSessionUser(db);
    if (products.isEmpty || warehouses.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'Cadastre um produto e um armazém primeiro.',
            ),
          ),
        );
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    String product = products.first.id,
        warehouse = warehouses.first.id,
        type = 'Adicionar';
    final quantity = TextEditingController(), reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Ajustar stock'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: product,
                  items: products
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => product = v!),
                  decoration: InputDecoration(
                    labelText: 'Produto'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: warehouse,
                  items: warehouses
                      .map(
                        (w) =>
                            DropdownMenuItem(value: w.id, child: Text(w.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => warehouse = v!),
                  decoration: InputDecoration(
                    labelText: 'Armazém'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton(
                  segments: const [
                    ButtonSegment(
                      value: 'Adicionar',
                      label: LocalizedText('Adicionar'),
                    ),
                    ButtonSegment(
                      value: 'Remover',
                      label: LocalizedText('Remover'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => setDialog(() => type = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantidade'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: InputDecoration(
                    labelText: 'Motivo obrigatório'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final milli =
        ((double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) * 1000)
            .round() *
        (type == 'Remover' ? -1 : 1);
    final result = await InventoryLedger(db).move(
      companyId: company.id,
      productId: product,
      warehouseId: warehouse,
      quantityMilli: milli,
      type: type == 'Remover'
          ? InventoryMovementType.adjustmentOut
          : InventoryMovementType.adjustmentIn,
      deviceId: company.deviceId,
      userId: user.id,
      reason: reason.text,
    );
    if (context.mounted) {
      if (result case Failure(:final error)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    }
  }
}
