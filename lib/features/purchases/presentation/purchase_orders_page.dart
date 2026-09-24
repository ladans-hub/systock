import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/purchases/application/purchase_order_service.dart';
import 'package:systock/features/purchases/application/receive_purchase.dart';

class PurchaseOrdersPage extends ConsumerWidget {
  const PurchaseOrdersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const AppBarTitle('Pedidos de compra'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => create(context, db),
        icon: const Icon(Icons.add),
        label: const LocalizedText('Novo pedido'),
      ),
      body: StreamBuilder<List<PurchaseOrder>>(
        stream: (db.select(
          db.purchaseOrders,
        )..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).watch(),
        builder: (_, snapshot) {
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem pedidos de compra.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final order = rows[i];
              return Card(
                child: ListTile(
                  title: Text(order.documentNumber),
                  subtitle: Text(order.status),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoneyMinor(order.totalMinor)),
                      if (order.status == 'draft')
                        TextButton(
                          onPressed: () => PurchaseOrderService(
                            db,
                          ).transition(order.id, 'sent'),
                          child: const LocalizedText('Enviar'),
                        ),
                      if (order.status == 'sent')
                        TextButton(
                          onPressed: () => receive(context, db, order),
                          child: const LocalizedText('Receber'),
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

  Future<void> create(BuildContext context, AppDatabase db) async {
    final suppliers = await db.select(db.suppliers).get(),
        products = await db.select(db.products).get();
    if (suppliers.isEmpty || products.isEmpty || !context.mounted) {
      if (context.mounted) {
        showAppError(context, 'Cadastre fornecedor e produto primeiro.');
      }
      return;
    }
    var supplier = suppliers.first, product = products.first;
    final quantity = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Novo pedido de compra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                initialValue: supplier.id,
                items: [
                  for (final s in suppliers)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(
                  () => supplier = suppliers.firstWhere((s) => s.id == v),
                ),
              ),
              DropdownButtonFormField(
                initialValue: product.id,
                items: [
                  for (final p in products)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(
                  () => product = products.firstWhere((p) => p.id == v),
                ),
              ),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantidade'.localized(context),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final company = await db.select(db.companies).getSingle(),
        user = await currentSessionUser(db);
    final result = await PurchaseOrderService(db).create(
      companyId: company.id,
      supplierId: supplier.id,
      userId: user.id,
      deviceId: company.deviceId,
      lines: [
        PurchaseOrderLine(
          product.id,
          (int.tryParse(quantity.text) ?? 0) * 1000,
          product.costMinor,
        ),
      ],
    );
    if (context.mounted && result is Failure<String>) {
      showAppFailure(context, result.error);
    }
  }

  Future<void> receive(
    BuildContext context,
    AppDatabase db,
    PurchaseOrder order,
  ) async {
    final warehouse = await db.select(db.warehouses).getSingle(),
        user = await currentSessionUser(db);
    final items = await (db.select(
      db.purchaseOrderItems,
    )..where((i) => i.purchaseOrderId.equals(order.id))).get();
    final remaining = [
      for (final item in items)
        PurchaseLineInput(
          productId: item.productId,
          quantityMilli: item.quantityMilli - item.receivedQuantityMilli,
          unitCostMinor: item.unitCostMinor,
        ),
    ].where((l) => l.quantityMilli > 0).toList();
    final result = await ReceivePurchase(db)(
      companyId: order.companyId,
      supplierId: order.supplierId,
      warehouseId: warehouse.id,
      documentNumber: 'COM-${order.documentNumber}',
      userId: user.id,
      deviceId: order.deviceId,
      lines: remaining,
      purchaseOrderId: order.id,
    );
    if (context.mounted) {
      if (result case Failure(:final error)) {
        showAppFailure(context, error);
      } else {
        await showAppAlert(context, 'Pedido recebido e stock atualizado.');
      }
    }
  }
}
