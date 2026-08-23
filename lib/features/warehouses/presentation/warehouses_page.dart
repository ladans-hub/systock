import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';

class WarehousesPage extends ConsumerWidget {
  const WarehousesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Armazéns'),
        actions: [
          FilledButton.icon(
            onPressed: () => add(context, db),
            icon: const Icon(Icons.add),
            label: const LocalizedText('Novo'),
          ),
        ],
      ),
      body: StreamBuilder<List<Warehouse>>(
        stream: (db.select(
          db.warehouses,
        )..where((w) => w.deletedAt.isNull())).watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final w = snapshot.data![i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.warehouse_outlined),
                  ),
                  title: Text(w.name),
                  subtitle: Text(w.code),
                  onTap: () => locations(context, db, w),
                  trailing: Chip(label: Text(w.active ? 'Ativo' : 'Inativo')),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> add(BuildContext context, AppDatabase db) async {
    final name = TextEditingController(), code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const LocalizedText('Novo armazém'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome'.localized(context),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: 'Código'.localized(context),
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
            child: const LocalizedText('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || code.text.trim().isEmpty) {
      return;
    }
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc();
    try {
      await db
          .into(db.warehouses)
          .insert(
            WarehousesCompanion.insert(
              id: const Uuid().v7(),
              companyId: company.id,
              name: name.text.trim(),
              code: code.text.trim().toUpperCase(),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('Já existe um armazém com este código.'),
          ),
        );
      }
    }
  }

  Future<void> locations(
    BuildContext context,
    AppDatabase db,
    Warehouse warehouse,
  ) async {
    final existing = await (db.select(
      db.warehouseLocations,
    )..where((l) => l.warehouseId.equals(warehouse.id))).get();
    if (!context.mounted) return;
    final code = TextEditingController(),
        aisle = TextEditingController(),
        shelf = TextEditingController(),
        position = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: LocalizedText('Localizações · ${warehouse.name}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final location in existing)
                ListTile(
                  title: Text(location.code),
                  subtitle: Text(
                    [
                      location.aisle,
                      location.shelf,
                      location.position,
                    ].whereType<String>().join(' · '),
                  ),
                ),
              const Divider(),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: 'Código (ex.: A-03-04)'.localized(context),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: aisle,
                      decoration: InputDecoration(
                        labelText: 'Corredor'.localized(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: shelf,
                      decoration: InputDecoration(
                        labelText: 'Prateleira'.localized(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: position,
                      decoration: InputDecoration(
                        labelText: 'Posição'.localized(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Fechar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Adicionar'),
          ),
        ],
      ),
    );
    if (add != true || code.text.trim().isEmpty) return;
    final now = DateTime.now().toUtc();
    await db
        .into(db.warehouseLocations)
        .insert(
          WarehouseLocationsCompanion.insert(
            id: const Uuid().v7(),
            warehouseId: warehouse.id,
            code: code.text.trim().toUpperCase(),
            aisle: Value(aisle.text.trim().isEmpty ? null : aisle.text.trim()),
            shelf: Value(shelf.text.trim().isEmpty ? null : shelf.text.trim()),
            position: Value(
              position.text.trim().isEmpty ? null : position.text.trim(),
            ),
            createdAt: now,
            updatedAt: now,
            deviceId: warehouse.deviceId,
          ),
        );
  }
}
