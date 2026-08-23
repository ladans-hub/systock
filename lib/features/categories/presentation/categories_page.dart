import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Categorias'),
        actions: [
          IconButton(
            onPressed: () => add(context, db),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Category>>(
        stream: (db.select(
          db.categories,
        )..where((c) => c.deletedAt.isNull())).watch(),
        builder: (context, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem categorias.'),
            );
          }
          return ListView(
            children: s.data!
                .map(
                  (c) => ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(c.name),
                    subtitle: Text(
                      c.parentId == null
                          ? 'Categoria principal'
                          : 'Subcategoria',
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Future<void> add(BuildContext context, AppDatabase db) async {
    final name = TextEditingController(),
        parents =
            await (db.select(db.categories)
                  ..where((c) => c.parentId.isNull())
                  ..where((c) => c.deletedAt.isNull()))
                .get();
    String? parent;
    if (!context.mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Nova categoria'),
          content: Column(
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
              DropdownButtonFormField<String?>(
                initialValue: parent,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: LocalizedText('Categoria principal'),
                  ),
                  ...parents.map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ),
                ],
                onChanged: (v) => setDialog(() => parent = v),
                decoration: InputDecoration(
                  labelText: 'Categoria pai'.localized(context),
                ),
              ),
            ],
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
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final company = await db.select(db.companies).getSingle(),
          now = DateTime.now().toUtc();
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Uuid().v7(),
              companyId: company.id,
              parentId: Value(parent),
              name: name.text.trim(),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
    }
  }
}
