import 'package:systock/core/utils/quantity.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/products/application/product_image_service.dart';
import 'package:systock/features/products/presentation/product_image.dart';

class _LotExpiryEditor extends StatefulWidget {
  const _LotExpiryEditor({
    required this.db,
    required this.lot,
    required this.onChanged,
  });
  final AppDatabase db;
  final Lot lot;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_LotExpiryEditor> createState() => _LotExpiryEditorState();
}

class _LotExpiryEditorState extends State<_LotExpiryEditor> {
  late DateTime? expiresAt = widget.lot.expiresAt;

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: expiresAt ?? DateTime.now(),
    );
    if (picked == null) return;
    final value = DateTime.utc(picked.year, picked.month, picked.day);
    await (widget.db.update(
      widget.db.lots,
    )..where((l) => l.id.equals(widget.lot.id))).write(
      LotsCompanion(
        expiresAt: Value(value),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    if (mounted) setState(() => expiresAt = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('Lote: ${widget.lot.batchNumber}'),
    subtitle: Text(
      expiresAt == null
          ? 'Validade não definida'
          : 'Validade: ${expiresAt!.day.toString().padLeft(2, '0')}/${expiresAt!.month.toString().padLeft(2, '0')}/${expiresAt!.year}',
    ),
    trailing: IconButton(
      icon: const Icon(Icons.edit_calendar_outlined),
      onPressed: _pick,
    ),
  );
}

class ProductEditPage extends ConsumerStatefulWidget {
  const ProductEditPage(this.id, {super.key});
  final String id;

  @override
  ConsumerState<ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends ConsumerState<ProductEditPage> {
  Product? product;
  List<Category> categories = const [];
  List<Brand> brands = const [];
  List<Unit> units = const [];
  List<Lot> lots = const [];
  List<Warehouse> warehouses = const [];
  final balances = <String, int>{};
  String? warehouseId;
  final quantity = TextEditingController();
  final price = TextEditingController();
  bool get isKg =>
      units.where((u) => u.id == unitId).firstOrNull?.code.toUpperCase() ==
      'KG';
  final name = TextEditingController();
  final description = TextEditingController();
  final barcode = TextEditingController();
  final location = TextEditingController();
  final shelf = TextEditingController();
  String? categoryId, brandId, unitId, selectedImage;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final loaded = await (db.select(
      db.products,
    )..where((p) => p.id.equals(widget.id))).getSingle();
    final primaryBarcode =
        await (db.select(db.productBarcodes)
              ..where((b) => b.productId.equals(widget.id))
              ..where((b) => b.primaryBarcode.equals(true))
              ..limit(1))
            .getSingleOrNull();
    categories = await db.select(db.categories).get();
    brands = await db.select(db.brands).get();
    units = await db.select(db.units).get();
    lots =
        await (db.select(db.lots)
              ..where((l) => l.productId.equals(widget.id))
              ..where((l) => l.deletedAt.isNull()))
            .get();
    warehouses =
        await (db.select(db.warehouses)..where(
              (w) =>
                  w.companyId.equals(loaded.companyId) &
                  w.active.equals(true) &
                  w.deletedAt.isNull(),
            ))
            .get();
    final stock = await (db.select(
      db.inventoryBalances,
    )..where((b) => b.productId.equals(widget.id))).get();
    balances.addEntries(
      stock.map((b) => MapEntry(b.warehouseId, b.quantityMilli)),
    );
    warehouseId = warehouses.firstOrNull?.id;
    quantity.text = formatQuantity(balances[warehouseId] ?? 0);
    price.text =
        '${loaded.saleMinor ~/ 100},${(loaded.saleMinor % 100).toString().padLeft(2, '0')}';
    product = loaded;
    name.text = loaded.name;
    description.text = loaded.description ?? '';
    barcode.text = primaryBarcode?.barcode ?? '';
    location.text = loaded.location ?? '';
    shelf.text = loaded.shelf ?? '';
    categoryId = loaded.categoryId;
    brandId = loaded.brandId;
    unitId = loaded.unitId;
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file?.path != null && mounted) {
      setState(() => selectedImage = file!.path);
    }
  }

  Future<void> _save() async {
    final current = product;
    if (current == null || saving) return;
    int saleMinor = current.saleMinor;
    int? targetQuantity;
    try {
      if (isKg) {
        if (!RegExp(r'^\d+([,.]\d{1,2})?$').hasMatch(price.text.trim())) {
          throw const FormatException('Informe um preço por kg válido.');
        }
        saleMinor = parseMoneyMinor(price.text);
        if (current.trackStock) {
          final parsed = parseQuantityMilli(quantity.text);
          if (warehouseId == null) {
            throw const FormatException('Cadastre um armazém ativo.');
          }
          if (parsed != (balances[warehouseId] ?? 0)) targetQuantity = parsed;
        }
      }
    } on FormatException catch (error) {
      await showAppError(context, error.message);
      return;
    }
    setState(() => saving = true);
    final db = ref.read(databaseProvider);
    final user = targetQuantity == null ? null : await currentSessionUser(db);
    final result = await ProductCatalog(db).updateComplete(
      current: current,
      name: name.text,
      description: description.text,
      sku: current.sku,
      categoryId: categoryId,
      brandId: brandId,
      unitId: unitId,
      costMinor: current.costMinor,
      saleMinor: saleMinor,
      quantityMilli: targetQuantity,
      expectedQuantityMilli: targetQuantity == null
          ? null
          : balances[warehouseId] ?? 0,
      warehouseId: warehouseId,
      userId: user?.id,
      wholesaleMinor: current.wholesaleMinor,
      minimumPriceMinor: current.minimumPriceMinor,
      minimumStockMilli: current.minimumStockMilli,
      maximumStockMilli: current.maximumStockMilli,
      location: location.text,
      shelf: shelf.text,
      trackStock: current.trackStock,
      allowNegativeStock: current.allowNegativeStock,
      active: current.active,
      barcode: barcode.text,
    );
    if (result case Success()) {
      if (selectedImage != null) {
        final updated = await (db.select(
          db.products,
        )..where((p) => p.id.equals(widget.id))).getSingle();
        final imageResult = await ProductImageService(
          db,
        ).attach(product: updated, sourcePath: selectedImage!);
        if (imageResult case Failure(:final error)) {
          if (mounted) setState(() => saving = false);
          if (mounted) await showAppFailure(context, error);
          return;
        }
      }
      if (mounted) context.go('/products/${widget.id}');
      return;
    }
    if (mounted) setState(() => saving = false);
    if (mounted) await showAppFailure(context, (result as Failure<void>).error);
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      description,
      barcode,
      location,
      shelf,
      quantity,
      price,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final imagePath = selectedImage ?? product?.imagePath;
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Editar produto'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Align(
            heightFactor: 1,
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 280,
              child: AdaptivePrimaryButton(
                prominent: true,
                label: saving ? 'A guardar…' : 'Guardar alterações',
                onPressed: saving ? null : _save,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 180,
                height: 150,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: imagePath == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 40),
                          SizedBox(height: 8),
                          LocalizedText('Adicionar imagem'),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          ProductImage(
                            path: imagePath,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            borderRadius: 0,
                          ),
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: ColoredBox(
                              color: Color(0xB0000000),
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: LocalizedText(
                                    'Alterar imagem',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const LocalizedText('Edição segura'),
              subtitle: const LocalizedText(
                'Ao selecionar KG, pode definir o preço por kg e ajustar a quantidade existente com registo no histórico.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Informações gerais',
            children: [
              _field(name, 'Nome *'),
              _field(description, 'Descrição', lines: 3),
              _dropdown(
                'Categoria',
                categoryId,
                categories.map((e) => (e.id, e.name)).toList(),
                (value) => setState(() => categoryId = value),
              ),
              _dropdown(
                'Marca',
                brandId,
                brands.map((e) => (e.id, e.name)).toList(),
                (value) => setState(() => brandId = value),
              ),
              _dropdown(
                'Unidade',
                unitId,
                units.map((e) => (e.id, '${e.code} · ${e.name}')).toList(),
                (value) => setState(() => unitId = value),
              ),
            ],
          ),
          if (isKg) ...[
            const SizedBox(height: 14),
            _Section(
              title: 'Venda por peso',
              children: [
                if (product!.trackStock) ...[
                  _dropdown(
                    'Armazém',
                    warehouseId,
                    warehouses.map((w) => (w.id, w.name)).toList(),
                    (value) => setState(() {
                      warehouseId = value;
                      quantity.text = formatQuantity(balances[value] ?? 0);
                    }),
                  ),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade existente (kg)',
                      suffixText: 'kg',
                      helperText:
                          'Total disponível neste armazém. Aceita até 3 casas decimais.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preço por kg',
                    suffixText: 'MT/kg',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _Section(
            title: 'Localização',
            children: [
              _field(location, 'Localização'),
              _field(shelf, 'Prateleira'),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Lotes e validades',
            children: [
              if (lots.isEmpty) const LocalizedText('Nenhum lote registrado.'),
              for (final lot in lots)
                _LotExpiryEditor(
                  db: ref.read(databaseProvider),
                  lot: lot,
                  onChanged: (value) => setState(() {
                    final index = lots.indexWhere((item) => item.id == lot.id);
                    if (index >= 0) {
                      lots[index] = lot.copyWith(expiresAt: Value(value));
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _dropdown(
    String label,
    String? value,
    List<(String, String)> options,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(
          value: null,
          child: LocalizedText('Não definido'),
        ),
        for (final option in options)
          DropdownMenuItem(value: option.$1, child: Text(option.$2)),
      ],
      onChanged: changed,
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}
