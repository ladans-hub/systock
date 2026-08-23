import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/widgets/platform_controls.dart';

class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder(
      future: Future.wait<Object>([
        (db.select(db.purchases)..where((p) => p.id.equals(id))).getSingle(),
        (db.select(
          db.purchaseItems,
        )..where((i) => i.purchaseId.equals(id))).get(),
      ]),
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final purchase = snapshot.data![0] as Purchase,
            items = snapshot.data![1] as List<PurchaseItem>;
        return Scaffold(
          appBar: AppBar(
            leading: const AdaptiveBackButton(),
            title: Text(purchase.documentNumber),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                children: [
                  Chip(label: Text(purchase.status)),
                  Chip(label: Text(formatMoneyMinor(purchase.totalMinor))),
                  Chip(
                    label: LocalizedText(
                      '${formatMoneyMinor(purchase.paidMinor)} pago',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        title: Text(item.productId),
                        subtitle: LocalizedText(
                          '${item.quantityMilli / 1000} × ${formatMoneyMinor(item.unitCostMinor)}',
                        ),
                        trailing: Text(formatMoneyMinor(item.totalMinor)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
