import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart' as database;
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/l10n/localized_text.dart';

final inboxNotificationsProvider = StreamProvider<List<database.Notification>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notifications)
        ..where((n) => n.archivedAt.isNull() & n.deletedAt.isNull())
        ..orderBy([
          (n) => OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc),
        ]))
      .watch();
});

class NotificationBell extends ConsumerWidget {
  const NotificationBell({this.iconSize, super.key});

  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref
            .watch(inboxNotificationsProvider)
            .valueOrNull
            ?.where((notification) => notification.readAt == null)
            .length ??
        0;
    return IconButton(
      onPressed: () => context.go('/alerts'),
      tooltip: 'Alertas'.localized(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: Icon(Icons.notifications_outlined, size: iconSize),
      ),
    );
  }
}
