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
      if (session == null) return;
      try {
        final binding = await DriveVaultService.binding(db);
        if (binding != null && binding['enabled'] == true) {
          if (binding['accountId'] != session.accountId) return;
          final documents = await getApplicationDocumentsDirectory();
          await DriveVaultService(
            db,
            GoogleDriveVaultStore(session.client),
            const SecureVaultSecrets(),
            documents,
            accountId: session.accountId,
            email: session.email,
          ).synchronize();
          return;
        }
        final transport = GoogleDriveSyncTransport(session.client);
        final result = await SyncEngine(db, transport).synchronize();
        if (result case Success<SyncSummary>(
          :final value,
        ) when value.uploaded > 0 || value.applied > 0) {
          await DriveRecoverySnapshot(db, transport).uploadLatest();
        }
      } finally {
        session.client.close();
      }
    } catch (_) {
      // Background sync is best-effort and never affects the local workflow.
    } finally {
      _running = false;
    }
  }
}
