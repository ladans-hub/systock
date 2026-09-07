import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/core/utils/money.dart';
import 'package:file_picker/file_picker.dart' as picker;
import 'package:systock/features/products/application/product_spreadsheet_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/products/application/product_image_service.dart';
import 'package:systock/features/products/presentation/product_image.dart';
import 'package:systock/core/widgets/async_state_pane.dart';
import 'package:systock/core/files/file_save_service.dart';
import 'package:systock/features/inventory/presentation/stock_movement_analytics.dart';
import 'package:uuid/uuid.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});
  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String search = '';
  int limit = 50;
  Timer? _debounce;
  final _scroll = ScrollController();
  int _loadedProductCount = 0;
  bool gridView = false;
  bool favoritesOnly = false;
  final favorites = <String>{};
  bool summaryExpanded = false;
  AnalyticsPeriod period = AnalyticsPeriod.thirtyDays;
  DateTimeRange? customRange;
  ProductChartMode productMode = ProductChartMode.moved;

  DateTimeRange get analyticsRange => rangeForPeriod(period, customRange);

  Future<void> _changePeriod(AnalyticsPeriod value) async {
    if (value != AnalyticsPeriod.custom) {
      setState(() => period = value);
      return;
    }
    final initial = customRange ?? analyticsRange;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: initial.start,
        end: initial.end.subtract(const Duration(days: 1)),
      ),
    );
    if (selected == null) return;
    setState(() {
      period = value;
      customRange = DateTimeRange(
        start: DateTime(
          selected.start.year,
          selected.start.month,
          selected.start.day,
        ),
        end: DateTime(
          selected.end.year,
          selected.end.month,
          selected.end.day,
        ).add(const Duration(days: 1)),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreFavorites);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500 && _loadedProductCount >= limit) {
        setState(() => limit += 50);
      }
    });
  }

  Future<void> _restoreFavorites() async {
    final db = ref.read(databaseProvider);
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('pos.favorites'))).getSingleOrNull();
    if (setting == null) return;
    try {
      favorites.addAll(
        (jsonDecode(setting.valueJson) as List<dynamic>).cast<String>(),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleFavorite(String productId) async {
    setState(() {
      if (!favorites.add(productId)) favorites.remove(productId);
    });
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'pos.favorites',
            valueJson: jsonEncode(favorites.toList()),
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          search = value;
          limit = 50;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Produtos'),
        actions: [
          IconButton(
            onPressed: () => setState(() => gridView = false),
            icon: Icon(gridView ? Icons.view_list_outlined : Icons.view_list),
            tooltip: 'Ver como lista'.localized(context),
          ),
          IconButton(
            onPressed: () => setState(() => gridView = true),
            icon: Icon(gridView ? Icons.grid_view : Icons.grid_view_outlined),
            tooltip: 'Ver como grelha'.localized(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'import') {
                context.go('/products/import');
              } else if (value == 'labels') {
                context.go('/products/labels');
              } else if (value == 'category') {
                await _createCategory(context, db);
              } else if (value == 'brand') {
                await _createBrand(context, db);
              } else if (value == 'manage-taxonomy') {
                if (context.mounted) context.go('/categories');
              } else {
                await _export(context, db);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import',
                child: LocalizedText('Importar Excel'),
              ),
              PopupMenuItem(
                value: 'export',
                child: LocalizedText('Exportar XLSX'),
              ),
              PopupMenuItem(
                value: 'labels',
                child: LocalizedText('Imprimir etiquetas'),
              ),
              PopupMenuItem(
                value: 'category',
                child: LocalizedText('Cadastrar categoria'),
              ),
              PopupMenuItem(
                value: 'brand',
                child: LocalizedText('Cadastrar marca'),
              ),
              PopupMenuItem(
                value: 'manage-taxonomy',
                child: LocalizedText('Gerir categorias e marcas'),
              ),
            ],
          ),
          IconButton(
            onPressed: () => _add(context, db),
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar produto'.localized(context),
          ),
        ],
      ),
      body: FutureBuilder(
        future: db.select(db.companies).getSingleOrNull(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorPane(onRetry: () => setState(() {}));
          }
          final company = snapshot.data;
          if (company == null) {
            return const AsyncLoadingPane();
          }
          final compact = MediaQuery.sizeOf(context).width < 600;
          final showSummary = !compact || summaryExpanded;
          return CustomScrollView(
            controller: _scroll,
            slivers: [
              if (compact)
                SliverToBoxAdapter(
                  child: ListTile(
                    leading: const Icon(Icons.analytics_outlined),
                    title: const LocalizedText(
                      'Resumo de produtos e movimentos',
                    ),
                    trailing: Icon(
                      summaryExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: () =>
                        setState(() => summaryExpanded = !summaryExpanded),
                  ),
                ),
              if (showSummary)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnalyticsPeriodPicker(
                          value: period,
                          range: analyticsRange,
                          onChanged: _changePeriod,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DropdownButton<ProductChartMode>(
                            value: productMode,
                            items: [
                              for (final mode in ProductChartMode.values)
                                DropdownMenuItem(
                                  value: mode,
                                  child: LocalizedText(productModeLabel(mode)),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => productMode = value);
                              }
                            },
                          ),
                        ),
                        StreamBuilder<StockMovementAnalytics>(
                          stream: watchStockMovementAnalytics(
                            db,
                            company.id,
                            analyticsRange,
                          ),
                          builder: (context, analytics) {
                            if (!analytics.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return StockMovementSummary(
                              data: analytics.data!,
                              showProductCount: true,
                              productMode: productMode,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AdaptiveSearchField(
                    hintText: 'Nome ou código de barras'.localized(context),
                    onChanged: _search,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: LocalizedText('Todos'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.favorite),
                        label: LocalizedText('Favoritos'),
                      ),
                    ],
                    selected: {favoritesOnly},
                    onSelectionChanged: (value) =>
                        setState(() => favoritesOnly = value.first),
                  ),
                ),
              ),
              StreamBuilder<List<Product>>(
                stream: ProductCatalog(
                  db,
                ).watchPage(companyId: company.id, query: search, limit: limit),
                builder: (context, products) {
                  if (products.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: AsyncErrorPane(onRetry: () => setState(() {})),
                    );
                  }
                  if (!products.hasData) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: AsyncLoadingPane(),
                    );
                  }
                  final visibleProducts = products.data!
                      .where(
                        (product) =>
                            !favoritesOnly || favorites.contains(product.id),
                      )
                      .toList();
                  _loadedProductCount = products.data!.length;
                  if (visibleProducts.isEmpty) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Empty(),
                    );
                  }
                  if (gridView) {
                    return SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisExtent: 250,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: visibleProducts.length,
                        itemBuilder: (_, index) => _ProductGridCard(
                          product: visibleProducts[index],
                          currency: company.currencyCode,
                          favorite: favorites.contains(
                            visibleProducts[index].id,
                          ),
                          onFavorite: () =>
                              _toggleFavorite(visibleProducts[index].id),
                          onOpen: () => context.go(
                            '/products/${visibleProducts[index].id}',
                          ),
                          onEdit: () => context.go(
                            '/products/${visibleProducts[index].id}/edit',
                          ),
                          onRemove: () =>
                              _archive(context, db, visibleProducts[index]),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList.separated(
                      itemCount: visibleProducts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ProductListCard(
                        product: visibleProducts[index],
                        currency: company.currencyCode,
                        favorite: favorites.contains(visibleProducts[index].id),
                        onFavorite: () =>
                            _toggleFavorite(visibleProducts[index].id),
                        onOpen: () => context.go(
                          '/products/${visibleProducts[index].id}',
                        ),
                        onEdit: () => context.go(
                          '/products/${visibleProducts[index].id}/edit',
                        ),
                        onRemove: () =>
                            _archive(context, db, visibleProducts[index]),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _createCategory(BuildContext context, AppDatabase db) async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Nova categoria'),
        content: TextField(
          controller: name,
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
    );
    if (accepted != true || name.text.trim().isEmpty) return null;
    final company = await db.select(db.companies).getSingle();
    final duplicate =
        await (db.select(db.categories)
              ..where((c) => c.companyId.equals(company.id))
              ..where((c) => c.name.equals(name.text.trim()))
              ..where((c) => c.deletedAt.isNull()))
            .getSingleOrNull();
    if (duplicate != null) return duplicate.id;
    final id = const Uuid().v7(), now = DateTime.now().toUtc();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            companyId: company.id,
            name: name.text.trim(),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
    return id;
  }

  Future<String?> _createBrand(BuildContext context, AppDatabase db) async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Nova marca'),
        content: TextField(
          controller: name,
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
    );
    if (accepted != true || name.text.trim().isEmpty) return null;
    final company = await db.select(db.companies).getSingle();
    final duplicate =
        await (db.select(db.brands)
              ..where((b) => b.companyId.equals(company.id))
              ..where((b) => b.name.equals(name.text.trim()))
              ..where((b) => b.deletedAt.isNull()))
            .getSingleOrNull();
    if (duplicate != null) return duplicate.id;
    final id = const Uuid().v7(), now = DateTime.now().toUtc();
    await db
        .into(db.brands)
        .insert(
          BrandsCompanion.insert(
            id: id,
            companyId: company.id,
            name: name.text.trim(),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
    return id;
  }

  Future<void> _add(BuildContext context, AppDatabase db) async {
    try {
      await _showAddForm(context, db);
    } catch (error) {
      if (context.mounted) {
        await showAppError(
          context,
          'Não foi possível abrir o cadastro do produto.',
          details: error,
        );
      }
    }
  }

  Future<void> _showAddForm(BuildContext context, AppDatabase db) async {
    final company = await db.select(db.companies).getSingle();
    var categories = await (db.select(
      db.categories,
    )..where((c) => c.deletedAt.isNull())).get();
    var brands = await (db.select(
      db.brands,
    )..where((b) => b.deletedAt.isNull())).get();
    final units = await db.select(db.units).get();
    if (!context.mounted) return;
    final name = TextEditingController(),
        barcode = TextEditingController(),
        price = TextEditingController(),
        cost = TextEditingController(),
        wholesale = TextEditingController(),
        quantity = TextEditingController(text: '0');
    DateTime? expiresAt;
    String? categoryId, brandId, unitId = units.firstOrNull?.id, imagePath;
    bool saving = false;
    Future<void> save(BuildContext dialog, StateSetter setDialogState) async {
      if (saving) return;
      setDialogState(() => saving = true);
      String? savedProductId;
      try {
        if (name.text.trim().isEmpty) {
          await showAppError(dialog, 'Informe o nome do produto.');
          return;
        }
        if (barcode.text.trim().isEmpty) {
          await showAppError(dialog, 'Informe o código de barras.');
          return;
        }
        int minor, costMinor, wholesaleMinor;
        try {
          minor = price.text.trim().isEmpty ? 0 : parseMoneyMinor(price.text);
          costMinor = cost.text.trim().isEmpty ? 0 : parseMoneyMinor(cost.text);
          wholesaleMinor = wholesale.text.trim().isEmpty
              ? 0
              : parseMoneyMinor(wholesale.text);
        } on FormatException {
          await showAppError(dialog, 'Informe um preço válido.');
          return;
        }
        if (!dialog.mounted) return;
        if (minor < 0 || costMinor < 0 || wholesaleMinor < 0) {
          await showAppError(dialog, 'Os preços não podem ser negativos.');
          return;
        }
        if (!dialog.mounted) return;
        final parsedQuantity = double.tryParse(
          quantity.text.replaceAll(',', '.'),
        );
        if (parsedQuantity == null ||
            !parsedQuantity.isFinite ||
            parsedQuantity < 0) {
          await showAppError(dialog, 'Informe uma quantidade válida.');
          return;
        }
        final warehouse =
            await (db.select(db.warehouses)
                  ..where((w) => w.companyId.equals(company.id))
                  ..where((w) => w.deletedAt.isNull())
                  ..where((w) => w.active.equals(true))
                  ..limit(1))
                .getSingleOrNull();
        final user = await currentSessionUser(db);
        if (!dialog.mounted) return;
        if (warehouse == null) {
          await showAppError(dialog, 'Cadastre um armazém antes do produto.');
          return;
        }
        final result = await ProductCatalog(db).create(
          companyId: company.id,
          deviceId: company.deviceId,
          name: name.text,
          barcode: barcode.text,
          expiresAt: expiresAt,
          saleMinor: minor,
          costMinor: costMinor,
          wholesaleMinor: wholesaleMinor,
          categoryId: categoryId,
          brandId: brandId,
          unitId: unitId,
          initialQuantityMilli: (parsedQuantity * 1000).round(),
          warehouseId: warehouse.id,
          userId: user.id,
        );
        if (!dialog.mounted) return;
        if (result case Failure(:final error)) {
          await showAppFailure(dialog, error);
          return;
        }
        savedProductId = (result as Success<String>).value;
        if (imagePath != null) {
          final product = await (db.select(
            db.products,
          )..where((p) => p.id.equals(savedProductId!))).getSingle();
          final imageResult = await ProductImageService(
            db,
          ).attach(product: product, sourcePath: imagePath!);
          if (!dialog.mounted) return;
          if (imageResult case Failure(:final error)) {
            await showAppError(
              dialog,
              'O produto foi criado, mas a imagem não foi guardada. ${error.userMessage} Pode adicionar a imagem na edição do produto.',
              details: error.cause,
            );
          }
        }
      } catch (error) {
        if (dialog.mounted) {
          await showAppError(
            dialog,
            savedProductId == null
                ? 'Não foi possível concluir o cadastro do produto.'
                : 'O produto foi criado, mas não foi possível concluir os passos seguintes. Abra o produto para verificar os dados.',
            details: error,
          );
        }
      } finally {
        if (dialog.mounted) setDialogState(() => saving = false);
        if (savedProductId != null && dialog.mounted) {
          Navigator.pop(dialog, true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Produto "${name.text.trim()}" criado com sucesso.',
                ),
              ),
            );
            context.go('/products/$savedProductId');
          }
        }
      }
    }

    await showDialog<bool>(
      context: context,
      // O formulário de cadastro contém dados sensíveis; só pode ser
      // fechado explicitamente pelos botões Cancelar ou Salvar.
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: const LocalizedText('Novo produto'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final selected = await picker.FilePicker.pickFile(
                        type: picker.FileType.image,
                      );
                      final path = selected?.path;
                      if (path != null) setDialogState(() => imagePath = path);
                    },
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(dialog).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: imagePath == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 34,
                                ),
                                SizedBox(height: 8),
                                LocalizedText('Adicionar imagem do produto'),
                              ],
                            )
                          : ProductImage(
                              path: imagePath,
                              width: double.infinity,
                              height: 140,
                              fit: BoxFit.contain,
                              borderRadius: 12,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nome *'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownMenu<String>(
                          key: ValueKey(
                            'category-$categoryId-${categories.length}',
                          ),
                          initialSelection: categoryId ?? '',
                          label: const LocalizedText('Categoria'),
                          hintText: 'Pesquisar'.localized(context),
                          enableFilter: true,
                          requestFocusOnTap: true,
                          expandedInsets: EdgeInsets.zero,
                          menuHeight: 240,
                          dropdownMenuEntries: [
                            DropdownMenuEntry(
                              value: '',
                              label: 'Sem categoria'.localized(context),
                            ),
                            for (final c in categories)
                              DropdownMenuEntry(value: c.id, label: c.name),
                          ],
                          onSelected: (value) {
                            if (value == null) return;
                            setDialogState(
                              () => categoryId = value.isEmpty ? null : value,
                            );
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cadastrar categoria'.localized(context),
                        onPressed: () async {
                          final id = await _createCategory(dialog, db);
                          if (id != null) {
                            categories = await (db.select(
                              db.categories,
                            )..where((c) => c.deletedAt.isNull())).get();
                            setDialogState(() => categoryId = id);
                          }
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownMenu<String>(
                          key: ValueKey('brand-$brandId-${brands.length}'),
                          initialSelection: brandId ?? '',
                          label: const LocalizedText('Marca'),
                          hintText: 'Pesquisar'.localized(context),
                          enableFilter: true,
                          requestFocusOnTap: true,
                          expandedInsets: EdgeInsets.zero,
                          menuHeight: 240,
                          dropdownMenuEntries: [
                            DropdownMenuEntry(
                              value: '',
                              label: 'Sem marca'.localized(context),
                            ),
                            for (final b in brands)
                              DropdownMenuEntry(value: b.id, label: b.name),
                          ],
                          onSelected: (value) {
                            if (value == null) return;
                            setDialogState(
                              () => brandId = value.isEmpty ? null : value,
                            );
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cadastrar marca'.localized(context),
                        onPressed: () async {
                          final id = await _createBrand(dialog, db);
                          if (id != null) {
                            brands = await (db.select(
                              db.brands,
                            )..where((b) => b.deletedAt.isNull())).get();
                            setDialogState(() => brandId = id);
                          }
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: unitId,
                    decoration: InputDecoration(
                      labelText: 'Unidade'.localized(context),
                    ),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(
                          value: u.id,
                          child: LocalizedText('${u.code} · ${u.name}'),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => unitId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: barcode,
                    decoration: InputDecoration(
                      labelText: 'Código de barras'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Validade'.localized(context)),
                    subtitle: Text(
                      expiresAt == null
                          ? 'Não definida'.localized(context)
                          : '${expiresAt!.day.toString().padLeft(2, '0')}/${expiresAt!.month.toString().padLeft(2, '0')}/${expiresAt!.year}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialog,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: expiresAt ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(
                            () => expiresAt = DateTime.utc(
                              picked.year,
                              picked.month,
                              picked.day,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Custo'.localized(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: wholesale,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Preço grossista'.localized(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Quantidade inicial *'.localized(context),
                      helperText:
                          'Esta quantidade será a primeira entrada de stock'
                              .localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Preço de venda'.localized(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: saving ? null : () => save(dialog, setDialogState),
              child: LocalizedText(saving ? 'A guardar...' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, AppDatabase db) async {
    final company = await db.select(db.companies).getSingle();
    final result = await ProductSpreadsheetService(db).export(company.id);
    if (!context.mounted) return;
    switch (result) {
      case Success(:final value):
        final saved = await const FileSaveService().save(
          dialogTitle: 'Guardar catálogo de produtos',
          fileName: 'produtos-${DateTime.now().millisecondsSinceEpoch}.xlsx',
          bytes: value,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (!context.mounted) return;
        switch (saved) {
          case Success(value: final uri?):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: LocalizedText('Produtos guardados em $uri')),
            );
          case Success():
            break;
          case Failure(:final error):
            showAppFailure(context, error);
        }
      case Failure(:final error):
        showAppFailure(context, error);
    }
  }

  Future<void> _archive(
    BuildContext context,
    AppDatabase db,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Remover produto?'),
        content: LocalizedText(
          '${product.name} será arquivado sem apagar o histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ProductCatalog(db).archive(product.id);
    if (!context.mounted || result is Success<void>) return;
    final failure = result as Failure<void>;
    showAppFailure(context, failure.error);
  }
}

class _ProductListCard extends StatelessWidget {
  const _ProductListCard({
    required this.product,
    required this.currency,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
  });
  final Product product;
  final String currency;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen, onEdit, onRemove;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onOpen,
      leading: ProductImage(path: product.imagePath, width: 48, height: 48),
      title: Text(product.name),
      subtitle: const LocalizedText('Produto com controlo de stock'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatMoneyMinor(
              product.saleMinor,
              symbol: currency == 'MZN' ? 'MT' : currency,
            ),
          ),
          IconButton(
            onPressed: onFavorite,
            icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
            color: favorite ? Colors.red : null,
            tooltip: 'Favorito'.localized(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => value == 'remove' ? onRemove() : onEdit(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: LocalizedText('Editar')),
              PopupMenuItem(value: 'remove', child: LocalizedText('Remover')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({
    required this.product,
    required this.currency,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
  });
  final Product product;
  final String currency;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen, onEdit, onRemove;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ProductImage(
              path: product.imagePath,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        formatMoneyMinor(
                          product.saleMinor,
                          symbol: currency == 'MZN' ? 'MT' : currency,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                  color: favorite ? Colors.red : null,
                  tooltip: 'Favorito'.localized(context),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'remove' ? onRemove() : onEdit(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: LocalizedText('Editar'),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: LocalizedText('Remover'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inventory_2_outlined, size: 52),
        const SizedBox(height: 12),
        LocalizedText(
          'Ainda não existem produtos',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const LocalizedText('Use + para cadastrar o primeiro produto.'),
      ],
    ),
  );
}
