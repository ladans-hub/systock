import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/sync/drive_vault_identity.dart';
import 'package:systock/core/sync/drive_vault_service.dart';
import 'package:systock/core/sync/drive_vault_store.dart';
import 'package:systock/core/sync/vault_cipher.dart';

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
      _syncAnimationController.repeat();
    } else {
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
    _setBusy(true);
    try {
      final connected = await GoogleDriveAuthService.instance.connect();
      if (!mounted) return;
      setState(() {
        session = connected;
        email = connected.email;
      });
      final bindingResult = await _ensureVaultBinding(connected);
      if (!mounted || !bindingResult) return;
      await InitialSyncSnapshot(ref.read(databaseProvider)).enqueue();
      await _saveSetting('sync.google_drive', {
        'connected': true,
        'email': connected.email,
      });
      await synchronize();
    } catch (error) {
      if (mounted) {
        await showAppError(
          context,
          'Não foi possível conectar. Verifique a configuração OAuth da plataforma.',
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
    final saved = await DriveVaultService.binding(ref.read(databaseProvider));
    if (saved != null &&
        saved['companyId'] == company.id &&
        saved['accountId'] == connected.accountId) {
      return true;
    }
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
      final key = await _recoveryKeyDialog(existingBackup: true);
      if (key == null) return false;
      if (await _businessRecordCount() == 0) {
        final history = await vault.backups(company.id, claimId: claim.id);
        if (history.isEmpty) {
          throw StateError('Não existe backup desta loja no Google Drive.');
        }
        await vault.restore(claim, history.first, key);
        await _restartAfterRecovery();
        return false;
      }
      await vault.reconnect(claim, recoveryKey: key);
      return true;
    }
    if (claims.isNotEmpty && await _businessRecordCount() == 0) {
      final claim = claims.first;
      if (claim.accountId != connected.accountId) {
        throw StateError('A conta Google não corresponde à loja selecionada.');
      }
      final key = await _recoveryKeyDialog(existingBackup: true);
      if (key == null) return false;
      final history = await vault.backups(claim.companyId, claimId: claim.id);
      if (history.isEmpty) {
        throw StateError('Não existe backup desta loja no Google Drive.');
      }
      await vault.restore(claim, history.first, key);
      await _restartAfterRecovery();
      return false;
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

  Future<int> _businessRecordCount() async {
    final db = ref.read(databaseProvider);
    final row = await db.customSelect('''
      SELECT (SELECT COUNT(*) FROM products WHERE deleted_at IS NULL) +
      (SELECT COUNT(*) FROM sales WHERE deleted_at IS NULL) +
      (SELECT COUNT(*) FROM purchases WHERE deleted_at IS NULL) +
      (SELECT COUNT(*) FROM inventory_movements) AS total
    ''').getSingle();
    return row.read<int>('total');
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
                  ? 'Introduza a chave de recuperação da loja para transferir a caixa para este computador.'
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
    await GoogleDriveAuthService.instance.disconnect();
    await _saveSetting('sync.google_drive', {'connected': false});
    final vaultBinding = await DriveVaultService.binding(
      ref.read(databaseProvider),
    );
    if (vaultBinding != null) {
      await DriveVaultService.setting(
        ref.read(databaseProvider),
        DriveVaultService.bindingSetting,
        {...vaultBinding, 'enabled': false},
      );
    }
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
      final message = await (await _vault(current!)).synchronize();
      if (!mounted) return;
      _setBusy(false);
      setState(() => lastMessage = message);
      return;
    } catch (_) {
      // Keep the legacy operation log as a compatibility fallback for stores
      // connected before the encrypted vault was introduced.
    }
    final transport = GoogleDriveSyncTransport(current!.client);
    final result = await SyncEngine(
      ref.read(databaseProvider),
      transport,
    ).synchronize();
    if (!mounted) return;
    _setBusy(false);
    setState(() {
      lastMessage = switch (result) {
        Success(:final value) =>
          'Concluído: ${value.uploaded} enviadas, ${value.applied} recebidas, ${value.ignored} ignoradas.',
        Failure(:final error) => error.userMessage,
      };
    });
    if (result case Failure(:final error)) {
      await showAppFailure(context, error);
    }
    if (result is Success<SyncSummary>) {
      await DriveRecoverySnapshot(
        ref.read(databaseProvider),
        transport,
      ).uploadLatest();
      await _saveSetting('sync.last_success', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'summary': lastMessage ?? '',
      });
    } else {
      await _saveSetting('sync.last_failure', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'message': lastMessage ?? '',
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
                        icon: AnimatedBuilder(
                          animation: _syncAnimationController,
                          child: const Icon(Icons.sync),
                          builder: (context, child) => Transform.rotate(
                            angle: _syncAnimationController.value * 2 * math.pi,
                            child: child,
                          ),
                        ),
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
