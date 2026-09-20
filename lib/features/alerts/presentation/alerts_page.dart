import 'package:systock/core/widgets/notification_bell.dart';
import 'package:systock/core/widgets/action_colors.dart';
import 'package:drift/drift.dart';
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
    final notifications = ref.watch(inboxNotificationsProvider);
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
      body: Builder(
        builder: (_) {
          final rows = notifications.valueOrNull ?? const [];
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
                title: Text(
                  alert.title,
                  style: TextStyle(
                    fontWeight: alert.readAt == null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  alert.body,
                  style: TextStyle(
                    fontWeight: alert.readAt == null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: PopupMenuButton<_NotificationAction>(
                  tooltip: 'Ações da notificação'.localized(context),
                  onSelected: (action) async {
                    final now = DateTime.now().toUtc();
                    final update = action == _NotificationAction.archive
                        ? NotificationsCompanion(
                            archivedAt: Value(now),
                            readAt: Value(now),
                            updatedAt: Value(now),
                          )
                        : NotificationsCompanion(
                            deletedAt: Value(now),
                            readAt: Value(now),
                            updatedAt: Value(now),
                          );
                    await (db.update(
                      db.notifications,
                    )..where((n) => n.id.equals(alert.id))).write(update);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _NotificationAction.archive,
                      child: LocalizedText('Arquivar'),
                    ),
                    PopupMenuItem(
                      value: _NotificationAction.delete,
                      child: LocalizedText(
                        'Apagar',
                        style: TextStyle(color: removalActionColor),
                      ),
                    ),
                  ],
                ),
                onTap: () async {
                  if (alert.readAt != null) return;
                  final now = DateTime.now().toUtc();
                  await (db.update(db.notifications)..where(
                        (n) => n.id.equals(alert.id) & n.readAt.isNull(),
                      ))
                      .write(
                        NotificationsCompanion(
                          readAt: Value(now),
                          updatedAt: Value(now),
                        ),
                      );
                },
              );
            },
          );
        },
      ),
    );
  }
}

enum _NotificationAction { archive, delete }
