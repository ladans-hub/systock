import 'package:systock/core/widgets/error_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/products/application/product_spreadsheet_service.dart';

class ProductImportPage extends ConsumerStatefulWidget {
  const ProductImportPage({super.key});
  @override
  ConsumerState<ProductImportPage> createState() => _ProductImportPageState();
}

class _ProductImportPageState extends ConsumerState<ProductImportPage> {
  ProductImportPreview? preview;
  final mapping = <int, ProductImportField>{};
  bool busy = false;

  Future<void> select() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
    );
    if (file?.path == null) return;
    setState(() => busy = true);
    final result = await ProductSpreadsheetService(
      ref.read(databaseProvider),
    ).read(file!.path!);
    if (!mounted) return;
    setState(() => busy = false);
    switch (result) {
      case Success(:final value):
        setState(() {
          preview = value;
          mapping.clear();
          for (var i = 0; i < value.headers.length; i++) {
            mapping[i] = _guess(value.headers[i]);
          }
        });
      case Failure(:final error):
        showAppFailure(context, error);
    }
  }

  ProductImportField _guess(String header) {
    final h = header.toLowerCase();
    if (h.contains('nome') || h.contains('descri')) {
      return ProductImportField.name;
    }
    if (h.contains('barra') ||
        h.contains('ean') ||
        h == 'codigo' ||
        h == 'código') {
      return ProductImportField.barcode;
    }
    if (h.contains('custo')) {
      return ProductImportField.cost;
    }
    if (h.contains('preço') || h.contains('preco')) {
      return ProductImportField.price;
    }
    if (h.contains('stock') || h.contains('qtd') || h.contains('quant')) {
      return ProductImportField.stock;
    }
    return ProductImportField.ignore;
  }

  Future<void> import() async {
    final source = preview;
    if (source == null) return;
    setState(() => busy = true);
    final db = ref.read(databaseProvider),
        company = await db.select(db.companies).getSingle();
    final warehouse = await db.select(db.warehouses).getSingle(),
        user = await currentSessionUser(db);
    final result = await ProductSpreadsheetService(db).import(
      preview: source,
      mapping: mapping,
      companyId: company.id,
      warehouseId: warehouse.id,
      userId: user.id,
      deviceId: company.deviceId,
    );
    if (!mounted) return;
    setState(() => busy = false);
    switch (result) {
      case Success(:final value):
        _message(
          '${value.imported} produtos importados. ${value.warnings.length} avisos.',
        );
        Navigator.pop(context);
      case Failure(:final error):
        showAppFailure(context, error);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AdaptiveBackButton(),
      title: const LocalizedText('Importar produtos'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LocalizedText(
          'Selecionar → Mapear colunas → Validar → Importar',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : select,
          icon: const Icon(Icons.upload_file),
          label: const LocalizedText('Selecionar Excel/XLSX'),
        ),
        if (preview != null) ...[
          const SizedBox(height: 24),
          LocalizedText(
            '${preview!.rows.length} linhas encontradas',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var i = 0; i < preview!.headers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview!.headers[i].isEmpty
                                  ? 'Coluna ${i + 1}'
                                  : preview!.headers[i],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<ProductImportField>(
                              initialValue: mapping[i],
                              items: [
                                for (final field in ProductImportField.values)
                                  DropdownMenuItem(
                                    value: field,
                                    child: Text(_label(field)),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => mapping[i] = value!),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final h in preview!.headers) DataColumn(label: Text(h)),
              ],
              rows: [
                for (final row in preview!.rows.take(5))
                  DataRow(
                    cells: [
                      for (var i = 0; i < preview!.headers.length; i++)
                        DataCell(Text(i < row.length ? row[i] : '')),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : import,
            icon: const Icon(Icons.check),
            label: Text(busy ? 'A importar…' : 'Validar e importar'),
          ),
        ],
      ],
    ),
  );

  String _label(ProductImportField field) => switch (field) {
    ProductImportField.ignore => 'Ignorar',
    ProductImportField.name => 'Nome',
    ProductImportField.barcode => 'Código de barras',
    ProductImportField.cost => 'Custo',
    ProductImportField.price => 'Preço',
    ProductImportField.stock => 'Stock inicial',
  };
}
