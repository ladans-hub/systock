import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/inventory/application/stock_count_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';

class StockCountDetailPage extends ConsumerWidget {
  const StockCountDetailPage(this.id, {super.key});
  final String id;
  Future<
    ({StockCount count, List<({StockCountItem item, String product})> lines})
  >
  load(AppDatabase db) async {
    final count = await (db.select(
          db.stockCounts,
        )..where((c) => c.id.equals(id))).getSingle(),
        items = await (db.select(
          db.stockCountItems,
        )..where((i) => i.stockCountId.equals(id))).get();
    final lines = <({StockCountItem item, String product})>[];
    for (final item in items) {
      final p = await (db.select(
        db.products,
      )..where((p) => p.id.equals(item.productId))).getSingle();
      lines.add((item: item, product: p.name));
    }
    return (count: count, lines: lines);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder(
      future: load(db),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!,
            complete = data.lines.every(
              (l) => l.item.countedQuantityMilli != null,
            );
        return Scaffold(
          appBar: AppBar(
            leading: const AdaptiveBackButton(),
            title: Text(data.count.documentNumber),
            actions: [
              if (data.count.status == 'draft')
                FilledButton.icon(
                  onPressed: complete ? () => approve(context, db) : null,
                  icon: const Icon(Icons.check),
                  label: const LocalizedText('Aprovar'),
                ),
            ],
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.lines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final line = data.lines[i],
                  counted = line.item.countedQuantityMilli;
              return Card(
                child: ListTile(
                  onTap: data.count.status == 'draft'
                      ? () => edit(context, db, line.item, line.product)
                      : null,
                  title: Text(line.product),
                  subtitle: LocalizedText(
                    'Sistema: ${line.item.systemQuantityMilli / 1000}  •  Contado: ${counted == null ? '—' : counted / 1000}',
                  ),
                  trailing: counted == null
                      ? const Chip(label: LocalizedText('Pendente'))
                      : LocalizedText(
                          'Diferença ${(counted - line.item.systemQuantityMilli) / 1000}',
                        ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> approve(BuildContext context, AppDatabase db) async {
    final user = await currentSessionUser(db),
        result = await StockCountService(db).approve(id, userId: user.id);
    if (!context.mounted) return;
    if (result is Success<void>) {
      context.go('/inventory/counts');
    } else if (result case Failure(:final error)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Future<void> edit(
    BuildContext context,
    AppDatabase db,
    StockCountItem item,
    String product,
  ) async {
    final controller = TextEditingController(
      text: item.countedQuantityMilli == null
          ? ''
          : (item.countedQuantityMilli! / 1000).toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(product),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantidade contada'.localized(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const LocalizedText('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await StockCountService(db).count(
        item.id,
        ((double.tryParse(controller.text.replaceAll(',', '.')) ?? 0) * 1000)
            .round(),
      );
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    }
  }
}
