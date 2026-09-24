import 'package:drift/drift.dart' show CustomExpression, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/utils/quantity.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:systock/features/sales/application/sale_delivery_service.dart';
import 'package:systock/l10n/localized_text.dart';

class DeliveriesPage extends ConsumerStatefulWidget {
  const DeliveriesPage({super.key});

  @override
  ConsumerState<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends ConsumerState<DeliveriesPage> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final salesQuery = db.select(db.sales)
      ..where((sale) => sale.deletedAt.isNull())
      ..where((sale) => sale.status.isNotIn(['cancelled', 'refunded', 'draft']))
      ..orderBy([(sale) => OrderingTerm.desc(sale.createdAt)]);
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Gestão de entregas')),
      body: StreamBuilder<List<Sale>>(
        stream: salesQuery.watch(),
        builder: (context, salesSnapshot) {
          if (!salesSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sales = salesSnapshot.data!;
          if (sales.isEmpty) return _empty();
          return StreamBuilder<List<SaleItem>>(
            stream:
                (db.select(db.saleItems)..where(
                      (_) => const CustomExpression<bool>(
                        'delivered_quantity_milli < quantity_milli',
                      ),
                    ))
                    .watch(),
            builder: (context, itemsSnapshot) {
              if (!itemsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final salesById = {for (final sale in sales) sale.id: sale};
              final pendingItems = itemsSnapshot.data!
                  .where((item) => salesById.containsKey(item.saleId))
                  .toList();
              final filtered = pendingItems.where((item) {
                if (query.isEmpty) return true;
                final sale = salesById[item.saleId]!;
                return sale.documentNumber.toLowerCase().contains(query) ||
                    item.description.toLowerCase().contains(query);
              }).toList();
              final grouped = <String, List<SaleItem>>{};
              for (final item in filtered) {
                grouped.putIfAbsent(item.saleId, () => []).add(item);
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: search,
                      onChanged: (value) =>
                          setState(() => query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        labelText: 'Pesquisar entrega'.localized(context),
                        hintText: 'Documento ou produto'.localized(context),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar'.localized(context),
                                onPressed: () {
                                  search.clear();
                                  setState(() => query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: LocalizedText(
                        '${grouped.length} vendas com produtos por entregar',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: grouped.isEmpty
                        ? _empty(searching: query.isNotEmpty)
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: grouped.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final saleId = grouped.keys.elementAt(index);
                              final sale = salesById[saleId]!;
                              final items = grouped[saleId]!;
                              return _DeliveryCard(
                                sale: sale,
                                items: items,
                                onDeliverItem: (item) => _deliverItem(db, item),
                                onDeliverAll: () =>
                                    _deliverAll(db, sale, items),
                                onViewSale: () =>
                                    context.push('/sales/${sale.id}'),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _empty({bool searching = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off : Icons.inventory_2_outlined,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          LocalizedText(
            searching
                ? 'Nenhuma entrega corresponde à pesquisa.'
                : 'Não existem produtos pendentes de entrega.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Future<void> _deliverItem(AppDatabase db, SaleItem item) async {
    final pending = item.quantityMilli - item.deliveredQuantityMilli;
    final quantity = TextEditingController(text: formatQuantity(pending));
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Registrar entrega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.description),
            const SizedBox(height: 6),
            LocalizedText('Pendente: ${formatQuantity(pending)}'),
            const SizedBox(height: 12),
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantidade entregue'.localized(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(dialog, parseQuantityMilli(quantity.text));
              } on FormatException {
                showAppError(context, 'Informe uma quantidade válida.');
              }
            },
            child: const LocalizedText('Registrar entrega'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final result = await SaleDeliveryService(
      db,
    ).deliver(item: item, quantityMilli: value);
    if (!mounted) return;
    if (result case Failure(:final error)) {
      await showAppFailure(context, error);
    } else {
      await showAppAlert(context, 'Entrega registrada.');
    }
  }

  Future<void> _deliverAll(
    AppDatabase db,
    Sale sale,
    List<SaleItem> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Entregar todos os produtos?'),
        content: LocalizedText(
          'Todos os produtos pendentes da venda ${sale.documentNumber} serão marcados como entregues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Entregar tudo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await SaleDeliveryService(db).deliverAll(items);
    if (!mounted) return;
    if (result case Failure(:final error)) {
      await showAppFailure(context, error);
    } else {
      await showAppAlert(context, 'Todos os produtos foram entregues.');
    }
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.sale,
    required this.items,
    required this.onDeliverItem,
    required this.onDeliverAll,
    required this.onViewSale,
  });

  final Sale sale;
  final List<SaleItem> items;
  final ValueChanged<SaleItem> onDeliverItem;
  final VoidCallback onDeliverAll, onViewSale;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(child: Text('${items.length}')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.documentNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${sale.createdAt.toLocal()} · ${formatMoneyMinor(sale.totalMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onViewSale,
                icon: const Icon(Icons.visibility_outlined),
                label: const LocalizedText('Ver venda'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: onDeliverAll,
                icon: const Icon(Icons.done_all),
                label: const LocalizedText('Entregar tudo'),
              ),
            ],
          ),
          const Divider(height: 24),
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(item.description),
              subtitle: LocalizedText(
                'Entregue ${formatQuantity(item.deliveredQuantityMilli)} de ${formatQuantity(item.quantityMilli)} · Pendente ${formatQuantity(item.quantityMilli - item.deliveredQuantityMilli)}',
              ),
              trailing: OutlinedButton.icon(
                onPressed: () => onDeliverItem(item),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const LocalizedText('Entregar'),
              ),
            ),
        ],
      ),
    ),
  );
}
