import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/sync/google_drive_auth_service.dart';
import 'package:systock/core/sync/google_drive_transport.dart';
import 'package:systock/core/sync/sync_engine.dart';
import 'package:systock/core/network/connectivity_service.dart';
import 'package:systock/core/sync/initial_sync_snapshot.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/core/sync/drive_recovery_snapshot.dart';
import 'package:flutter/services.dart';

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});
  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  GoogleDriveSession? session;
  bool busy = false;
  String? email, lastMessage;

  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreSession);
  }

  Future<void> _restoreSession() async {
    try {
      final restored = await GoogleDriveAuthService.instance
          .reconnectSilently();
      if (mounted && restored != null) {
        setState(() {
          session = restored;
          email = restored.email;
        });
      }
    } catch (_) {
      // Optional cloud access must never affect local startup.
    }
  }

  Future<void> connect() async {
    setState(() => busy = true);
    try {
      final connected = await GoogleDriveAuthService.instance.connect();
      if (!mounted) return;
      setState(() {
        session = connected;
        email = connected.email;
      });
      final transport = GoogleDriveSyncTransport(connected.client);
      final recovery = await DriveRecoverySnapshot(
        ref.read(databaseProvider),
        transport,
      ).restoreIfLocalIsFresh();
      if (recovery case Failure(:final error)) {
        if (mounted) setState(() => lastMessage = error.userMessage);
        return;
      }
      if (recovery case Success(value: InitialDriveRecovery.restored)) {
        await _restartAfterRecovery();
        return;
      }
      await InitialSyncSnapshot(ref.read(databaseProvider)).enqueue();
      await _saveSetting('sync.google_drive', {
        'connected': true,
        'email': connected.email,
      });
      await synchronize();
    } catch (error) {
      if (mounted) {
        setState(
          () => lastMessage =
              'Não foi possível conectar. Verifique a configuração OAuth da plataforma.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Desconectar Google Drive?'),
        content: const LocalizedText(
          'Os dados locais serão preservados e a sincronização será interrompida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await GoogleDriveAuthService.instance.disconnect();
    await _saveSetting('sync.google_drive', {'connected': false});
    session?.client.close();
    if (mounted) {
      setState(() {
        session = null;
        email = null;
        lastMessage = 'Conta desconectada. Dados locais preservados.';
      });
    }
  }

  Future<void> synchronize() async {
    var current = session;
    if (current == null) {
      await connect();
      return;
    }
    if (!await const ConnectivityService().hasInternet()) {
      if (mounted) {
        setState(
          () => lastMessage =
              'Offline. As alterações continuam seguras e serão sincronizadas depois.',
        );
      }
      return;
    }
    setState(() => busy = true);
    final transport = GoogleDriveSyncTransport(current.client);
    final result = await SyncEngine(
      ref.read(databaseProvider),
      transport,
    ).synchronize();
    if (!mounted) return;
    setState(() {
      busy = false;
      lastMessage = switch (result) {
        Success(:final value) =>
          'Concluído: ${value.uploaded} enviadas, ${value.applied} recebidas, ${value.ignored} ignoradas.',
        Failure(:final error) => error.userMessage,
      };
    });
    if (result is Success<SyncSummary>) {
      await DriveRecoverySnapshot(
        ref.read(databaseProvider),
        transport,
      ).uploadLatest();
      await _saveSetting('sync.last_success', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'summary': lastMessage ?? '',
      });
    }
  }

  Future<void> _restartAfterRecovery() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await Process.start(
        Platform.resolvedExecutable,
        const [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
    await SystemNavigator.pop();
  }

  Future<void> _saveSetting(String key, Map<String, Object> value) => ref
      .read(databaseProvider)
      .into(ref.read(databaseProvider).appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: key,
          valueJson: jsonEncode(value),
          updatedAt: DateTime.now().toUtc(),
        ),
        mode: InsertMode.insertOrReplace,
      );

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final query = db.select(db.syncOperations)
      ..where((o) => o.status.equals('pending'));
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Sincronização'),
      ),
      body: StreamBuilder<List<SyncOperation>>(
        stream: query.watch(),
        builder: (context, snapshot) {
          final pending = snapshot.data?.length ?? 0;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: RadioGroup<bool>(
                  groupValue: session != null,
                  onChanged: (value) {
                    if (busy) return;
                    value == true ? connect() : disconnect();
                  },
                  child: const Column(
                    children: [
                      RadioListTile(
                        value: false,
                        title: LocalizedText('Apenas neste dispositivo'),
                        subtitle: LocalizedText(
                          'SQLite é a fonte de verdade local',
                        ),
                      ),
                      RadioListTile(
                        value: true,
                        title: LocalizedText('Sincronizar com Google Drive'),
                        subtitle: LocalizedText(
                          'Acesso restrito à pasta privada do aplicativo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            session != null
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            color: session != null ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              session != null
                                  ? 'Google Drive conectado'
                                  : 'Modo local',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      if (email != null) Text(email!),
                      const SizedBox(height: 12),
                      Text(
                        pending == 0
                            ? 'Nenhuma alteração pendente'
                            : '$pending alterações pendentes',
                      ),
                      if (lastMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(lastMessage!),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : synchronize,
                        icon: const Icon(Icons.sync),
                        label: Text(
                          busy ? 'Sincronizando…' : 'Sincronizar agora',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const LocalizedText(
                        'Uma falha do Drive nunca bloqueia vendas, compras ou stock.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
