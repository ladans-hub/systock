import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/stock_count_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/core/database/document_number_service.dart';

class StockCountsPage extends ConsumerWidget {
  const StockCountsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        q = db.select(db.stockCounts)
          ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Inventário físico'),
        actions: [
          FilledButton.icon(
            onPressed: () => create(context, db),
            icon: const Icon(Icons.add),
            label: const LocalizedText('Iniciar'),
          ),
        ],
      ),
      body: StreamBuilder<List<StockCount>>(
        stream: q.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem inventários.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = snapshot.data![i];
              return Card(
                child: ListTile(
                  onTap: () => context.go('/inventory/counts/${c.id}'),
                  leading: const CircleAvatar(
                    child: Icon(Icons.fact_check_outlined),
                  ),
                  title: Text(c.documentNumber),
                  subtitle: Text(c.status),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> create(BuildContext context, AppDatabase db) async {
    final warehouses = await db.select(db.warehouses).get();
    if (warehouses.isEmpty) return;
    String selected = warehouses.first.id;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Iniciar inventário'),
          content: DropdownButtonFormField(
            initialValue: selected,
            items: warehouses
                .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
                .toList(),
            onChanged: (v) => setDialog(() => selected = v!),
            decoration: InputDecoration(
              labelText: 'Armazém'.localized(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const LocalizedText('Criar snapshot'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final company = await db.select(db.companies).getSingle(),
        user = await db.select(db.users).getSingle();
    final documentNumber = await DocumentNumberService(db).next(
      companyId: company.id,
      type: 'stock_count',
      prefix: 'INV',
      deviceId: company.deviceId,
    );
    final result = await StockCountService(db).create(
      companyId: company.id,
      warehouseId: selected,
      documentNumber: documentNumber,
      userId: user.id,
      deviceId: company.deviceId,
    );
    if (context.mounted) {
      switch (result) {
        case Success(:final value):
          context.go('/inventory/counts/$value');
        case Failure(:final error):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    }
  }
}
