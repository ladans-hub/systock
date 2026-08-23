import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/database/database_provider.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});
  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  Map<String, String>? data;
  bool busy = false;

  Future<void> run() async {
    setState(() => busy = true);
    final db = ref.read(databaseProvider),
        docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/stock_manager.sqlite');
    final check = await db.customSelect('PRAGMA integrity_check').getSingle();
    final pending = await (db.select(
      db.syncOperations,
    )..where((o) => o.status.equals('pending'))).get();
    final backup =
        await (db.select(db.backups)
              ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final company = await db.select(db.companies).getSingleOrNull();
    if (!mounted) return;
    setState(() {
      busy = false;
      data = {
        'Versão da aplicação': '1.0.0+1',
        'Versão do schema': '${db.schemaVersion}',
        'Integridade SQLite': '${check.data.values.single}',
        'Tamanho do banco': awaitSize(file),
        'Operações pendentes': '${pending.length}',
        'Último backup': backup?.createdAt.toLocal().toString() ?? 'Nunca',
        'Dispositivo': company?.deviceId ?? 'Não configurado',
        'Plataforma': Platform.operatingSystem,
      };
    });
  }

  String awaitSize(File file) => file.existsSync()
      ? '${(file.lengthSync() / 1048576).toStringAsFixed(2)} MB'
      : 'Indisponível';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AdaptiveBackButton(),
      title: const LocalizedText('Diagnóstico'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  'Estado do sistema',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const LocalizedText(
                  'A verificação completa é executada apenas quando solicitada para não afetar as operações diárias.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : run,
                  icon: const Icon(Icons.health_and_safety),
                  label: Text(busy ? 'A verificar…' : 'Executar diagnóstico'),
                ),
              ],
            ),
          ),
        ),
        if (data != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final entry in data!.entries)
                  ListTile(
                    title: Text(entry.key),
                    trailing: SelectableText(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
