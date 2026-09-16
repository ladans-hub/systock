import 'package:logging/logging.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/network/connectivity_service.dart';
import 'package:systock/core/sync/google_drive_auth_service.dart';
import 'package:systock/core/sync/google_drive_transport.dart';
import 'package:systock/core/sync/sync_engine.dart';
import 'package:systock/core/sync/drive_recovery_snapshot.dart';
import 'package:systock/core/errors/result.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/sync/drive_vault_identity.dart';
import 'package:systock/core/sync/drive_vault_service.dart';
import 'package:systock/core/sync/drive_vault_store.dart';

class BackgroundSyncCoordinator {
  const BackgroundSyncCoordinator(this.db);
  final AppDatabase db;
  static bool _running = false;

  Future<void> synchronizeIfAuthorized() async {
    if (_running) return;
    _running = true;
    try {
      if (!await const ConnectivityService().hasInternet()) return;
      final session = await GoogleDriveAuthService.instance.reconnectSilently();
      if (session == null) {
        final binding = await DriveVaultService.binding(db);
        if (binding?['enabled'] == true) {
          throw StateError(
            'Volte a ligar a conta Google para retomar a sincronização automática.',
          );
        }
        return;
      }
      try {
        final binding = await DriveVaultService.binding(db);
        if (binding != null) {
          if (binding['enabled'] != true) return;
          if (binding['accountId'] != session.accountId) {
            throw StateError(
              'A conta Google mudou. Volte a ligar a conta da loja.',
            );
          }
          final documents = await getApplicationDocumentsDirectory();
          await DriveVaultService(
            db,
            GoogleDriveVaultStore(session.client),
            const SecureVaultSecrets(),
            documents,
            accountId: session.accountId,
            email: session.email,
          ).synchronize();
          final recovery = await DriveRecoverySnapshot(
            db,
            GoogleDriveSyncTransport(session.client),
          ).uploadLatest();
          if (recovery case Failure(:final error)) {
            throw StateError('${error.userMessage} ${error.cause ?? ''}');
          }
          return;
        }
        final transport = GoogleDriveSyncTransport(session.client);
        final result = await SyncEngine(db, transport).synchronize();
        if (result case Failure(:final error)) {
          throw StateError('${error.userMessage} ${error.cause ?? ''}');
        }
        if (result case Success<SyncSummary>(
          :final value,
        ) when value.uploaded > 0 || value.applied > 0) {
          final recovery = await DriveRecoverySnapshot(
            db,
            transport,
          ).uploadLatest();
          if (recovery case Failure(:final error)) {
            throw StateError('${error.userMessage} ${error.cause ?? ''}');
          }
        }
        await (db.delete(
          db.appSettings,
        )..where((s) => s.key.equals('sync.last_failure'))).go();
      } finally {
        session.client.close();
      }
    } catch (error, stack) {
      Logger(
        'BackgroundSync',
      ).warning('Sincronização automática falhou', error, stack);
      // Keep local work available, but retain the reason for the sync screen.
      try {
        await DriveVaultService.setting(db, 'sync.last_failure', {
          'at': DateTime.now().toUtc().toIso8601String(),
          'message': error is StateError ? error.message : error.toString(),
        });
      } catch (writeError, writeStack) {
        Logger(
          'BackgroundSync',
        ).warning('Não foi possível guardar a falha', writeError, writeStack);
      }
    } finally {
      _running = false;
    }
  }
}
