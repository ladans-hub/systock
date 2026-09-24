import 'package:systock/core/widgets/action_colors.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/widgets/platform_controls.dart';
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

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<InventoryRow>> rows(AppDatabase db, String company) => db
      .customSelect(
        '''SELECT p.id,p.name product,COALESCE(u.code,'') unit,COALESCE(SUM(b.quantity_milli),0) quantity FROM products p LEFT JOIN units u ON u.id=p.unit_id LEFT JOIN inventory_balances b ON b.product_id=p.id WHERE p.company_id=? AND p.deleted_at IS NULL AND (?='' OR lower(p.name) LIKE ? OR EXISTS(SELECT 1 FROM product_barcodes barcode WHERE barcode.product_id=p.id AND barcode.deleted_at IS NULL AND lower(barcode.barcode) LIKE ?)) GROUP BY p.id,p.name,u.code ORDER BY p.name''',
        variables: [
          Variable(company),
          Variable(_query),
          Variable('%${_query.toLowerCase()}%'),
          Variable('%${_query.toLowerCase()}%'),
        ],
        readsFrom: {
          db.products,
          db.units,
          db.inventoryBalances,
          db.productBarcodes,
        },
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
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Stock')),
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
                    OutlinedButton.icon(
                      onPressed: () => context.go('/inventory/recent-entries'),
                      icon: const Icon(Icons.history),
                      label: const LocalizedText('Entradas recentes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/inventory/lots'),
                      icon: const Icon(Icons.event_outlined),
                      label: const LocalizedText('Lotes e validades'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AdaptiveSearchField(
                  controller: _searchController,
                  hintText: 'Nome ou código de barras'.localized(context),
                  onChanged: _search,
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
                      return Center(
                        child: LocalizedText(
                          _query.isEmpty
                              ? 'Cadastre produtos para controlar o stock.'
                              : 'Nenhum produto encontrado.',
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
                              title: LocalizedText(
                                _query.isEmpty
                                    ? 'Quantidade geral em stock'
                                    : 'Stock dos produtos encontrados',
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
        showAppError(context, 'Cadastre um produto e um armazém primeiro.');
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
                      label: LocalizedText(
                        'Remover',
                        style: TextStyle(color: removalActionColor),
                      ),
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
        showAppFailure(context, error);
      }
    }
  }
}
