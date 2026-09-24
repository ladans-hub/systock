import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

abstract class SyncEntityTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Companies extends SyncEntityTable {
  TextColumn get tradeName => text().withLength(min: 1, max: 160)();
  TextColumn get legalName => text().nullable()();
  TextColumn get taxId => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get receiptFooter => text().nullable()();
  TextColumn get currencyCode =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('MZN'))();
  TextColumn get locale => text().withDefault(const Constant('pt_MZ'))();
  TextColumn get timezone =>
      text().withDefault(const Constant('Africa/Maputo'))();
}

class Warehouses extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get code => text().withLength(min: 1, max: 32)();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, code},
  ];
}

class Products extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get sku => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get brandId => text().nullable().references(Brands, #id)();
  TextColumn get unitId => text().nullable().references(Units, #id)();
  IntColumn get costMinor => integer().withDefault(const Constant(0))();
  IntColumn get saleMinor => integer().withDefault(const Constant(0))();
  IntColumn get wholesaleMinor => integer().withDefault(const Constant(0))();
  IntColumn get minimumPriceMinor => integer().withDefault(const Constant(0))();
  IntColumn get minimumStockMilli => integer().withDefault(const Constant(0))();
  IntColumn get maximumStockMilli => integer().withDefault(const Constant(0))();
  TextColumn get location => text().nullable()();
  TextColumn get shelf => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get productType => text().withDefault(const Constant('simple'))();
  BoolColumn get trackLots => boolean().withDefault(const Constant(false))();
  BoolColumn get trackSerials => boolean().withDefault(const Constant(false))();
  IntColumn get weightMilli => integer().nullable()();
  BoolColumn get trackStock => boolean().withDefault(const Constant(true))();
  BoolColumn get allowNegativeStock =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, sku},
  ];
}

class ProductBarcodes extends SyncEntityTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get barcode => text().withLength(min: 4, max: 128).unique()();
  IntColumn get quantityMilli => integer().withDefault(const Constant(0))();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  BoolColumn get primaryBarcode =>
      boolean().withDefault(const Constant(false))();
}

class Roles extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  BoolColumn get systemRole => boolean().withDefault(const Constant(false))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, name},
  ];
}

class Permissions extends Table {
  TextColumn get code => text()();
  TextColumn get description => text()();
  @override
  Set<Column<Object>> get primaryKey => {code};
}

class RolePermissions extends Table {
  TextColumn get roleId =>
      text().references(Roles, #id, onDelete: KeyAction.cascade)();
  TextColumn get permissionCode =>
      text().references(Permissions, #code, onDelete: KeyAction.cascade)();
  @override
  Set<Column<Object>> get primaryKey => {roleId, permissionCode};
}

class Users extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get roleId => text().references(Roles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get username => text().withLength(min: 1, max: 80)();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinSalt => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, username},
  ];
}

class Categories extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, parentId, name},
  ];
}

class Brands extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, name},
  ];
}

class Units extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get code => text().withLength(min: 1, max: 12)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get decimalPlaces => integer().withDefault(const Constant(0))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, code},
  ];
}

class ProductVariants extends SyncEntityTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get sku => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get attributesJson => text().withDefault(const Constant('{}'))();
  IntColumn get costMinor => integer().nullable()();
  IntColumn get saleMinor => integer().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Suppliers extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get businessName => text().nullable()();
  TextColumn get taxId => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get whatsapp => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get balanceMinor => integer().withDefault(const Constant(0))();
}

class Customers extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get taxId => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get creditLimitMinor => integer().withDefault(const Constant(0))();
  IntColumn get balanceMinor => integer().withDefault(const Constant(0))();
  IntColumn get points => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

class WarehouseLocations extends SyncEntityTable {
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get code => text().withLength(min: 1, max: 40)();
  TextColumn get aisle => text().nullable()();
  TextColumn get shelf => text().nullable()();
  TextColumn get position => text().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {warehouseId, code},
  ];
}

class Lots extends SyncEntityTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get batchNumber => text()();
  DateTimeColumn get manufacturedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {productId, warehouseId, batchNumber},
  ];
}

