import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/notifications/local_notification_service.dart';
import 'package:systock/features/alerts/application/alert_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';

class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final query = db.select(db.notifications)
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(fallbackPath: '/dashboard'),
        title: const LocalizedText('Central de alertas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final company = await db.select(db.companies).getSingle();
              await LocalNotificationService.instance.requestPermissions();
              await AlertService(
                db,
              ).refresh(company.id, company.deviceId, notify: true);
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Notification>>(
        stream: query.watch(),
        builder: (_, snapshot) {
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: LocalizedText('Nenhum alerta ativo.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final alert = rows[i];
              return ListTile(
                leading: Icon(
                  alert.type == 'low_stock'
                      ? Icons.inventory_outlined
                      : Icons.notifications_outlined,
                ),
                title: Text(alert.title),
                subtitle: Text(alert.body),
                trailing: alert.readAt == null
                    ? const Badge(label: LocalizedText('Novo'))
                    : null,
                onTap: () =>
                    (db.update(
                      db.notifications,
                    )..where((n) => n.id.equals(alert.id))).write(
                      NotificationsCompanion(
                        readAt: Value(DateTime.now().toUtc()),
                      ),
                    ),
              );
            },
          );
        },
      ),
    );
  }
}
