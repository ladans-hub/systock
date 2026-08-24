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
              final incoming = m.quantityMilli > 0;
              final color = incoming ? Colors.green : Colors.red;
              return Card(
                color: color.withValues(alpha: 0.10),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: color.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Icon(
                      incoming ? Icons.arrow_downward : Icons.arrow_upward,
                      color: Colors.white,
                    ),
                  ),
                  title: LocalizedText(
                    _movementLabel(m.movementType),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: LocalizedText(
                    '${m.reason ?? ''}\n${m.createdAt.toLocal()}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    '${incoming ? '+' : ''}${m.quantityMilli / 1000}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _movementLabel(String type) => switch (type) {
    'purchase' => 'Compra',
    'sale' => 'Venda',
    'adjustmentIn' => 'Ajuste de entrada',
    'adjustmentOut' => 'Ajuste de saída',
    'transferIn' => 'Transferência recebida',
    'transferOut' => 'Transferência expedida',
    'returnIn' => 'Devolução',
    'damaged' => 'Produto danificado',
    'expired' => 'Produto vencido',
    'initialStock' => 'Stock inicial',
    'production' => 'Produção',
    'cancellation' => 'Cancelamento',
    _ => type,
  };
}
