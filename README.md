# Systock

Sistema profissional de gestão de stock offline-first para Android, iOS, Windows e macOS. O SQLite local é a fonte de verdade; nenhuma conta ou Internet é necessária para operações comerciais.

## Estado

As fases 1–10 possuem implementação funcional integrada. O schema v10 inclui cadastros, ledger e cache de stock, inventário físico, transferências, compras/pedidos, vendas/POS, pagamentos divididos e crédito, caixa, despesas, cotações, lotes/séries, devoluções, RBAC, auditoria, backup/restauro, alertas, relatórios e outbox idempotente. Android e macOS têm builds debug validados; iOS e Windows devem ser compilados nos respetivos toolchains.

## Requisitos e execução

- Flutter stable 3.44.8 ou compatível e Dart 3.12+
- toolchains da plataforma alvo

```sh
flutter pub get
dart run build_runner build
flutter run
```

O banco nativo é criado como `stock_manager.sqlite` no diretório de documentos da aplicação. Para validar:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Dependências escolhidas

- `drift` + `drift_flutter`: SQLite type-safe, migrations, streams/transações e executor nativo fora da UI.
- `flutter_riverpod`: estado e injeção testáveis; 2.6.1 é a versão compatível resolvida pelo Flutter instalado.
- `go_router`: navegação declarativa oficial com shell adaptativo e deep links.
- `intl`: locale, moeda e datas; `uuid`: IDs globais; `logging`: eventos estruturados.
- `build_runner`/`drift_dev`: geração do schema; `mocktail`: doubles de teste.
- `mobile_scanner` e listener HID: câmara e scanners físicos; `pdf`/`printing`/`barcode`: recibos, QR e etiquetas.
- `google_sign_in` + `googleapis`: OAuth e Drive v3 com scope `drive.appdata`; `flutter_secure_storage`: segredos no cofre do sistema.
- `file_picker` + `excel_community` + `csv`: importação, mapeamento e exportação; `flutter_local_notifications`: alertas offline.

Para Google Drive, configure clientes OAuth separados no Google Cloud para Android, iOS e macOS, habilite Drive API e mantenha apenas o scope `drive.appdata`. Android usa a configuração do package/signing certificate; Apple exige URL scheme no `Info.plist`. Nunca inclua client secrets no aplicativo. Windows mantém todo o uso local funcional e requer um adaptador OAuth desktop configurado para ativar Drive.

## Documentação

- [Arquitetura](ARCHITECTURE.md)
- [Banco e ER](DATABASE.md)
- [Sincronização](SYNC.md)
- [Segurança](SECURITY.md)
- [Impressão](PRINTING.md)
- [Testes](TESTING.md)
- [Contribuição](CONTRIBUTING.md)

## Builds

```sh
flutter build apk
flutter build ios --no-codesign
flutter build windows
flutter build macos
```

Execute apenas o build correspondente num host que suporte a plataforma.
