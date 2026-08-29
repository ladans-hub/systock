import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show InsertMode, Variable;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/scanner/camera_scanner_page.dart';
import 'package:systock/core/scanner/barcode_keyboard_decoder.dart';
import 'package:systock/features/products/application/product_catalog.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/products/presentation/product_image.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/core/widgets/async_state_pane.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});
  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final focusNode = FocusNode();
  final searchController = TextEditingController();
  final hid = BarcodeKeyboardDecoder();
  final cart = <String, ({Product product, int quantityMilli})>{};
  final favorites = <String>{};
  String search = '';
  bool completing = false;
  Timer? searchDebounce;
  int get total => cart.values.fold(
    0,
    (s, e) => s + (e.product.saleMinor * e.quantityMilli) ~/ 1000,
  );
  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreActive);
    Future.microtask(_restoreFavorites);
  }

  void add(Product p) {
    setState(
      () => cart[p.id] = (
        product: p,
        quantityMilli: (cart[p.id]?.quantityMilli ?? 0) + 1000,
      ),
    );
    unawaited(_saveCart('pos.active_cart'));
  }

  Future<void> _saveCart(String key) async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: key,
            valueJson: jsonEncode([
              for (final entry in cart.values)
                {
                  'productId': entry.product.id,
                  'quantityMilli': entry.quantityMilli,
                },
            ]),
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> _restoreActive() async {
    final db = ref.read(databaseProvider);
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('pos.active_cart'))).getSingleOrNull();
    if (setting == null) return;
    final values = jsonDecode(setting.valueJson) as List<dynamic>;
    for (final value in values.cast<Map<String, dynamic>>()) {
      final product =
          await (db.select(db.products)
                ..where((p) => p.id.equals(value['productId'] as String)))
              .getSingleOrNull();
      if (product != null) {
        cart[product.id] = (
          product: product,
          quantityMilli: value['quantityMilli'] as int,
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _restoreFavorites() async {
    final db = ref.read(databaseProvider);
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('pos.favorites'))).getSingleOrNull();
    if (setting != null) {
      favorites.addAll(
        (jsonDecode(setting.valueJson) as List<dynamic>).cast<String>(),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(String productId) async {
    setState(
      () => favorites.contains(productId)
          ? favorites.remove(productId)
          : favorites.add(productId),
    );
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

  Future<void> _suspend() async {
    await _saveCart('pos.suspended_cart');
    setState(cart.clear);
    await _saveCart('pos.active_cart');
  }

  Future<void> _resume() async {
    final db = ref.read(databaseProvider);
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('pos.suspended_cart'))).getSingleOrNull();
    if (setting == null) return;
    setState(cart.clear);
    final values = jsonDecode(setting.valueJson) as List<dynamic>;
    for (final value in values.cast<Map<String, dynamic>>()) {
      final product =
          await (db.select(db.products)
                ..where((p) => p.id.equals(value['productId'] as String)))
              .getSingleOrNull();
      if (product != null) {
        cart[product.id] = (
          product: product,
          quantityMilli: value['quantityMilli'] as int,
        );
      }
    }
    await (db.delete(
      db.appSettings,
    )..where((s) => s.key.equals('pos.suspended_cart'))).go();
    await _saveCart('pos.active_cart');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    focusNode.dispose();
    searchController.dispose();
    searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> onKey(KeyEvent event) async {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (cart.isNotEmpty) setState(cart.clear);
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.f9 && cart.isNotEmpty) {
      final db = ref.read(databaseProvider);
      final company = await db.select(db.companies).getSingleOrNull();
      if (company != null) await finish(db, company);
      return;
    }
    final character = event.logicalKey == LogicalKeyboardKey.enter
        ? '\n'
        : event.character;
    if (character == null) return;
    final code = hid.add(character, DateTime.now());
    if (code == null) return;
    final db = ref.read(databaseProvider);
    final row = await db
        .customSelect(
          'SELECT p.* FROM products p JOIN product_barcodes b ON b.product_id=p.id WHERE b.barcode=? AND p.deleted_at IS NULL LIMIT 1',
          variables: [Variable(code)],
          readsFrom: {db.products, db.productBarcodes},
        )
        .getSingleOrNull();
    if (row != null && mounted) add(db.products.map(row.data));
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: onKey,
      child: FutureBuilder(
        future: db.select(db.companies).getSingleOrNull(),
        builder: (context, company) {
          if (company.hasError) {
            return Scaffold(
              body: AsyncErrorPane(onRetry: () => setState(() {})),
            );
          }
          if (company.data == null) {
            return const Scaffold(body: AsyncLoadingPane());
          }
          final products = StreamBuilder<List<Product>>(
            stream: ProductCatalog(
              db,
            ).watchPage(companyId: company.data!.id, query: search),
            builder: (context, snapshot) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: AdaptiveSearchField(
                    controller: searchController,
                    hintText: 'Buscar produto / Scanner'.localized(context),
                    onChanged: (v) {
                      searchDebounce?.cancel();
                      searchDebounce = Timer(
                        const Duration(milliseconds: 250),
                        () {
                          if (mounted) setState(() => search = v);
                        },
                      );
                    },
                    trailing: AdaptiveIconButton(
                      glyph: PlatformGlyph.scanner,
                      tooltip: 'Digitalizar código'.localized(context),
                      onPressed: () async {
                        final code = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CameraScannerPage(),
                          ),
                        );
                        if (code != null) {
                          searchController.text = code;
                          setState(() => search = code);
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 130,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: snapshot.data?.length ?? 0,
                    itemBuilder: (_, i) {
                      final p = snapshot.data![i];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => add(p),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ProductImage(
                                      path: p.imagePath,
                                      width: 54,
                                      height: 54,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    AdaptiveIconButton(
                                      onPressed: () => _toggleFavorite(p.id),
                                      glyph: favorites.contains(p.id)
                                          ? PlatformGlyph.favoriteFilled
                                          : PlatformGlyph.favorite,
                                      selected: favorites.contains(p.id),
                                      tooltip: 'Favorito'.localized(context),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  formatMoneyMinor(
                                    p.saleMinor,
                                    symbol: company.data!.currencyCode == 'MZN'
                                        ? 'MT'
                                        : company.data!.currencyCode,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
          final checkout = Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      LocalizedText(
                        'Carrinho',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: cart.isEmpty
                            ? null
                            : () => setState(cart.clear),
                        child: const LocalizedText('Limpar'),
                      ),
                      AdaptiveIconButton(
                        onPressed: cart.isEmpty ? _resume : _suspend,
                        glyph: cart.isEmpty
                            ? PlatformGlyph.play
                            : PlatformGlyph.pause,
                        tooltip: cart.isEmpty
                            ? 'Retomar venda'
                            : 'Suspender venda',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: cart.isEmpty
                      ? const Center(
                          child: LocalizedText(
                            'Digitalize ou selecione um produto',
                          ),
                        )
                      : ListView(
                          children: cart.values
                              .map(
                                (e) => ListTile(
                                  title: Text(e.product.name),
                                  subtitle: LocalizedText(
                                    '${e.quantityMilli / 1000} × ${formatMoneyMinor(e.product.saleMinor)}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AdaptiveIconButton(
                                        onPressed: () => setState(
                                          () => cart[e.product.id] = (
                                            product: e.product,
                                            quantityMilli:
                                                e.quantityMilli + 1000,
                                          ),
                                        ),
                                        glyph: PlatformGlyph.add,
                                      ),
                                      AdaptiveIconButton(
                                        onPressed: () => setState(() {
                                          final q = e.quantityMilli - 1000;
                                          if (q <= 0) {
                                            cart.remove(e.product.id);
                                          } else {
                                            cart[e.product.id] = (
                                              product: e.product,
                                              quantityMilli: q,
                                            );
                                          }
                                          unawaited(
                                            _saveCart('pos.active_cart'),
                                          );
                                        }),
                                        glyph: PlatformGlyph.remove,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          LocalizedText(
                            'Total',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Text(
                            formatMoneyMinor(
                              total,
                              symbol: company.data!.currencyCode == 'MZN'
                                  ? 'MT'
                                  : company.data!.currencyCode,
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: AdaptivePrimaryButton(
                          prominent: true,
                          onPressed: cart.isEmpty || completing
                              ? null
                              : () => finish(db, company.data!),
                          glyph: PlatformGlyph.payment,
                          label: completing
                              ? 'A finalizar…'
                              : 'Finalizar Venda',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          return Scaffold(
            appBar: AppBar(title: const LocalizedText('Ponto de Venda')),
            body: LayoutBuilder(
              builder: (_, c) => c.maxWidth >= 900
                  ? Row(
                      children: [
                        Expanded(flex: 3, child: products),
                        SizedBox(width: 390, child: checkout),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(flex: 3, child: products),
                        Expanded(flex: 2, child: checkout),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<void> finish(AppDatabase db, Company company) async {
    final payments = await _collectPayments();
    if (payments == null || payments.isEmpty) return;
    String? customerId;
    if (payments.any((p) => p.method == 'credit')) {
      customerId = await _selectCustomer(db);
      if (customerId == null) return;
    }
    setState(() => completing = true);
    final user = await currentSessionUser(db),
        warehouse = await db.select(db.warehouses).getSingle();
    final cashSession =
        await (db.select(db.cashSessions)
              ..where((s) => s.status.equals('open'))
              ..limit(1))
            .getSingleOrNull();
    final number = await DocumentNumberService(db).next(
      companyId: company.id,
      type: 'sale',
      prefix: 'VEN',
      deviceId: company.deviceId,
    );
    final result = await CompleteSale(db)(
      companyId: company.id,
      warehouseId: warehouse.id,
      documentNumber: number,
      userId: user.id,
      deviceId: company.deviceId,
      lines: cart.values
          .map(
            (e) => SaleLineInput(
              productId: e.product.id,
              description: e.product.name,
              quantityMilli: e.quantityMilli,
              unitPriceMinor: e.product.saleMinor,
              unitCostMinor: e.product.costMinor,
            ),
          )
          .toList(),
      payments: payments,
      customerId: customerId,
      cashSessionId: cashSession?.id,
    );
    if (!mounted) return;
    setState(() => completing = false);
    switch (result) {
      case Success():
        setState(cart.clear);
        await _saveCart('pos.active_cart');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('Venda $number concluída.')),
        );
      case Failure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Future<List<PaymentInput>?> _collectPayments() async {
    final methods = <String, String>{
      'cash': 'Dinheiro',
      'card': 'Cartão',
      'transfer': 'Transferência',
      'mpesa': 'M-Pesa',
      'emola': 'e-Mola',
      'mkesh': 'mKesh',
      'credit': 'Crédito',
      'other': 'Outro',
    };
    final rows = <({String method, TextEditingController amount})>[
      (
        method: 'cash',
        amount: TextEditingController(
          text:
              '${total ~/ 100},${(total.abs() % 100).toString().padLeft(2, '0')}',
        ),
      ),
    ];
    return showDialog<List<PaymentInput>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) {
          int allocated() => rows.fold(0, (sum, row) {
            try {
              return sum + parseMoneyMinor(row.amount.text);
            } on FormatException {
              return sum;
            }
          });
          return AlertDialog(
            title: const LocalizedText('Pagamento'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: rows[i].method,
                              items: [
                                for (final entry in methods.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) => setDialogState(
                                () => rows[i] = (
                                  method: value!,
                                  amount: rows[i].amount,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: rows[i].amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Valor'.localized(context),
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          IconButton(
                            onPressed: rows.length == 1
                                ? null
                                : () => setDialogState(() => rows.removeAt(i)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setDialogState(
                        () => rows.add((
                          method: 'mpesa',
                          amount: TextEditingController(),
                        )),
                      ),
                      icon: const Icon(Icons.add),
                      label: const LocalizedText('Dividir pagamento'),
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const LocalizedText('Por alocar'),
                      const Spacer(),
                      Text(formatMoneyMinor(total - allocated())),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const LocalizedText('Cancelar'),
              ),
              FilledButton(
                onPressed: allocated() == total
                    ? () {
                        Navigator.pop(dialog, [
                          for (final row in rows)
                            PaymentInput(
                              row.method,
                              parseMoneyMinor(row.amount.text),
                            ),
                        ]);
                      }
                    : null,
                child: const LocalizedText('Confirmar pagamento'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _selectCustomer(AppDatabase db) async {
    final customers = await db.select(db.customers).get();
    if (!mounted) return null;
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Cadastre um cliente antes de vender a crédito.',
          ),
        ),
      );
      return null;
    }
    var id = customers.first.id;
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Cliente da venda a crédito'),
          content: DropdownButtonFormField<String>(
            initialValue: id,
            items: [
              for (final customer in customers)
                DropdownMenuItem(
                  value: customer.id,
                  child: Text(customer.name),
                ),
            ],
            onChanged: (value) => setState(() => id = value!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, id),
              child: const LocalizedText('Continuar'),
            ),
          ],
        ),
      ),
    );
  }
}
