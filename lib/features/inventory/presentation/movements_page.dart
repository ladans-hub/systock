import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';

class MovementsPage extends ConsumerWidget {
  const MovementsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        q = db.select(db.inventoryMovements)
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(200);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Movimentos de stock'),
      ),
      body: StreamBuilder<List<InventoryMovement>>(
        stream: q.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final m = snapshot.data![i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      m.quantityMilli >= 0 ? Icons.add : Icons.remove,
                    ),
                  ),
                  title: Text(m.movementType),
                  subtitle: LocalizedText(
                    '${m.reason ?? ''}\n${m.createdAt.toLocal()}',
                  ),
                  isThreeLine: true,
                  trailing: LocalizedText(
                    '${m.quantityMilli >= 0 ? '+' : ''}${m.quantityMilli / 1000}',
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
