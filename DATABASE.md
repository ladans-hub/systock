# Banco de dados

O ficheiro `stock_manager.sqlite` usa WAL, foreign keys e `busy_timeout`. O schema atual é v10, evoluído somente por migrations aditivas. Ele contém empresa/RBAC, catálogo e variantes, lotes/séries, armazéns, ledger e cache, compras/pedidos, vendas/pagamentos/crédito/devoluções, caixa/despesas, cotações, impostos/listas de preço, alertas, auditoria, backup e sincronização.

```mermaid
erDiagram
  COMPANY ||--o{ USER : employs
  ROLE ||--o{ USER : grants
  ROLE ||--o{ ROLE_PERMISSION : contains
  PERMISSION ||--o{ ROLE_PERMISSION : maps
  COMPANY ||--o{ PRODUCT : owns
  PRODUCT ||--o{ PRODUCT_VARIANT : has
  PRODUCT ||--o{ PRODUCT_BARCODE : identifies
  COMPANY ||--o{ WAREHOUSE : owns
  WAREHOUSE ||--o{ WAREHOUSE_LOCATION : contains
  PRODUCT ||--o{ INVENTORY_MOVEMENT : ledger
  WAREHOUSE ||--o{ INVENTORY_MOVEMENT : ledger
  PRODUCT ||--o{ INVENTORY_BALANCE : caches
  SALE ||--|{ SALE_ITEM : contains
  SALE ||--o{ PAYMENT : settles
  PURCHASE ||--|{ PURCHASE_ITEM : contains
  SUPPLIER ||--o{ PURCHASE : supplies
  CUSTOMER ||--o{ SALE : buys
  STOCK_TRANSFER ||--|{ STOCK_TRANSFER_ITEM : contains
  DEVICE ||--o{ SYNC_OPERATION : produces
  SYNC_OPERATION ||--o| SYNC_CONFLICT : detects
  QUOTE ||--|{ QUOTE_ITEM : contains
  CUSTOMER ||--o{ CUSTOMER_ACCOUNT_MOVEMENT : owns
  PRICE_LIST ||--o{ PRICE_LIST_ITEM : contains
```

As migrations v1→v9 são aditivas e testadas preservando dados e foreign keys. O agendador cria snapshots diários verificados; restaurações criam obrigatoriamente uma cópia pré-restauro. `inventory_balances` é reconstruível por `SUM(inventory_movements.quantity_milli)` e nunca substitui o ledger.

Índices seguem consultas: nome/SKU/barcode, produto+armazém+tempo, documentos+tempo, operações pendentes e auditoria por entidade. Paginação é obrigatória para listagens.
