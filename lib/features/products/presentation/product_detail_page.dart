import 'package:drift/drift.dart' show Value, Variable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/products/application/product_image_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/products/presentation/product_image.dart';
import 'package:systock/features/inventory/application/inventory_ledger.dart';
import 'package:systock/core/utils/money.dart';

class _BarcodeExpiryTile extends StatefulWidget {
  const _BarcodeExpiryTile({required this.db, required this.barcode});
  final AppDatabase db;
  final ProductBarcode barcode;

  @override
  State<_BarcodeExpiryTile> createState() => _BarcodeExpiryTileState();
}

class _BarcodeExpiryTileState extends State<_BarcodeExpiryTile> {
  late DateTime? expiresAt = widget.barcode.expiresAt;

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: expiresAt ?? DateTime.now(),
    );
    if (picked == null) return;
    final value = DateTime.utc(picked.year, picked.month, picked.day);
    await (widget.db.update(widget.db.productBarcodes)
          ..where((b) => b.id.equals(widget.barcode.id)))
        .write(ProductBarcodesCompanion(expiresAt: Value(value)));
    if (mounted) setState(() => expiresAt = value);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text('Validade · ${widget.barcode.barcode}'),
    subtitle: Text('Quantidade: ${widget.barcode.quantityMilli / 1000}'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          expiresAt == null
              ? 'Não definida'
              : '${expiresAt!.day.toString().padLeft(2, '0')}/${expiresAt!.month.toString().padLeft(2, '0')}/${expiresAt!.year}',
        ),
        IconButton(
          icon: const Icon(Icons.edit_calendar_outlined),
          tooltip: 'Alterar validade'.localized(context),
          onPressed: _pick,
        ),
      ],
    ),
  );
}

