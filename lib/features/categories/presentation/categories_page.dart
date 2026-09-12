import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/core/widgets/action_colors.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:uuid/uuid.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const LocalizedText('Categorias e marcas'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categorias'),
              Tab(text: 'Marcas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_categories(context, db), _brands(context, db)],
        ),
      ),
    );
  }

  Widget _categories(BuildContext context, AppDatabase db) => StreamBuilder(
    stream:
        (db.select(db.categories)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .watch(),
    builder: (context, snapshot) => _CatalogList(
      emptyText: 'Ainda não existem categorias.',
      addLabel: 'Nova categoria',
      rows: [
        for (final item in snapshot.data ?? const <Category>[])
          _CatalogRow(
            name: item.name,
            icon: Icons.category_outlined,
            onEdit: () => _editCategory(context, db, item),
            onDelete: () => _deleteCategory(context, db, item),
          ),
      ],
      onAdd: () => _editCategory(context, db),
    ),
  );

  Widget _brands(BuildContext context, AppDatabase db) => StreamBuilder(
    stream:
        (db.select(db.brands)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .watch(),
    builder: (context, snapshot) => _CatalogList(
      emptyText: 'Ainda não existem marcas.',
      addLabel: 'Nova marca',
      rows: [
        for (final item in snapshot.data ?? const <Brand>[])
          _CatalogRow(
            name: item.name,
            icon: Icons.sell_outlined,
            onEdit: () => _editBrand(context, db, item),
            onDelete: () => _deleteBrand(context, db, item),
          ),
      ],
      onAdd: () => _editBrand(context, db),
    ),
  );

  Future<void> _editCategory(
    BuildContext context,
    AppDatabase db, [
    Category? item,
  ]) async {
    final name = TextEditingController(text: item?.name);
    if (!await _nameDialog(
          context,
          item == null ? 'Nova categoria' : 'Editar categoria',
          name,
        ) ||
        name.text.trim().isEmpty) {
      return;
    }
    try {
      final now = DateTime.now().toUtc();
      if (item == null) {
        final company = await db.select(db.companies).getSingle();
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: const Uuid().v7(),
                companyId: company.id,
                name: name.text.trim(),
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
            );
      } else {
        await (db.update(
          db.categories,
        )..where((row) => row.id.equals(item.id))).write(
          CategoriesCompanion(
            name: Value(name.text.trim()),
            updatedAt: Value(now),
            version: Value(item.version + 1),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, 'Já existe uma categoria com este nome.');
      }
    }
  }

  Future<void> _editBrand(
    BuildContext context,
    AppDatabase db, [
    Brand? item,
  ]) async {
    final name = TextEditingController(text: item?.name);
    if (!await _nameDialog(
          context,
          item == null ? 'Nova marca' : 'Editar marca',
          name,
        ) ||
        name.text.trim().isEmpty) {
      return;
    }
    try {
      final now = DateTime.now().toUtc();
      if (item == null) {
        final company = await db.select(db.companies).getSingle();
        await db
            .into(db.brands)
            .insert(
              BrandsCompanion.insert(
                id: const Uuid().v7(),
                companyId: company.id,
                name: name.text.trim(),
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
            );
      } else {
        await (db.update(
          db.brands,
        )..where((row) => row.id.equals(item.id))).write(
          BrandsCompanion(
            name: Value(name.text.trim()),
            updatedAt: Value(now),
            version: Value(item.version + 1),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, 'Já existe uma marca com este nome.');
      }
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    AppDatabase db,
    Category item,
  ) async {
    if (!await _confirmDelete(context, item.name)) return;
    await db.transaction(() async {
      await (db.update(db.products)..where((p) => p.categoryId.equals(item.id)))
          .write(const ProductsCompanion(categoryId: Value(null)));
      await (db.update(db.categories)..where((c) => c.parentId.equals(item.id)))
          .write(const CategoriesCompanion(parentId: Value(null)));
      await (db.delete(db.categories)..where((c) => c.id.equals(item.id))).go();
    });
  }

  Future<void> _deleteBrand(
    BuildContext context,
    AppDatabase db,
    Brand item,
  ) async {
    if (!await _confirmDelete(context, item.name)) return;
    await db.transaction(() async {
      await (db.update(db.products)..where((p) => p.brandId.equals(item.id)))
          .write(const ProductsCompanion(brandId: Value(null)));
      await (db.delete(db.brands)..where((b) => b.id.equals(item.id))).go();
    });
  }

  Future<bool> _nameDialog(
    BuildContext context,
    String title,
    TextEditingController controller,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: LocalizedText(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Nome'.localized(context)),
            onSubmitted: (_) => Navigator.pop(dialog, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Salvar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmDelete(BuildContext context, String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const LocalizedText('Remover registro?'),
          content: LocalizedText(
            '$name será removido dos produtos existentes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: removalActionColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Remover'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(BuildContext context, String text) =>
      showAppError(context, text);
}

class _CatalogRow {
  const _CatalogRow({
    required this.name,
    required this.icon,
    required this.onEdit,
    required this.onDelete,
  });
  final String name;
  final IconData icon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
}

class _CatalogList extends StatefulWidget {
  const _CatalogList({
    required this.rows,
    required this.emptyText,
    required this.addLabel,
    required this.onAdd,
  });
  final List<_CatalogRow> rows;
  final String emptyText;
  final String addLabel;
  final VoidCallback onAdd;
  @override
  State<_CatalogList> createState() => _CatalogListState();
}

class _CatalogListState extends State<_CatalogList> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rows
        .where((row) => row.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: AdaptiveSearchField(
              hintText: 'Pesquisar categorias ou marcas'.localized(context),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: widget.rows.isEmpty
                ? Center(child: LocalizedText(widget.emptyText))
                : filtered.isEmpty
                ? const Center(child: Text('Nenhum resultado encontrado.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final row = filtered[index];
                      return ListTile(
                        leading: Icon(row.icon),
                        title: Text(row.name),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) =>
                              action == 'edit' ? row.onEdit() : row.onDelete(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: LocalizedText('Editar'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: LocalizedText(
                                'Remover',
                                style: TextStyle(color: removalActionColor),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAdd,
        icon: const Icon(Icons.add),
        label: LocalizedText(widget.addLabel),
      ),
    );
  }
}
