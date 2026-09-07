import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/app/bootstrap/app_restart_scope.dart';
import 'package:systock/core/backup/backup_service.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/core/files/file_save_service.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool busy = false;

  Future<Directory> _directory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/systock_backups')
      ..createSync(recursive: true);
  }

  Future<void> create() async {
    setState(() => busy = true);
    File? temporary;
    try {
      final db = ref.read(databaseProvider);
      final company = await db.select(db.companies).getSingle();
      final now = DateTime.now().toUtc();
      final tempDirectory = await getTemporaryDirectory();
      final fileName =
          'systock-backup-${now.toIso8601String().replaceAll(':', '-')}.sqlite';
      temporary = File('${tempDirectory.path}/$fileName');
      final created = await BackupService(db).create(temporary.path);
      if (created case Failure<BackupMetadata>(:final error)) {
        if (mounted) await showAppFailure(context, error);
        return;
      }
      final metadata = (created as Success<BackupMetadata>).value;
      final saved = await const FileSaveService().save(
        dialogTitle: 'Escolha onde guardar a cópia de segurança',
        fileName: fileName,
        bytes: await temporary.readAsBytes(),
        mimeType: 'application/vnd.sqlite3',
      );
      if (!mounted) return;
      if (saved case Failure<Uri?>(:final error)) {
        if (mounted) await showAppFailure(context, error);
        return;
      }
      final uri = (saved as Success<Uri?>).value;
      if (uri == null) return;
      final savedPath = uri.scheme == 'file'
          ? uri.toFilePath()
          : uri.toString();
      if (uri.scheme == 'file') {
        await File('$savedPath.json').writeAsString(
          jsonEncode({...metadata.toJson(), 'path': savedPath}),
          flush: true,
        );
      }
      await db
          .into(db.backups)
          .insert(
            BackupsCompanion.insert(
              id: const Uuid().v7(),
              path: savedPath,
              checksum: metadata.checksum,
              schemaVersion: metadata.schemaVersion,
              sizeBytes: metadata.sizeBytes,
              deviceId: company.deviceId,
              createdAt: metadata.createdAt,
              status: 'valid',
            ),
          );
      _message('Backup criado, validado e guardado em $savedPath');
    } catch (error, stackTrace) {
      debugPrint('Falha ao guardar backup: $error\n$stackTrace');
      if (mounted) {
        await showAppError(
          context,
          'Não foi possível criar ou guardar o backup.',
          details: error,
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      final metadata = temporary == null
          ? null
          : File('${temporary.path}.json');
      if (metadata != null && await metadata.exists()) {
        await metadata.delete();
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    try {
      await _restore();
    } catch (error) {
      if (mounted) {
        setState(() => busy = false);
        await showAppError(
          context,
          'Não foi possível concluir a restauração.',
          details: error,
        );
      }
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    final service = BackupService(ref.read(databaseProvider));
    final metadataFile = File('$path.json');
    String? checksum;
    if (await metadataFile.exists()) {
      final json =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      checksum = json['checksum'] as String?;
    }
    final validation = await service.verify(path, expectedChecksum: checksum);
    if (!mounted) return;
    if (validation case Failure(:final error)) {
      showAppFailure(context, error);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Restaurar este backup?'),
        content: LocalizedText(
          'Arquivo validado:\n$path\n\nSerá criada uma cópia de segurança do estado atual. A aplicação deverá ser reaberta após a restauração.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    final docs = await getApplicationDocumentsDirectory(),
        dir = await _directory();
    final result = await service.restore(
      backupPath: path,
      currentDatabasePath: '${docs.path}/stock_manager.sqlite',
      preRestoreBackupPath:
          '${dir.path}/pre-restore-${DateTime.now().toUtc().millisecondsSinceEpoch}.sqlite',
      expectedChecksum: checksum,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        await _restartApplication();
      case Failure(:final error):
        setState(() => busy = false);
        await showAppFailure(context, error);
    }
  }

  Future<void> _restartApplication() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await Process.start(
        Platform.resolvedExecutable,
        const [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
    await AppRestartScope.restart(context);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final backups = (db.select(
      db.backups,
    )..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).watch();
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Backup e restauração'),
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
                    'Cópias locais verificadas',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    'Cada snapshot inclui checksum SHA-256, versão do schema e verificação de integridade SQLite.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : create,
                        icon: const Icon(Icons.backup),
                        label: Text(
                          busy ? 'A processar…' : 'Criar backup agora',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : restore,
                        icon: const Icon(Icons.restore),
                        label: const LocalizedText('Restaurar arquivo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LocalizedText(
            'Histórico',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          StreamBuilder<List<Backup>>(
            stream: backups,
            builder: (_, snapshot) {
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedText('Ainda não existem backups.'),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final backup in rows)
                      ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: Text(backup.createdAt.toLocal().toString()),
                        subtitle: LocalizedText(
                          '${(backup.sizeBytes / 1048576).toStringAsFixed(2)} MB · schema ${backup.schemaVersion}\n${backup.path}',
                        ),
                        isThreeLine: true,
                        trailing: Text(backup.status),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