class SerialNumbers extends SyncEntityTable {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get serial => text().unique()();
  TextColumn get imei => text().nullable().unique()();
  TextColumn get status => text().withDefault(const Constant('available'))();
}

class StockCounts extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get createdBy => text().references(Users, #id)();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class StockCountItems extends Table {
  TextColumn get id => text()();
  TextColumn get stockCountId =>
      text().references(StockCounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get systemQuantityMilli => integer()();
  IntColumn get countedQuantityMilli => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {stockCountId, productId},
  ];
}

class StockTransfers extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get documentNumber => text()();
  @ReferenceName('outgoingTransfers')
  TextColumn get sourceWarehouseId => text().references(Warehouses, #id)();
  @ReferenceName('incomingTransfers')
  TextColumn get destinationWarehouseId => text().references(Warehouses, #id)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get createdBy => text().references(Users, #id)();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class StockTransferItems extends Table {
  TextColumn get id => text()();
  TextColumn get transferId =>
      text().references(StockTransfers, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantityMilli => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PurchaseOrders extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().references(Users, #id)();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class PurchaseOrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseOrderId =>
      text().references(PurchaseOrders, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantityMilli => integer()();
  IntColumn get receivedQuantityMilli =>
      integer().withDefault(const Constant(0))();
  IntColumn get unitCostMinor => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Purchases extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get purchaseOrderId =>
      text().nullable().references(PurchaseOrders, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get subtotalMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get additionalCostsMinor =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer()();
  IntColumn get paidMinor => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().references(Users, #id)();
  TextColumn get notes => text().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId =>
      text().references(Purchases, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId =>
      text().nullable().references(ProductVariants, #id)();
  IntColumn get quantityMilli => integer()();
  IntColumn get unitCostMinor => integer()();
  IntColumn get totalMinor => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sales extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get subtotalMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer()();
  IntColumn get costMinor => integer()();
  IntColumn get paidMinor => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().references(Users, #id)();
  TextColumn get reversalOfId => text().nullable().references(Sales, #id)();
  TextColumn get notes => text().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId =>
      text().references(Sales, #id, onDelete: KeyAction.restrict)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId =>
      text().nullable().references(ProductVariants, #id)();
  TextColumn get description => text()();
  IntColumn get quantityMilli => integer()();
  IntColumn get unitPriceMinor => integer()();
  IntColumn get unitCostMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer()();
  IntColumn get deliveredQuantityMilli =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Payments extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get method => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get reference => text().nullable()();
}

class CashRegisters extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get name => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class CashSessions extends SyncEntityTable {
  TextColumn get cashRegisterId => text().references(CashRegisters, #id)();
  @ReferenceName('openedCashSessions')
  TextColumn get openedBy => text().references(Users, #id)();
  @ReferenceName('closedCashSessions')
  TextColumn get closedBy => text().nullable().references(Users, #id)();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get openingMinor => integer()();
  IntColumn get expectedMinor => integer().nullable()();
  IntColumn get countedMinor => integer().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
}

class CashMovements extends SyncEntityTable {
  TextColumn get cashSessionId => text().references(CashSessions, #id)();
  TextColumn get type => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get userId => text().references(Users, #id)();
}

class ExpenseCategories extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, name},
  ];
}

class Expenses extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  TextColumn get cashSessionId =>
      text().nullable().references(CashSessions, #id)();
  TextColumn get description => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get createdBy => text().references(Users, #id)();
  TextColumn get notes => text().nullable()();
}

class TaxRates extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  IntColumn get rateBasisPoints => integer()();
  BoolColumn get priceIncludesTax =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class PriceLists extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, name},
  ];
}

class PriceListItems extends Table {
  TextColumn get id => text()();
  TextColumn get priceListId =>
      text().references(PriceLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get variantId =>
      text().nullable().references(ProductVariants, #id)();
  IntColumn get priceMinor => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {priceListId, productId, variantId},
  ];
}

class Quotes extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get kind => text().withDefault(const Constant('quote'))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get totalMinor => integer()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  TextColumn get createdBy => text().references(Users, #id)();
  TextColumn get convertedSaleId => text().nullable().references(Sales, #id)();
  TextColumn get notes => text().nullable()();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class QuoteItems extends Table {
  TextColumn get id => text()();
  TextColumn get quoteId =>
      text().references(Quotes, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get description => text()();
  IntColumn get quantityMilli => integer()();
  IntColumn get unitPriceMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerAccountMovements extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  TextColumn get type => text()();
  IntColumn get amountMinor => integer()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
}

class SaleReturns extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get documentNumber => text()();
  TextColumn get type => text().withDefault(const Constant('refund'))();
  IntColumn get totalMinor => integer()();
  TextColumn get reason => text()();
  TextColumn get createdBy => text().references(Users, #id)();
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {companyId, documentNumber},
  ];
}

class SaleReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get returnId =>
      text().references(SaleReturns, #id, onDelete: KeyAction.restrict)();
  TextColumn get saleItemId => text().references(SaleItems, #id)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantityMilli => integer()();
  IntColumn get refundMinor => integer()();
  BoolColumn get restock => boolean().withDefault(const Constant(true))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DocumentSequences extends Table {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get documentType => text()();
  IntColumn get year => integer()();
  IntColumn get nextValue => integer().withDefault(const Constant(1))();
  @override
  Set<Column<Object>> get primaryKey => {companyId, documentType, year};
}

class InventoryMovements extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get variantId =>
      text().nullable().references(ProductVariants, #id)();
  TextColumn get lotId => text().nullable().references(Lots, #id)();
  TextColumn get serialNumberId =>
      text().nullable().references(SerialNumbers, #id)();
  TextColumn get movementType => text()();
  IntColumn get quantityMilli => integer()();
  IntColumn get balanceBeforeMilli => integer()();
  IntColumn get balanceAfterMilli => integer()();
  IntColumn get unitCostMinor => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get reason => text().nullable()();
  TextColumn get userId => text().nullable()();
}

class InventoryBalances extends Table {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  IntColumn get quantityMilli => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {productId, warehouseId};
}

class SyncOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get deviceId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get version => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get checksum => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class AppliedOperations extends Table {
  TextColumn get operationId => text()();
  DateTimeColumn get appliedAt => dateTime()();
  TextColumn get sourceDeviceId => text()();
  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get userId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Devices extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  DateTimeColumn get lastSeenAt => dateTime()();
  BoolColumn get revoked => boolean().withDefault(const Constant(false))();
}

class SyncStates extends Table {
  TextColumn get deviceId => text()();
  TextColumn get remoteDeviceId => text()();
  TextColumn get cursor => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {deviceId, remoteDeviceId};
}

class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayloadJson => text()();
  TextColumn get remotePayloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Backups extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();
  TextColumn get checksum => text()();
  IntColumn get schemaVersion => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Notifications extends SyncEntityTable {
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get entityId => text().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

@DriftDatabase(
  tables: [
    Companies,
    Warehouses,
    Products,
    ProductBarcodes,
    Roles,
    Permissions,
    RolePermissions,
    Users,
    Categories,
    Brands,
    Units,
    ProductVariants,
    Suppliers,
    Customers,
    WarehouseLocations,
    Lots,
    SerialNumbers,
    StockCounts,
    StockCountItems,
    StockTransfers,
    StockTransferItems,
    PurchaseOrders,
    PurchaseOrderItems,
    Purchases,
    PurchaseItems,
    Sales,
    SaleItems,
    Payments,
    CashRegisters,
    CashSessions,
    CashMovements,
    ExpenseCategories,
    Expenses,
    TaxRates,
    PriceLists,
    PriceListItems,
    Quotes,
    QuoteItems,
    CustomerAccountMovements,
    SaleReturns,
    SaleReturnItems,
    DocumentSequences,
    InventoryMovements,
    InventoryBalances,
    SyncOperations,
    AppliedOperations,
    AuditLogs,
    Devices,
    SyncStates,
    SyncConflicts,
    Backups,
    AppSettings,
    Notifications,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: 'stock_manager',
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    ),
  );
  @override
  int get schemaVersion => 15;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(roles);
        await m.createTable(permissions);
        await m.createTable(rolePermissions);
        await m.createTable(users);
        await m.createTable(categories);
        await m.createTable(brands);
        await m.createTable(units);
        await m.createTable(productVariants);
        await m.createTable(suppliers);
        await m.createTable(customers);
        await m.createTable(warehouseLocations);
        await _createPhaseTwoIndexes();
      }
      if (from < 3) {
        await m.createTable(lots);
        await m.createTable(serialNumbers);
        await m.createTable(stockCounts);
        await m.createTable(stockCountItems);
        await m.createTable(stockTransfers);
        await m.createTable(stockTransferItems);
        await _createPhaseThreeIndexes();
      }
      if (from < 4) {
        await m.createTable(purchaseOrders);
        await m.createTable(purchaseOrderItems);
        await m.createTable(purchases);
        await m.createTable(purchaseItems);
        await _createPhaseFourIndexes();
      }
      if (from < 5) {
        await m.createTable(sales);
        await m.createTable(saleItems);
        await m.createTable(payments);
        await m.createTable(cashRegisters);
        await m.createTable(cashSessions);
        await m.createTable(cashMovements);
        await _createPhaseFiveIndexes();
      }
      if (from < 6) {
        await m.createTable(devices);
        await m.createTable(syncStates);
        await m.createTable(syncConflicts);
        await m.createTable(backups);
        await m.createTable(appSettings);
        await m.createTable(notifications);
        await _createPhaseEightIndexes();
      }
      if (from < 7) {
        await m.createTable(expenseCategories);
        await m.createTable(expenses);
        await _createPhaseSevenIndexes();
      }
      if (from < 8) {
        await m.createTable(taxRates);
        await m.createTable(priceLists);
        await m.createTable(priceListItems);
        await m.createTable(quotes);
        await m.createTable(quoteItems);
        await m.createTable(customerAccountMovements);
        await m.createTable(documentSequences);
        await _createPhaseCommercialIndexes();
      }
      if (from < 9) {
        await m.addColumn(companies, companies.phone);
        await m.addColumn(companies, companies.email);
        await m.addColumn(companies, companies.address);
        await m.addColumn(companies, companies.logoPath);
        await m.addColumn(companies, companies.receiptFooter);
        await m.addColumn(products, products.categoryId);
        await m.addColumn(products, products.brandId);
        await m.addColumn(products, products.unitId);
        await m.addColumn(products, products.wholesaleMinor);
        await m.addColumn(products, products.minimumPriceMinor);
        await m.addColumn(products, products.maximumStockMilli);
        await m.addColumn(products, products.location);
        await m.addColumn(products, products.shelf);
        await m.addColumn(products, products.imagePath);
        await m.addColumn(products, products.productType);
        await m.addColumn(products, products.trackLots);
        await m.addColumn(products, products.trackSerials);
        await m.addColumn(products, products.weightMilli);
        await m.addColumn(inventoryMovements, inventoryMovements.variantId);
        await m.addColumn(inventoryMovements, inventoryMovements.lotId);
        await m.addColumn(
          inventoryMovements,
          inventoryMovements.serialNumberId,
        );
      }
      if (from < 10) {
        await m.createTable(saleReturns);
        await m.createTable(saleReturnItems);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_returns_sale ON sale_returns(sale_id, created_at)',
        );
      }
      // Databases older than v6 create notifications from the current table
      // definition in the v6 migration, so archived_at already exists there.
      if (from >= 6 && from < 11) {
        await m.addColumn(notifications, notifications.archivedAt);
      }
      if (from < 12) {
        final columns = await customSelect(
          'PRAGMA table_info(product_barcodes)',
        ).get();
        if (!columns.any(
          (row) => row.read<String>('name') == 'quantity_milli',
        )) {
          await m.addColumn(productBarcodes, productBarcodes.quantityMilli);
        }
      }
      if (from < 13) {
        final columns = await customSelect(
          'PRAGMA table_info(product_barcodes)',
        ).get();
        if (!columns.any((row) => row.read<String>('name') == 'expires_at')) {
          await m.addColumn(productBarcodes, productBarcodes.expiresAt);
        }
      }
      if (from < 14) {
        await customStatement('''
          INSERT INTO lots (id, product_id, warehouse_id, batch_number, expires_at,
                            created_at, updated_at, version, device_id)
          SELECT lower(hex(randomblob(16))), p.id, w.id, b.barcode, b.expires_at,
                 b.created_at, b.updated_at, 1, b.device_id
            FROM product_barcodes b
            JOIN products p ON p.id = b.product_id
            JOIN warehouses w ON w.company_id = p.company_id AND w.active = 1
           WHERE b.deleted_at IS NULL
             AND NOT EXISTS (
               SELECT 1 FROM lots l
                WHERE l.product_id = b.product_id AND l.batch_number = b.barcode
             )
           GROUP BY b.id
        ''');
      }
      if (from < 15) {
        final columns = await customSelect(
          'PRAGMA table_info(sale_items)',
        ).get();
        final columnNames = columns
            .map((row) => row.read<String>('name'))
            .toSet();
        if (!columnNames.contains('delivered_quantity_milli')) {
          await m.addColumn(saleItems, saleItems.deliveredQuantityMilli);
        }
        if (!columnNames.contains('delivered_at')) {
          await m.addColumn(saleItems, saleItems.deliveredAt);
        }
        await customStatement(
          'UPDATE sale_items SET delivered_quantity_milli=quantity_milli, delivered_at=(SELECT created_at FROM sales WHERE sales.id=sale_items.sale_id)',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX idx_products_name ON products(company_id, name COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX idx_movements_lookup ON inventory_movements(product_id, warehouse_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX idx_sync_pending ON sync_operations(status, created_at)',
    );
    await customStatement(
      'CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id, created_at)',
    );
    await _createPhaseTwoIndexes();
    await _createPhaseThreeIndexes();
    await _createPhaseFourIndexes();
    await _createPhaseFiveIndexes();
    await _createPhaseEightIndexes();
    await _createPhaseSevenIndexes();
    await _createPhaseCommercialIndexes();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_returns_sale ON sale_returns(sale_id, created_at)',
    );
  }

  Future<void> _createPhaseTwoIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_users_company ON users(company_id, active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(company_id, parent_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id, active)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(company_id, name COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(company_id, name COLLATE NOCASE)',
    );
  }

  Future<void> _createPhaseThreeIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lots_expiry ON lots(warehouse_id, expires_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counts_status ON stock_counts(warehouse_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transfers_status ON stock_transfers(company_id, status, created_at)',
    );
  }

  Future<void> _createPhaseFourIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders(company_id, status, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(supplier_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON purchase_items(product_id, purchase_id)',
    );
  }

  Future<void> _createPhaseFiveIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(company_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id, sale_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payments_sale ON payments(sale_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cash_session_status ON cash_sessions(cash_register_id, status)',
    );
  }

  Future<void> _createPhaseEightIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conflicts_status ON sync_conflicts(status, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_backups_date ON backups(created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(company_id, read_at, created_at)',
    );
  }

  Future<void> _createPhaseSevenIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(company_id, created_at)',
    );
  }

  Future<void> _createPhaseCommercialIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_quotes_status ON quotes(company_id, status, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_quote_items_product ON quote_items(product_id, quote_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customer_account ON customer_account_movements(customer_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_price_list_product ON price_list_items(price_list_id, product_id)',
    );
  }

  Future<void> validateIntegrity() async {
    final result = await customSelect('PRAGMA quick_check').getSingle();
    if (result.data.values.single != 'ok') {
      throw StateError('SQLite integrity validation failed');
    }
  }

  Future<void> rebuildInventoryBalances() => transaction(() async {
    await delete(inventoryBalances).go();
    await customStatement('''
          INSERT INTO inventory_balances(product_id, warehouse_id, quantity_milli, updated_at)
          SELECT product_id, warehouse_id, SUM(quantity_milli), MAX(created_at)
          FROM inventory_movements WHERE deleted_at IS NULL GROUP BY product_id, warehouse_id
        ''');
  });
}
