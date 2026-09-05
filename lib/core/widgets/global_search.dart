import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/widgets/platform_controls.dart';

class GlobalSearchResult {
  const GlobalSearchResult(
    this.type,
    this.id,
    this.title,
    this.subtitle,
    this.route,
  );
  final String type, id, title, subtitle, route;
}

class GlobalSearchDelegate extends SearchDelegate<GlobalSearchResult?> {
  GlobalSearchDelegate(this.db);
  final AppDatabase db;

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  Future<List<GlobalSearchResult>> search() async {
    if (query.trim().isEmpty) return const [];
    final term = '%${query.trim().toLowerCase()}%';
    final rows = await db.customSelect('''
      SELECT 'Produto' type,p.id,p.name title,COALESCE((SELECT barcode FROM product_barcodes b WHERE b.product_id=p.id AND b.deleted_at IS NULL ORDER BY b.primary_barcode DESC LIMIT 1),'') subtitle,'/products/'||p.id route FROM products p WHERE p.deleted_at IS NULL AND (lower(p.name) LIKE ? OR EXISTS(SELECT 1 FROM product_barcodes b WHERE b.product_id=p.id AND b.deleted_at IS NULL AND lower(b.barcode) LIKE ?))
      UNION ALL SELECT 'Cliente',id,name,COALESCE(phone,''),'/customers' FROM customers WHERE deleted_at IS NULL AND lower(name) LIKE ?
      UNION ALL SELECT 'Fornecedor',id,name,COALESCE(phone,''),'/suppliers' FROM suppliers WHERE deleted_at IS NULL AND lower(name) LIKE ?
      UNION ALL SELECT 'Venda',id,document_number,status,'/sales/'||id FROM sales WHERE lower(document_number) LIKE ?
      UNION ALL SELECT 'Compra',id,document_number,status,'/purchases' FROM purchases WHERE lower(document_number) LIKE ?
      UNION ALL SELECT 'Transferência',id,document_number,status,'/transfers' FROM stock_transfers WHERE lower(document_number) LIKE ?
      LIMIT 50
    ''', variables: List.generate(7, (_) => Variable(term))).get();
    return [
      for (final row in rows)
        GlobalSearchResult(
          row.read('type'),
          row.read('id'),
          row.read('title'),
          row.read('subtitle'),
          row.read('route'),
        ),
    ];
  }

  @override
  String get searchFieldLabel => 'Produto, cliente, venda, compra…';
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) => FutureBuilder(
    future: search(),
    builder: (_, snapshot) => ListView(
      children: [
        for (final item in snapshot.data ?? const [])
          ListTile(
            leading: const AdaptiveIcon(PlatformGlyph.search),
            title: Text(item.title),
            subtitle: LocalizedText('${item.type} · ${item.subtitle}'),
            onTap: () {
              close(context, item);
              context.go(item.route);
            },
          ),
      ],
    ),
  );
}

Future<void> showCommandPalette(BuildContext context, AppDatabase db) async {
  await showDialog<void>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const LocalizedText('Ações rápidas'),
      children: [
        _command(
          dialog,
          context,
          Icons.add_box_outlined,
          'Adicionar produto',
          '/products',
        ),
        _command(dialog, context, Icons.point_of_sale, 'Nova venda', '/pos'),
        _command(
          dialog,
          context,
          Icons.shopping_cart_outlined,
          'Nova compra',
          '/purchases',
        ),
        SimpleDialogOption(
          onPressed: () {
            Navigator.pop(dialog);
            showSearch(context: context, delegate: GlobalSearchDelegate(db));
          },
          child: const ListTile(
            leading: Icon(Icons.search),
            title: LocalizedText('Pesquisa global'),
          ),
        ),
        _command(dialog, context, Icons.sync, 'Sincronizar', '/settings/sync'),
      ],
    ),
  );
}

Widget _command(
  BuildContext dialog,
  BuildContext root,
  IconData icon,
  String label,
  String route,
) => SimpleDialogOption(
  onPressed: () {
    Navigator.pop(dialog);
    root.go(route);
  },
  child: ListTile(leading: Icon(icon), title: Text(label)),
);
