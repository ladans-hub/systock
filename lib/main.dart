import 'package:flutter/widgets.dart';
import 'package:systock/app/bootstrap/app_restart_scope.dart';
import 'package:systock/app/bootstrap/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = await bootstrap();
  runApp(AppRestartScope(initialContainer: container));
}
