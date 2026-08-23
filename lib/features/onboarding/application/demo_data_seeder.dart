import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/purchases/application/receive_purchase.dart';
import 'package:systock/features/sales/application/complete_sale.dart';
import 'package:uuid/uuid.dart';

class DemoDataSeeder {
  DemoDataSeeder(this.db);
  final AppDatabase db;
  static const _uuid = Uuid();

  String _id(String companyId, String value) =>
      _uuid.v5(Namespace.url.value, 'systock-demo:$companyId:$value');

  Future<void> seed(Company company, {bool refresh = false}) async {
    final marker = 'demo.seed.v1.${company.id}';
    if (refresh) {
      await (db.delete(
        db.appSettings,
      )..where((s) => s.key.equals(marker))).go();
    }
    if (await (db.select(
          db.appSettings,
        )..where((s) => s.key.equals(marker))).getSingleOrNull() !=
        null) {
      return;
    }
    final user =
        await (db.select(db.users)
              ..where((u) => u.companyId.equals(company.id))
              ..limit(1))
            .getSingle();
    final mainWarehouse =
        await (db.select(db.warehouses)
              ..where((w) => w.companyId.equals(company.id))
              ..limit(1))
            .getSingle();
    final units = await (db.select(
      db.units,
    )..where((u) => u.companyId.equals(company.id))).get();
    String unit(String code) => units.firstWhere((u) => u.code == code).id;
    final now = DateTime.now().toUtc();
    final categoryIds = {
      for (final name in [
        'Mercearia',
        'Bebidas',
        'Farmácia',
        'Escritório',
        'Eletrónica',
      ])
        name: _id(company.id, 'category:$name'),
    };
    final brandIds = {
      for (final name in [
        'Casa Boa',
        'Maputo Fresh',
        'Saúde+',
        'OfficePro',
        'TechLine',
      ])
        name: _id(company.id, 'brand:$name'),
    };
    final supplierId = _id(company.id, 'supplier:central');
    final customerId = _id(company.id, 'customer:ana');
    final secondWarehouseId = _id(company.id, 'warehouse:central');

    await db.transaction(() async {
      for (final entry in categoryIds.entries) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: entry.value,
                companyId: company.id,
                name: entry.key,
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      for (final entry in brandIds.entries) {
        await db
            .into(db.brands)
            .insert(
              BrandsCompanion.insert(
                id: entry.value,
                companyId: company.id,
                name: entry.key,
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: supplierId,
              companyId: company.id,
              name: 'Distribuidora Central de Maputo',
              businessName: const Value('DCM, Lda.'),
              taxId: const Value('400123456'),
              phone: const Value('+258 84 123 4567'),
              email: const Value('vendas@dcm.demo'),
              address: const Value('Av. de Moçambique, Maputo'),
              notes: const Value('Fornecedor fictício para demonstração.'),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: customerId,
              companyId: company.id,
              name: 'Ana Mabunda',
              phone: const Value('+258 82 555 0199'),
              email: const Value('ana.mabunda@example.test'),
              creditLimitMinor: const Value(250000),
              notes: const Value('Cliente fictício para demonstração.'),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.warehouses)
          .insert(
            WarehousesCompanion.insert(
              id: secondWarehouseId,
              companyId: company.id,
              name: 'Armazém Central',
              code: 'CENTRAL',
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      for (final item in _products) {
        final productId = _id(company.id, 'product:${item.sku}');
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: productId,
                companyId: company.id,
                sku: Value(item.sku),
                name: item.name,
                description: Value(item.description),
                categoryId: Value(categoryIds[item.category]),
                brandId: Value(brandIds[item.brand]),
                unitId: Value(unit(item.unit)),
                costMinor: Value(item.cost),
                saleMinor: Value(item.price),
                wholesaleMinor: Value((item.price * 90) ~/ 100),
                minimumPriceMinor: Value((item.price * 85) ~/ 100),
                minimumStockMilli: Value(item.minimum * 1000),
                maximumStockMilli: Value(item.stock * 2 * 1000),
                location: Value(item.location.split('-').first),
                shelf: Value(item.location),
                imagePath: Value(
                  'asset://assets/demo/products/${item.image}.png',
                ),
                trackLots: Value(item.category == 'Farmácia'),
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.productBarcodes)
            .insert(
              ProductBarcodesCompanion.insert(
                id: _id(company.id, 'barcode:${item.barcode}'),
                productId: productId,
                barcode: item.barcode,
                primaryBarcode: const Value(true),
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });

    final purchaseNumber = 'COM-DEMO-000001';
    final purchaseExists =
        await (db.select(db.purchases)
              ..where((p) => p.companyId.equals(company.id))
              ..where((p) => p.documentNumber.equals(purchaseNumber)))
            .getSingleOrNull();
    if (purchaseExists == null) {
      final result = await ReceivePurchase(db)(
        companyId: company.id,
        supplierId: supplierId,
        warehouseId: mainWarehouse.id,
        documentNumber: purchaseNumber,
        userId: user.id,
        deviceId: company.deviceId,
        lines: [
          for (final item in _products)
            PurchaseLineInput(
              productId: _id(company.id, 'product:${item.sku}'),
              quantityMilli: item.stock * 1000,
              unitCostMinor: item.cost,
            ),
        ],
      );
      if (result case Failure(:final error)) {
        throw StateError(error.userMessage);
      }
    }

    for (var index = 0; index < _demoSales.length; index++) {
      final number = 'VEN-DEMO-${(index + 1).toString().padLeft(6, '0')}';
      final exists =
          await (db.select(db.sales)
                ..where((s) => s.companyId.equals(company.id))
                ..where((s) => s.documentNumber.equals(number)))
              .getSingleOrNull();
      if (exists != null) continue;
      final selected = _demoSales[index];
      final lines = [
        for (final entry in selected.entries)
          SaleLineInput(
            productId: _id(company.id, 'product:${_products[entry.key].sku}'),
            description: _products[entry.key].name,
            quantityMilli: entry.value * 1000,
            unitPriceMinor: _products[entry.key].price,
            unitCostMinor: _products[entry.key].cost,
          ),
      ];
      final total = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
      final result = await CompleteSale(db)(
        companyId: company.id,
        warehouseId: mainWarehouse.id,
        documentNumber: number,
        userId: user.id,
        deviceId: company.deviceId,
        customerId: index == 3 ? customerId : null,
        lines: lines,
        payments: [PaymentInput(index.isEven ? 'cash' : 'mpesa', total)],
      );
      if (result case Failure(:final error)) {
        throw StateError(error.userMessage);
      }
    }
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: marker,
            valueJson: 'true',
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}

class _DemoProduct {
  const _DemoProduct(
    this.sku,
    this.barcode,
    this.name,
    this.description,
    this.category,
    this.brand,
    this.unit,
    this.cost,
    this.price,
    this.stock,
    this.minimum,
    this.location,
    this.image,
  );
  final String sku,
      barcode,
      name,
      description,
      category,
      brand,
      unit,
      location,
      image;
  final int cost, price, stock, minimum;
}

const _products = [
  _DemoProduct(
    'MER-001',
    '5600000000011',
    'Arroz Premium 5 kg',
    'Arroz agulha tipo 1.',
    'Mercearia',
    'Casa Boa',
    'UN',
    42000,
    55000,
    42,
    10,
    'A-01-01',
    'grocery',
  ),
  _DemoProduct(
    'MER-002',
    '5600000000028',
    'Óleo Alimentar 1 L',
    'Óleo vegetal refinado.',
    'Mercearia',
    'Casa Boa',
    'L',
    9800,
    13500,
    64,
    15,
    'A-01-02',
    'grocery',
  ),
  _DemoProduct(
    'MER-003',
    '5600000000035',
    'Açúcar Branco 1 kg',
    'Açúcar branco granulado.',
    'Mercearia',
    'Casa Boa',
    'KG',
    6200,
    8500,
    38,
    12,
    'A-01-03',
    'grocery',
  ),
  _DemoProduct(
    'MER-004',
    '5600000000042',
    'Farinha de Milho 1 kg',
    'Farinha de milho fina.',
    'Mercearia',
    'Maputo Fresh',
    'KG',
    5400,
    7500,
    27,
    10,
    'A-02-01',
    'grocery',
  ),
  _DemoProduct(
    'MER-005',
    '5600000000059',
    'Feijão Manteiga 1 kg',
    'Feijão seco selecionado.',
    'Mercearia',
    'Maputo Fresh',
    'KG',
    10500,
    14500,
    18,
    8,
    'A-02-02',
    'grocery',
  ),
  _DemoProduct(
    'BEB-001',
    '5600000000066',
    'Refrigerante Cola 2 L',
    'Bebida gaseificada sabor cola.',
    'Bebidas',
    'Maputo Fresh',
    'UN',
    7500,
    11000,
    50,
    12,
    'B-01-01',
    'beverages',
  ),
  _DemoProduct(
    'BEB-002',
    '5600000000073',
    'Sumo de Laranja 1 L',
    'Bebida de fruta sabor laranja.',
    'Bebidas',
    'Maputo Fresh',
    'L',
    6800,
    9500,
    31,
    10,
    'B-01-02',
    'beverages',
  ),
  _DemoProduct(
    'BEB-003',
    '5600000000080',
    'Água Mineral 1,5 L',
    'Água mineral sem gás.',
    'Bebidas',
    'Maputo Fresh',
    'UN',
    2200,
    3500,
    96,
    24,
    'B-01-03',
    'beverages',
  ),
  _DemoProduct(
    'BEB-004',
    '5600000000097',
    'Água Mineral 500 ml',
    'Água mineral individual.',
    'Bebidas',
    'Maputo Fresh',
    'UN',
    1200,
    2000,
    120,
    30,
    'B-01-04',
    'beverages',
  ),
  _DemoProduct(
    'FAR-001',
    '5600000000103',
    'Paracetamol 500 mg',
    'Caixa com 20 comprimidos.',
    'Farmácia',
    'Saúde+',
    'CX',
    4800,
    7500,
    55,
    15,
    'C-01-01',
    'pharmacy',
  ),
  _DemoProduct(
    'FAR-002',
    '5600000000110',
    'Vitamina C 1000 mg',
    'Frasco com comprimidos efervescentes.',
    'Farmácia',
    'Saúde+',
    'UN',
    12500,
    18000,
    22,
    8,
    'C-01-02',
    'pharmacy',
  ),
  _DemoProduct(
    'FAR-003',
    '5600000000127',
    'Kit Primeiros Socorros',
    'Kit básico doméstico.',
    'Farmácia',
    'Saúde+',
    'UN',
    48000,
    65000,
    9,
    5,
    'C-01-03',
    'pharmacy',
  ),
  _DemoProduct(
    'ESC-001',
    '5600000000134',
    'Caderno A5 120 folhas',
    'Caderno pautado de capa dura.',
    'Escritório',
    'OfficePro',
    'UN',
    8500,
    12500,
    44,
    12,
    'D-01-01',
    'office',
  ),
  _DemoProduct(
    'ESC-002',
    '5600000000141',
    'Caneta Azul',
    'Caneta esferográfica azul.',
    'Escritório',
    'OfficePro',
    'UN',
    1200,
    2500,
    88,
    20,
    'D-01-02',
    'office',
  ),
  _DemoProduct(
    'ESC-003',
    '5600000000158',
    'Papel A4 500 folhas',
    'Resma de papel branco 80 g.',
    'Escritório',
    'OfficePro',
    'PCT',
    23500,
    32000,
    16,
    8,
    'D-01-03',
    'office',
  ),
  _DemoProduct(
    'TEC-001',
    '5600000000165',
    'Mouse Sem Fios',
    'Mouse óptico sem fios.',
    'Eletrónica',
    'TechLine',
    'UN',
    28000,
    45000,
    14,
    6,
    'E-01-01',
    'office',
  ),
  _DemoProduct(
    'TEC-002',
    '5600000000172',
    'Teclado Compacto',
    'Teclado USB compacto.',
    'Eletrónica',
    'TechLine',
    'UN',
    42000,
    65000,
    11,
    5,
    'E-01-02',
    'office',
  ),
  _DemoProduct(
    'TEC-003',
    '5600000000189',
    'Cabo USB-C 1 m',
    'Cabo de dados e carregamento.',
    'Eletrónica',
    'TechLine',
    'UN',
    6500,
    12000,
    35,
    10,
    'E-01-03',
    'office',
  ),
  _DemoProduct(
    'TEC-004',
    '5600000000196',
    'Carregador USB 20 W',
    'Carregador de parede compacto.',
    'Eletrónica',
    'TechLine',
    'UN',
    18500,
    29000,
    19,
    6,
    'E-01-04',
    'office',
  ),
  _DemoProduct(
    'TEC-005',
    '5600000000202',
    'Pen Drive 32 GB',
    'Memória USB 3.0.',
    'Eletrónica',
    'TechLine',
    'UN',
    22000,
    35000,
    13,
    5,
    'E-01-05',
    'office',
  ),
];

const _demoSales = [
  {0: 2, 1: 3, 7: 6},
  {5: 4, 6: 2, 13: 5},
  {9: 2, 10: 1, 2: 3},
  {12: 2, 14: 1, 15: 1},
  {1: 4, 8: 8, 17: 2},
  {0: 1, 5: 2, 18: 1},
];