class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage(this.id, {super.key});
  final String id;
  Future<
    ({
      Product product,
      List<ProductBarcode> barcodes,
      List<InventoryMovement> movements,
      List<ProductVariant> variants,
      List<Lot> lots,
      List<AuditLog> audits,
      List<SerialNumber> serials,
    })
  >
  load(AppDatabase db) async => (
    product: await (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingle(),
    barcodes:
        await (db.select(db.productBarcodes)
              ..where((b) => b.productId.equals(id))
              ..where((b) => b.deletedAt.isNull()))
            .get(),
    movements: await (db.select(
      db.inventoryMovements,
    )..where((m) => m.productId.equals(id))).get(),
    variants: await (db.select(
      db.productVariants,
    )..where((v) => v.productId.equals(id))).get(),
    lots: await (db.select(
      db.lots,
    )..where((l) => l.productId.equals(id))).get(),
    audits: await (db.select(
      db.auditLogs,
    )..where((a) => a.entityId.equals(id))).get(),
    serials: await (db.select(
      db.serialNumbers,
    )..where((s) => s.productId.equals(id))).get(),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: load(ref.watch(databaseProvider)),
    builder: (context, s) {
      if (!s.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final d = s.data!, db = ref.read(databaseProvider);
      return DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            leading: const AdaptiveBackButton(),
            title: Text(d.product.name),
            actions: [
              IconButton(
                onPressed: () => context.go('/products/${d.product.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar produto'.localized(context),
              ),
              IconButton(
                onPressed: () => _archive(context, db, d.product),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remover produto'.localized(context),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Visão geral'),
                Tab(text: 'Stock'),
                Tab(text: 'Movimentos'),
                Tab(text: 'Compras'),
                Tab(text: 'Vendas'),
                Tab(text: 'Histórico'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Column(
                      children: [
                        if (d.product.imagePath != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: ProductImage(
                              path: d.product.imagePath,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ListTile(
                          title: const LocalizedText('Preço de venda'),
                          trailing: Text(formatMoneyMinor(d.product.saleMinor)),
                        ),
                        ListTile(
                          title: const LocalizedText('Custo'),
                          trailing: Text(formatMoneyMinor(d.product.costMinor)),
                        ),
                        ListTile(
                          title: const LocalizedText('Código de barras'),
                          subtitle: Text(
                            d.barcodes.map((b) => b.barcode).join(', '),
                          ),
                        ),
                        for (final code in d.barcodes)
                          _BarcodeExpiryTile(db: db, barcode: code),
                        FutureBuilder<int>(
                          future: db
                              .customSelect(
                                'SELECT COALESCE(SUM(quantity_milli),0) quantity FROM inventory_balances WHERE product_id=?',
                                variables: [Variable(d.product.id)],
                                readsFrom: {db.inventoryBalances},
                              )
                              .map((row) => row.read<int>('quantity'))
                              .getSingle(),
                          builder: (_, stock) => ListTile(
                            title: const LocalizedText('Quantidade disponível'),
                            trailing: Text(
                              ((stock.data ?? 0) / 1000).toStringAsFixed(3),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _addImage(context, db, d.product),
                        icon: const Icon(Icons.image_outlined),
                        label: const LocalizedText('Imagem'),
                      ),
                    ],
                  ),
                  if (d.serials.isNotEmpty)
                    Card(
                      child: Column(
                        children: [
                          for (final serial in d.serials)
                            ListTile(
                              title: Text(serial.serial),
                              subtitle: Text(serial.imei ?? serial.status),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              _ProductStockTab(db: db, product: d.product),
              ListView(
                children: d.movements.reversed
                    .map(
                      (m) => ListTile(
                        title: Text(m.movementType),
                        subtitle: Text(m.reason ?? ''),
                        trailing: LocalizedText('${m.quantityMilli / 1000}'),
                      ),
                    )
                    .toList(),
              ),
              FutureBuilder(
                future: db
                    .customSelect(
                      '''SELECT p.document_number,p.created_at,pi.quantity_milli,pi.unit_cost_minor FROM purchase_items pi JOIN purchases p ON p.id=pi.purchase_id WHERE pi.product_id=? ORDER BY p.created_at DESC LIMIT 100''',
                      variables: [Variable(id)],
                    )
                    .get(),
                builder: (_, s) => ListView(
                  children: [
                    for (final row in s.data ?? const [])
                      ListTile(
                        title: Text(row.read<String>('document_number')),
                        subtitle: Text(
                          row.read<DateTime>('created_at').toLocal().toString(),
                        ),
                        trailing: LocalizedText(
                          '${row.read<int>('quantity_milli') / 1000} × ${formatMoneyMinor(row.read<int>('unit_cost_minor'))}',
                        ),
                      ),
                  ],
                ),
              ),
              FutureBuilder(
                future: db
                    .customSelect(
                      '''SELECT s.document_number,s.created_at,si.quantity_milli,si.total_minor FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE si.product_id=? ORDER BY s.created_at DESC LIMIT 100''',
                      variables: [Variable(id)],
                    )
                    .get(),
                builder: (_, s) => ListView(
                  children: [
                    for (final row in s.data ?? const [])
                      ListTile(
                        title: Text(row.read<String>('document_number')),
                        subtitle: Text(
                          row.read<DateTime>('created_at').toLocal().toString(),
                        ),
                        trailing: LocalizedText(
                          '${row.read<int>('quantity_milli') / 1000} · ${formatMoneyMinor(row.read<int>('total_minor'))}',
                        ),
                      ),
                  ],
                ),
              ),
              ListView(
                children: [
                  for (final audit in d.audits.reversed)
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(audit.action),
                      subtitle: Text(audit.createdAt.toLocal().toString()),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _addImage(
    BuildContext context,
    AppDatabase db,
    Product product,
  ) async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file?.path == null) return;
    final result = await ProductImageService(
      db,
    ).attach(product: product, sourcePath: file!.path!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Success() => 'Imagem adicionada.',
          Failure(:final error) => error.userMessage,
        }),
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    AppDatabase db,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Remover produto?'),
        content: LocalizedText(
          '${product.name} será arquivado. O histórico de stock, compras e vendas será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ProductCatalog(db).archive(product.id);
    if (!context.mounted) return;
    switch (result) {
      case Success():
        context.go('/products');
      case Failure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }
}

class _ProductStockTab extends StatelessWidget {
  const _ProductStockTab({required this.db, required this.product});
  final AppDatabase db;
  final Product product;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: db
        .customSelect(
          '''SELECT w.id warehouse_id,w.name,COALESCE(b.quantity_milli,0) quantity_milli FROM warehouses w LEFT JOIN inventory_balances b ON b.warehouse_id=w.id AND b.product_id=? WHERE w.company_id=? AND w.deleted_at IS NULL ORDER BY w.name''',
          variables: [Variable(product.id), Variable(product.companyId)],
          readsFrom: {db.warehouses, db.inventoryBalances},
        )
        .watch(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          LocalizedText(
            'Quantidade atual',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final row in snapshot.data!)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.warehouse_outlined),
                ),
                title: Text(row.read<String>('name')),
                subtitle: const LocalizedText(
                  'Saldo calculado pelos movimentos',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (row.read<int>('quantity_milli') / 1000).toStringAsFixed(
                        3,
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Editar quantidade'.localized(context),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _setQuantity(
                        context,
                        row.read<String>('warehouse_id'),
                        row.read<int>('quantity_milli'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Future<void> _setQuantity(
    BuildContext context,
    String warehouseId,
    int currentMilli,
  ) async {
    final quantity = TextEditingController(
      text: (currentMilli / 1000).toStringAsFixed(3),
    );
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Definir quantidade atual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Nova quantidade'.localized(context),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Aplicar ajuste'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final target =
        (double.tryParse(quantity.text.replaceAll(',', '.')) ?? -1) * 1000;
    final targetMilli = target.round();
    final delta = targetMilli - currentMilli;
    if (targetMilli < 0 || delta == 0 || reason.text.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'Informe uma quantidade e um motivo válidos.',
            ),
          ),
        );
      }
      return;
    }
    final user = await currentSessionUser(db);
    final result = await InventoryLedger(db).move(
      companyId: product.companyId,
      productId: product.id,
      warehouseId: warehouseId,
      quantityMilli: delta,
      type: delta > 0
          ? InventoryMovementType.adjustmentIn
          : InventoryMovementType.adjustmentOut,
      deviceId: product.deviceId,
      userId: user.id,
      reason: reason.text,
      allowNegative: product.allowNegativeStock,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Success() => 'Quantidade atualizada com movimento de ajuste.',
          Failure(:final error) => error.userMessage,
        }),
      ),
    );
  }
}
