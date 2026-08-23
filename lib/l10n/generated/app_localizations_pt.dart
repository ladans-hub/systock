// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'Systock';

  @override
  String get dashboard => 'Visão geral';

  @override
  String get products => 'Produtos';

  @override
  String get inventory => 'Stock';

  @override
  String get sales => 'Vendas';

  @override
  String get purchases => 'Compras';

  @override
  String get settings => 'Configurações';

  @override
  String get save => 'Salvar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get offlineSaved =>
      'Alterações salvas localmente. Serão sincronizadas quando houver conexão.';
}
