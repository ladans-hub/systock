import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/purchases/application/receive_purchase.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:uuid/uuid.dart';

class PurchasesPage extends ConsumerWidget {
  const PurchasesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        query = db.select(db.purchases)
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
          ..limit(100);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Compras'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/purchases/orders'),
            icon: const Icon(Icons.description_outlined),
            label: const LocalizedText('Pedidos'),
          ),
          IconButton(
            onPressed: () => _supplier(context, db),
            icon: const Icon(Icons.person_add),
            tooltip: 'Novo fornecedor'.localized(context),
          ),
          FilledButton.icon(
            onPressed: () => _receive(context, db),
            icon: const Icon(Icons.add),
            label: const LocalizedText('Receber compra'),
          ),
        ],
      ),
      body: StreamBuilder<List<Purchase>>(
        stream: query.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem compras.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = snapshot.data![i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_shipping_outlined),
                  ),
                  onTap: () => context.go('/purchases/${p.id}'),
                  title: Text(p.documentNumber),
                  subtitle: LocalizedText(
                    '${p.createdAt.toLocal()} • ${p.status}',
                  ),
                  trailing: Text(formatMoneyMinor(p.totalMinor)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _supplier(BuildContext context, AppDatabase db) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const LocalizedText('Novo fornecedor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Nome'.localized(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const LocalizedText('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc();
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: const Uuid().v7(),
            companyId: company.id,
            name: controller.text.trim(),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
  }

  Future<void> _receive(BuildContext context, AppDatabase db) async {
    final suppliers = await db.select(db.suppliers).get(),
        products = await (db.select(
          db.products,
        )..where((p) => p.deletedAt.isNull())).get();
    if (suppliers.isEmpty || products.isEmpty) {
      if (context.mounted) {
        showAppError(
          context,
          'Cadastre pelo menos um fornecedor e um produto.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    String supplier = suppliers.first.id, product = products.first.id;
    final quantity = TextEditingController(text: '1'),
        cost = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Receber compra'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: supplier,
                  items: suppliers
                      .map(
                        (s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => supplier = v!),
                  decoration: InputDecoration(
                    labelText: 'Fornecedor'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
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
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantidade'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Custo unitário'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const LocalizedText('Receber'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final company = await db.select(db.companies).getSingle(),
        warehouse = await db.select(db.warehouses).getSingle(),
        user = await currentSessionUser(db);
    final documentNumber = await DocumentNumberService(db).next(
      companyId: company.id,
      type: 'purchase',
      prefix: 'COM',
      deviceId: company.deviceId,
    );
    final q =
            ((double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) * 1000)
                .round(),
        unit = ((double.tryParse(cost.text.replaceAll(',', '.')) ?? 0) * 100)
            .round();
    final result = await ReceivePurchase(db)(
      companyId: company.id,
      supplierId: supplier,
      warehouseId: warehouse.id,
      documentNumber: documentNumber,
      userId: user.id,
      deviceId: company.deviceId,
      lines: [
        PurchaseLineInput(
          productId: product,
          quantityMilli: q,
          unitCostMinor: unit,
        ),
      ],
    );
    if (context.mounted) {
      if (result case Failure(:final error)) {
        showAppFailure(context, error);
      }
    }
  }
}
