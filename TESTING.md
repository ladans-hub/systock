# Testes

Execute `dart format --output=none --set-exit-if-changed .`, `flutter analyze` e `flutter test`. A suíte usa SQLite real em memória e cobre Result, dinheiro exato, foreign keys, migration v1→v10, PIN/RBAC, scanner HID, PDF/ESC-POS, backup/restauro, idempotência, produto/duplicados, compra, stock, inventário físico, transferências, caixa, despesas, venda/pagamentos/crédito, cancelamento e devolução. O teste integrado percorre empresa→produto→compra→stock→venda→recibo inteiramente offline.

Builds validados no host macOS: Android debug, iOS debug sem assinatura e macOS debug. Windows deve ser validado num runner Windows.
