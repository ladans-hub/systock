import 'package:systock/core/widgets/action_colors.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/security/permission_gate.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/products/presentation/product_image.dart';
import 'package:systock/features/products/application/product_catalog.dart';

class InventoryProductPage extends ConsumerStatefulWidget {
  const InventoryProductPage(this.productId, {super.key});
  final String productId;

  @override
  ConsumerState<InventoryProductPage> createState() =>
      _InventoryProductPageState();
}

class _InventoryProductPageState extends ConsumerState<InventoryProductPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<Product>(
      future: (db.select(
        db.products,
      )..where((p) => p.id.equals(widget.productId))).getSingle(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final product = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            leading: const AdaptiveBackButton(fallbackPath: '/inventory'),
            title: Text(product.name),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      ProductImage(
                        path: product.imagePath,
                        width: 72,
                        height: 72,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const LocalizedText('Stock do produto'),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/products/${product.id}'),
                        child: const LocalizedText('Abrir ficha'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              PermissionBuilder(
                permission: 'inventory.adjust',
                builder: (_) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _addEntry(db, product),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const LocalizedText('Adicionar entrada'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _adjust(db, product),
                      icon: const Icon(Icons.tune),
                      label: const LocalizedText('Ajustar stock'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'Quantidade disponível',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              StreamBuilder(
                stream: db
                    .customSelect(
                      '''SELECT COALESCE(SUM(quantity_milli),0) quantity FROM inventory_balances WHERE product_id=?''',
                      variables: [Variable(product.id)],
                      readsFrom: {db.inventoryBalances},
                    )
                    .watch(),
                builder: (_, balances) => Card(
                  child: Column(
                    children: [
                      for (final row in balances.data ?? const [])
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: const LocalizedText('Stock disponível'),
                          trailing: Text(
                            _quantity(row.read<int>('quantity')),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'Movimentos recentes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<InventoryMovement>>(
                stream:
                    (db.select(db.inventoryMovements)
                          ..where((m) => m.productId.equals(product.id))
                          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
                          ..limit(100))
                        .watch(),
                builder: (_, movements) => Card(
                  child: Column(
                    children: [
                      if ((movements.data ?? const []).isEmpty)
                        const ListTile(
                          title: LocalizedText('Ainda não existem movimentos.'),
                        ),
                      for (final movement in movements.data ?? const [])
                        ListTile(
                          leading: Icon(
                            movement.quantityMilli >= 0
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: movement.quantityMilli >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                          title: Text(_movementLabel(movement.movementType)),
                          subtitle: Text(
                            '${_date(movement.createdAt)} · ${movement.reason ?? 'Sem observação'}',
                          ),
                          trailing: LocalizedText(
                            '${movement.quantityMilli >= 0 ? '+' : ''}${_quantity(movement.quantityMilli)}',
                            style: TextStyle(
                              color: movement.quantityMilli >= 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _adjust(AppDatabase db, Product product) async {
    final warehouses =
        await (db.select(db.warehouses)
              ..where((w) => w.deletedAt.isNull())
              ..where((w) => w.active.equals(true)))
            .get();
    if (!mounted || warehouses.isEmpty) return;
    var warehouseId = warehouses.first.id, mode = 'add';
    final quantity = TextEditingController(), reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: LocalizedText('Ajustar ${product.name}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: warehouseId,
                  decoration: InputDecoration(
                    labelText: 'Armazém'.localized(context),
                  ),
                  items: [
                    for (final warehouse in warehouses)
                      DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(warehouse.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => warehouseId = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(
                    labelText: 'Operação'.localized(context),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'add',
                      child: LocalizedText('Adicionar'),
                    ),
                    DropdownMenuItem(
                      value: 'remove',
                      child: LocalizedText(
                        'Remover',
                        style: TextStyle(color: removalActionColor),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'set',
                      child: LocalizedText('Definir quantidade'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => mode = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
    if (confirmed != true || reason.text.trim().isEmpty) return;
    var milli =
        ((double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) * 1000)
            .round();
    final balance =
        await (db.select(db.inventoryBalances)
              ..where((b) => b.productId.equals(product.id))
              ..where((b) => b.warehouseId.equals(warehouseId)))
            .getSingleOrNull();
    if (mode == 'set') milli -= balance?.quantityMilli ?? 0;
    if (mode == 'remove') milli = -milli;
    if (milli == 0) return;
    final user =
        await (db.select(db.users)
              ..where((u) => u.active.equals(true))
              ..limit(1))
            .getSingle();
    final result = await InventoryLedger(db).move(
      companyId: product.companyId,
      productId: product.id,
      warehouseId: warehouseId,
      quantityMilli: milli,
      type: milli > 0
          ? InventoryMovementType.adjustmentIn
          : InventoryMovementType.adjustmentOut,
      deviceId: product.deviceId,
      userId: user.id,
      reason: reason.text.trim(),
      allowNegative: product.allowNegativeStock,
    );
    if (!mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      _message('Stock atualizado com movimento auditável.');
    }
  }

  Future<void> _addEntry(AppDatabase db, Product product) async {
    final code = TextEditingController(), quantity = TextEditingController();
    DateTime? expiresAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Adicionar entrada de stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Código de barras'),
            ),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            StatefulBuilder(
              builder: (context, setState) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Validade'),
                subtitle: Text(
                  expiresAt == null
                      ? 'Não definida'
                      : '${expiresAt!.day.toString().padLeft(2, '0')}/${expiresAt!.month.toString().padLeft(2, '0')}/${expiresAt!.year}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: expiresAt ?? DateTime.now(),
                    );
                    if (picked != null) {
                      setState(
                        () => expiresAt = DateTime.utc(
                          picked.year,
                          picked.month,
                          picked.day,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final parsed = double.tryParse(quantity.text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return;
    final user = await currentSessionUser(db);
    final warehouse =
        await (db.select(db.warehouses)
              ..where((w) => w.companyId.equals(product.companyId))
              ..where((w) => w.active.equals(true))
              ..limit(1))
            .getSingle();
    final result = await ProductCatalog(db).addStockEntry(
      companyId: product.companyId,
      productId: product.id,
      barcode: code.text,
      quantityMilli: (parsed * 1000).round(),
      warehouseId: warehouse.id,
      deviceId: product.deviceId,
      userId: user.id,
      expiresAt: expiresAt,
    );
    if (!mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      _message('Entrada adicionada.');
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  String _quantity(int milli) {
    final value = milli / 1000;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(3);
  }

  String _movementLabel(String type) => switch (type) {
    'purchase' => 'Compra',
    'sale' => 'Venda',
    'initialStock' => 'Entrada inicial',
    'adjustmentIn' => 'Entrada de stock',
    'adjustmentOut' => 'Saída de stock',
    'returnIn' => 'Devolução',
    _ => type,
  };
}
