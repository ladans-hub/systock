import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/utils/money.dart';

class SalesPage extends ConsumerWidget {
  const SalesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final query = db.select(db.sales)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(100);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Vendas')),
      body: StreamBuilder<List<Sale>>(
        stream: query.watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem vendas.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final sale = snapshot.data![i];
              return Card(
                child: ListTile(
                  onTap: () => context.go('/sales/${sale.id}'),
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text(sale.documentNumber),
                  subtitle: LocalizedText(
                    '${sale.createdAt.toLocal()} • ${sale.status}',
                  ),
                  trailing: Text(
                    formatMoneyMinor(sale.totalMinor),
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
