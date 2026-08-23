import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/security/permission_gate.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/features/products/presentation/product_image.dart';
import 'package:systock/features/transfers/application/transfer_service.dart';

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
                            Text(product.sku ?? 'Sem SKU'),
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
                      onPressed: () => _adjust(db, product),
                      icon: const Icon(Icons.tune),
                      label: const LocalizedText('Ajustar stock'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _transfer(db, product),
                      icon: const Icon(Icons.swap_horiz),
                      label: const LocalizedText('Transferir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/inventory/counts'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const LocalizedText('Contagem física'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/inventory/lots'),
                      icon: const Icon(Icons.inventory_outlined),
                      label: const LocalizedText('Lotes e validade'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'Saldo por armazém',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              StreamBuilder(
                stream: db
                    .customSelect(
                      '''SELECT w.id,w.name,COALESCE(b.quantity_milli,0) quantity FROM warehouses w LEFT JOIN inventory_balances b ON b.warehouse_id=w.id AND b.product_id=? WHERE w.company_id=? AND w.deleted_at IS NULL ORDER BY w.name''',
                      variables: [
                        Variable(product.id),
                        Variable(product.companyId),
                      ],
                      readsFrom: {db.warehouses, db.inventoryBalances},
                    )
                    .watch(),
                builder: (_, balances) => Card(
                  child: Column(
                    children: [
                      for (final row in balances.data ?? const [])
                        ListTile(
                          leading: const Icon(Icons.warehouse_outlined),
                          title: Text(row.read<String>('name')),
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
                          ),
                          title: Text(_movementLabel(movement.movementType)),
                          subtitle: Text(movement.reason ?? 'Sem observação'),
                          trailing: LocalizedText(
                            '${movement.quantityMilli >= 0 ? '+' : ''}${_quantity(movement.quantityMilli)}',
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
                      child: LocalizedText('Remover'),
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
    _message(switch (result) {
      Success() => 'Stock atualizado com movimento auditável.',
      Failure(:final error) => error.userMessage,
    });
  }

  Future<void> _transfer(AppDatabase db, Product product) async {
    final warehouses =
        await (db.select(db.warehouses)
              ..where((w) => w.deletedAt.isNull())
              ..where((w) => w.active.equals(true)))
            .get();
    if (!mounted || warehouses.length < 2) {
      _message('Cadastre pelo menos dois armazéns para transferir stock.');
      return;
    }
    var source = warehouses.first.id, destination = warehouses[1].id;
    final quantity = TextEditingController(text: '1');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: LocalizedText('Transferir ${product.name}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _warehouseField(
                  'Origem',
                  source,
                  warehouses,
                  (value) => setDialogState(() => source = value!),
                ),
                const SizedBox(height: 12),
                _warehouseField(
                  'Destino',
                  destination,
                  warehouses,
                  (value) => setDialogState(() => destination = value!),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: source == destination
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const LocalizedText('Criar transferência'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final milli =
        ((double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) * 1000)
            .round();
    final company = await db.select(db.companies).getSingle();
    final user =
        await (db.select(db.users)
              ..where((u) => u.active.equals(true))
              ..limit(1))
            .getSingle();
    final number = await DocumentNumberService(db).next(
      companyId: company.id,
      type: 'transfer',
      prefix: 'TRF',
      deviceId: company.deviceId,
    );
    final result = await TransferService(db).create(
      companyId: company.id,
      sourceWarehouseId: source,
      destinationWarehouseId: destination,
      documentNumber: number,
      userId: user.id,
      deviceId: company.deviceId,
      lines: [TransferLine(product.id, milli)],
    );
    if (!mounted) return;
    _message(switch (result) {
      Success() => 'Transferência criada como rascunho.',
      Failure(:final error) => error.userMessage,
    });
  }

  Widget _warehouseField(
    String label,
    String value,
    List<Warehouse> warehouses,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final warehouse in warehouses)
        DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
    ],
    onChanged: changed,
  );

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
    'adjustment_in' => 'Ajuste de entrada',
    'adjustment_out' => 'Ajuste de saída',
    'transfer_in' => 'Transferência recebida',
    'transfer_out' => 'Transferência expedida',
    'return' => 'Devolução',
    _ => type,
  };
}
