import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/transfers/application/transfer_service.dart';
import 'package:systock/core/database/document_number_service.dart';

class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        q = db.select(db.stockTransfers)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Transferências'),
        actions: [
          FilledButton.icon(
            onPressed: () => create(context, db),
            icon: const Icon(Icons.add),
            label: const LocalizedText('Nova'),
          ),
        ],
      ),
      body: StreamBuilder<List<StockTransfer>>(
        stream: q.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem transferências.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = snapshot.data![i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
                  title: Text(t.documentNumber),
                  subtitle: Text(t.status),
                  trailing: Wrap(
                    children: [
                      if (t.status == 'draft')
                        FilledButton(
                          onPressed: () => act(
                            context,
                            TransferService(
                              db,
                            ).dispatch(t.id, userId: t.createdBy),
                          ),
                          child: const LocalizedText('Expedir'),
                        ),
                      if (t.status == 'in_transit')
                        FilledButton(
                          onPressed: () => act(
                            context,
                            TransferService(
                              db,
                            ).receive(t.id, userId: t.createdBy),
                          ),
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

  Future<void> act(BuildContext context, Future<Result<void>> operation) async {
    final result = await operation;
    if (context.mounted) {
      if (result case Failure(:final error)) {
        showAppFailure(context, error);
      }
    }
  }

  Future<void> create(BuildContext context, AppDatabase db) async {
    final warehouses = await (db.select(
          db.warehouses,
        )..where((w) => w.active.equals(true))).get(),
        products = await (db.select(
          db.products,
        )..where((p) => p.deletedAt.isNull())).get();
    if (warehouses.length < 2 || products.isEmpty) {
      if (context.mounted) {
        showAppError(context, 'Cadastre dois armazéns e um produto primeiro.');
      }
      return;
    }
    if (!context.mounted) return;
    String source = warehouses.first.id,
        destination = warehouses[1].id,
        product = products.first.id;
    final quantity = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Nova transferência'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: source,
                  items: warehouses
                      .map(
                        (w) =>
                            DropdownMenuItem(value: w.id, child: Text(w.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => source = v!),
                  decoration: InputDecoration(
                    labelText: 'Origem'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: destination,
                  items: warehouses
                      .map(
                        (w) =>
                            DropdownMenuItem(value: w.id, child: Text(w.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => destination = v!),
                  decoration: InputDecoration(
                    labelText: 'Destino'.localized(context),
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
              child: const LocalizedText('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final company = await db.select(db.companies).getSingle(),
        user = await currentSessionUser(db);
    final documentNumber = await DocumentNumberService(db).next(
      companyId: company.id,
      type: 'transfer',
      prefix: 'TRF',
      deviceId: company.deviceId,
    );
    final result = await TransferService(db).create(
      companyId: company.id,
      sourceWarehouseId: source,
      destinationWarehouseId: destination,
      documentNumber: documentNumber,
      userId: user.id,
      deviceId: company.deviceId,
      lines: [
        TransferLine(
          product,
          ((double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) * 1000)
              .round(),
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
