import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/sync/google_drive_auth_service.dart';
import 'package:systock/core/sync/google_drive_transport.dart';
import 'package:systock/core/sync/drive_recovery_snapshot.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/network/connectivity_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/sync/drive_vault_identity.dart';
import 'package:systock/core/sync/drive_vault_service.dart';
import 'package:systock/core/sync/drive_vault_store.dart';
import 'package:systock/core/sync/vault_cipher.dart';
import 'package:systock/core/sync/drive_connection_dialogs.dart';

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});
  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage>
    with SingleTickerProviderStateMixin {
  GoogleDriveSession? session;
  bool busy = false;
  String? email, lastMessage;
  late final AnimationController _syncAnimationController;

  void _setBusy(bool value) {
    if (value) {
      if (!mounted) return;
      _syncAnimationController.repeat();
    } else {
      if (!mounted) return;
      _syncAnimationController.stop();
      _syncAnimationController.reset();
    }
    if (mounted) setState(() => busy = value);
  }

  @override
  void initState() {
    super.initState();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.microtask(_restoreSession);
  }

  @override
  void dispose() {
    _syncAnimationController.dispose();
    session?.client.close();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final binding = await DriveVaultService.binding(
        ref.read(databaseProvider),
      );
      if (binding?['enabled'] == false) return;
      final restored = await GoogleDriveAuthService.instance
          .reconnectSilently();
      if (!mounted || busy) {
        restored?.client.close();
        return;
      }
      if (restored != null) {
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
    _setBusy(true);
    try {
      final connected = await GoogleDriveAuthService.instance.connect();
      if (!mounted) {
        connected.client.close();
        return;
      }
      session?.client.close();
      setState(() {
        session = connected;
        email = connected.email;
      });
      final bindingResult = await _ensureVaultBinding(connected);
      if (!mounted || !bindingResult) return;
      await _saveSetting('sync.google_drive', {
        'connected': true,
        'email': connected.email,
      });
      await synchronize();
    } catch (error) {
      if (mounted) {
        await showAppError(
          context,
          'Não foi possível concluir a ligação ao Google Drive.',
          details: error,
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<DriveVaultService> _vault(GoogleDriveSession connected) async {
    final documents = await getApplicationDocumentsDirectory();
    return DriveVaultService(
      ref.read(databaseProvider),
      GoogleDriveVaultStore(connected.client),
      const SecureVaultSecrets(),
      documents,
      accountId: connected.accountId,
      email: connected.email,
    );
  }

  Future<bool> _ensureVaultBinding(GoogleDriveSession connected) async {
    final vault = await _vault(connected);
    final company = await ref
        .read(databaseProvider)
        .select(ref.read(databaseProvider).companies)
        .getSingle();
    final claims = await vault.identity.claims();
    final existing = claims
        .where((claim) => claim.companyId == company.id)
        .toList();
    if (existing.isNotEmpty) {
      final claim = DriveVaultIdentity.active(
        existing,
        company.id,
        connected.accountId,
      );
      final savedKey = await vault.secrets.read(
        'key.${company.id}.${connected.accountId}',
      );
      if (savedKey != null) {
        await vault.reconnect(claim);
      } else {
        if (!mounted) return false;
        final key = await requestDriveRecoveryKey(context);
        if (key == null) return false;
        await vault.reconnect(claim, recoveryKey: key);
      }
      return true;
    }
    final key = await _recoveryKeyDialog(existingBackup: false);
    if (key == null) return false;
    await vault.register(key);
    if (mounted) {
      setState(
        () => lastMessage =
            'Loja associada à conta Google. Guarde a chave de recuperação apresentada.',
      );
    }
    return true;
  }

  Future<String?> _recoveryKeyDialog({required bool existingBackup}) async {
    final generated = await VaultCipher.newRecoveryKey();
    if (!mounted) return null;
    final controller = TextEditingController(
      text: existingBackup ? '' : generated,
    );
    final key = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: Text(
          existingBackup ? 'Restaurar loja existente' : 'Proteger a loja',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              existingBackup
                  ? 'Introduza a chave de recuperação da loja para sincronizar este dispositivo.'
                  : 'Guarde esta chave num local seguro. Ela será necessária para restaurar a loja num computador novo.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              readOnly: !existingBackup,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Chave de recuperação',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const LocalizedText('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key == null || key.isEmpty) return null;
    return key;
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
    _setBusy(true);
    try {
      // Disable locally first, under the same lock as every automatic sync.
      final db = ref.read(databaseProvider);
      await VaultLock.run(() async {
        final binding = await DriveVaultService.binding(db);
        if (binding != null) {
          await DriveVaultService.setting(
            db,
            DriveVaultService.bindingSetting,
            {...binding, 'enabled': false},
          );
        }
        await _saveSetting('sync.google_drive', {'connected': false});
      });
      session?.client.close();
      if (mounted) {
        setState(() {
          session = null;
          email = null;
          lastMessage =
              'Conta desconectada. Dados e alterações locais preservados.';
        });
      }
      await GoogleDriveAuthService.instance.disconnect();
    } catch (error) {
      if (mounted) {
        await showAppError(
          context,
          'Não foi possível concluir a saída da conta Google.',
          details: error,
        );
      }
    } finally {
      _setBusy(false);
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
    _setBusy(true);
    // Access tokens are short-lived. Refresh before either transport is used.
    try {
      final refreshed = await GoogleDriveAuthService.instance
          .reconnectSilently();
      if (refreshed != null) {
        current.client.close();
        current = refreshed;
        session = refreshed;
        email = refreshed.email;
      }
    } catch (_) {
      // The current token may still be valid; the transport reports failure.
    }
    try {
      final binding = await DriveVaultService.binding(
        ref.read(databaseProvider),
      );
      final vault = await _vault(current!);
      final savedKey = binding == null
          ? null
          : await vault.secrets.read(
              'key.${binding['companyId']}.${current.accountId}',
            );
      if (binding == null ||
          binding['enabled'] != true ||
          binding['accountId'] != current.accountId ||
          savedKey == null) {
        if (!await _ensureVaultBinding(current)) return;
      }
      final message = await vault.synchronize();
      final recovery = await DriveRecoverySnapshot(
        ref.read(databaseProvider),
        GoogleDriveSyncTransport(current.client),
      ).uploadLatest();
      if (recovery case Failure(:final error)) {
        throw StateError('${error.userMessage} ${error.cause ?? ''}');
      }
      if (mounted) setState(() => lastMessage = message);
    } catch (error) {
      final message = error is StateError ? error.message : error.toString();
      await _saveSetting('sync.last_failure', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'message': message,
      });
      if (mounted) {
        setState(() => lastMessage = 'Sincronização não concluída: $message');
        await showAppError(
          context,
          'Não foi possível sincronizar.',
          details: error,
        );
      }
    } finally {
      if (mounted) _setBusy(false);
    }
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
                      if (session != null)
                        OutlinedButton.icon(
                          onPressed: busy ? null : disconnect,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Desconectar conta Google Drive'),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        pending == 0
                            ? 'A sincronização verifica todos os dados locais e do Drive'
                            : '$pending alterações pendentes',
                      ),
                      _SyncFailureStatus(db: db),
                      if (lastMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(lastMessage!),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : synchronize,
                        icon: AnimatedBuilder(
                          animation: _syncAnimationController,
                          child: const Icon(Icons.sync),
                          builder: (context, child) => Transform.rotate(
                            angle: _syncAnimationController.value * 2 * math.pi,
                            child: child,
                          ),
                        ),
                        label: Text(
                          busy
                              ? 'Sincronizando…'
                              : session == null
                              ? 'Conectar e sincronizar'
                              : 'Sincronizar agora',
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

class _SyncFailureStatus extends StatelessWidget {
  const _SyncFailureStatus({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => StreamBuilder<AppSetting?>(
    stream: (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('sync.last_failure'))).watchSingleOrNull(),
    builder: (context, snapshot) {
      final row = snapshot.data;
      if (row == null) return const SizedBox.shrink();
      String message;
      try {
        message =
            (jsonDecode(row.valueJson) as Map<String, dynamic>)['message']
                as String;
      } on Object {
        message = 'Não foi possível concluir a última sincronização.';
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Última tentativa falhou: $message',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    },
  );
}
