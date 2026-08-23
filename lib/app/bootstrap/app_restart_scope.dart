import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/app/app.dart';
import 'package:systock/app/bootstrap/bootstrap.dart';

class AppRestartScope extends StatefulWidget {
  const AppRestartScope({required this.initialContainer, super.key});

  final ProviderContainer initialContainer;

  static Future<void> restart(BuildContext context) async {
    final state = context.findAncestorStateOfType<_AppRestartScopeState>();
    if (state == null) {
      throw StateError('AppRestartScope não encontrado.');
    }
    await state.restart();
  }

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  late ProviderContainer _container = widget.initialContainer;
  int _generation = 0;

  Future<void> restart() async {
    final previous = _container;
    final next = await bootstrap();
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() {
      _container = next;
      _generation++;
    });
    previous.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: KeyedSubtree(key: ValueKey(_generation), child: const SystockApp()),
  );
}
