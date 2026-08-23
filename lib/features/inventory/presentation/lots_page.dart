import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';

class LotsPage extends ConsumerWidget {
  const LotsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Lotes e validades'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => add(context, db),
        icon: const Icon(Icons.add),
        label: const LocalizedText('Novo lote'),
      ),
      body: StreamBuilder<List<Lot>>(
        stream: (db.select(
          db.lots,
        )..orderBy([(l) => OrderingTerm.asc(l.expiresAt)])).watch(),
        builder: (_, snapshot) {
          final lots = snapshot.data ?? const [];
          if (lots.isEmpty) {
            return const Center(
              child: LocalizedText('Nenhum lote registrado.'),
            );
          }
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: lots.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final lot = lots[i], days = lot.expiresAt?.difference(now).inDays;
              final status = days == null
                  ? 'Sem validade'
                  : days < 0
                  ? 'Vencido'
                  : 'Vence em $days dias';
              return ListTile(
                leading: Icon(
                  days != null && days <= 30
                      ? Icons.warning_amber
                      : Icons.inventory_2_outlined,
                ),
                title: Text(lot.batchNumber),
                subtitle: Text(status),
                trailing: Text(lot.productId),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> add(BuildContext context, AppDatabase db) async {
    final products = await db.select(db.products).get(),
        warehouses = await db.select(db.warehouses).get();
    if (products.isEmpty || warehouses.isEmpty || !context.mounted) return;
    var product = products.first, warehouse = warehouses.first;
    final number = TextEditingController(), expiry = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Novo lote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              DropdownButtonFormField(
                initialValue: warehouse.id,
                items: [
                  for (final w in warehouses)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(
                  () => warehouse = warehouses.firstWhere((w) => w.id == v),
                ),
              ),
              TextField(
                controller: number,
                decoration: InputDecoration(
                  labelText: 'Número do lote'.localized(context),
                ),
              ),
              TextField(
                controller: expiry,
                decoration: InputDecoration(
                  labelText: 'Validade (AAAA-MM-DD)'.localized(context),
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
              child: const LocalizedText('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || number.text.trim().isEmpty) return;
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc();
    await db
        .into(db.lots)
        .insert(
          LotsCompanion.insert(
            id: const Uuid().v7(),
            productId: product.id,
            warehouseId: warehouse.id,
            batchNumber: number.text.trim(),
            expiresAt: Value(DateTime.tryParse(expiry.text)?.toUtc()),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
  }
}
