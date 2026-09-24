import 'package:systock/core/widgets/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/printing/pdf_receipt_printer.dart';
import 'package:systock/core/printing/receipt.dart' as model;
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/sales/application/reverse_sale.dart';
import 'package:systock/features/sales/application/return_sale.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/core/database/document_number_service.dart';
import 'package:systock/features/sales/application/sale_delivery_service.dart';
import 'package:systock/core/utils/quantity.dart';

class SaleDetailPage extends ConsumerWidget {
  const SaleDetailPage(this.saleId, {super.key});
  final String saleId;
  Future<
    ({Sale sale, List<SaleItem> items, List<Payment> payments, Company company})
  >
  load(AppDatabase db) async {
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();
    return (
      sale: sale,
      items: await (db.select(
        db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).get(),
      payments: await (db.select(
        db.payments,
      )..where((p) => p.saleId.equals(saleId))).get(),
      company: await (db.select(
        db.companies,
      )..where((c) => c.id.equals(sale.companyId))).getSingle(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: load(ref.watch(databaseProvider)),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final v = snapshot.data!;
      final receipt = model.Receipt(
        company: v.company.tradeName,
        taxId: v.company.taxId,
        documentNumber: v.sale.documentNumber,
        issuedAt: v.sale.createdAt,
        lines: v.items
            .map(
              (i) => model.ReceiptLine(
                description: i.description,
                quantityMilli: i.quantityMilli,
                unitPriceMinor: i.unitPriceMinor,
                totalMinor: i.totalMinor,
              ),
            )
            .toList(),
        subtotalMinor: v.sale.subtotalMinor,
        discountMinor: v.sale.discountMinor,
        totalMinor: v.sale.totalMinor,
        payments: {for (final p in v.payments) p.method: p.amountMinor},
        footer: 'Obrigado pela preferência!',
      );
      return Scaffold(
        appBar: AppBar(
          leading: const AdaptiveBackButton(),
          title: AppBarTitle(v.sale.documentNumber, localized: false),
          actions: [
            IconButton(
              onPressed: () async {
                final result = await SystemReceiptPrinter().print(receipt);
                if (context.mounted && result is model.PrintFailure) {
                  showAppError(context, result.message);
                }
              },
              icon: const Icon(Icons.print),
              tooltip: 'Imprimir'.localized(context),
            ),
            if (!['cancelled', 'refunded'].contains(v.sale.status))
              IconButton(
                onPressed: () => _returnItem(
                  context,
                  ref.read(databaseProvider),
                  v.sale,
                  v.items,
                  v.company,
                ),
                icon: const Icon(Icons.assignment_return_outlined),
                tooltip: 'Devolver item'.localized(context),
              ),
            if (v.sale.status != 'cancelled' && v.sale.reversalOfId == null)
              IconButton(
                onPressed: () async {
                  final reason = TextEditingController();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const LocalizedText('Cancelar venda?'),
                      content: TextField(
                        controller: reason,
                        decoration: InputDecoration(
                          labelText: 'Motivo obrigatório'.localized(context),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const LocalizedText('Voltar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const LocalizedText('Cancelar venda'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  final db = ref.read(databaseProvider),
                      user = await currentSessionUser(db);
                  final documentNumber = await DocumentNumberService(db).next(
                    companyId: v.company.id,
                    type: 'sale_cancellation',
                    prefix: 'CAN',
                    deviceId: v.company.deviceId,
                  );
                  final result = await ReverseSale(db)(
                    saleId: v.sale.id,
                    documentNumber: documentNumber,
                    userId: user.id,
                    deviceId: v.company.deviceId,
                    reason: reason.text,
                  );
                  if (!context.mounted) return;
                  switch (result) {
                    case Success():
                      context.go('/sales');
                    case Failure(:final error):
                      showAppFailure(context, error);
                  }
                },
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Cancelar venda'.localized(context),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric('Total', v.sale.totalMinor),
                _Metric('Custo', v.sale.costMinor),
                _Metric('Lucro bruto', v.sale.totalMinor - v.sale.costMinor),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                LocalizedText(
                  'Itens',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (v.items.any(
                  (item) => item.deliveredQuantityMilli < item.quantityMilli,
                ))
                  FilledButton.icon(
                    onPressed: () => _deliverAll(
                      context,
                      ref.read(databaseProvider),
                      v.items,
                    ),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const LocalizedText('Entregar tudo'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: v.items.map((i) {
                  final pending = i.quantityMilli - i.deliveredQuantityMilli;
                  final status = pending <= 0
                      ? 'Entregue'
                      : i.deliveredQuantityMilli > 0
                      ? 'Parcialmente entregue'
                      : 'Não entregue';
                  return ListTile(
                    leading: Icon(
                      pending <= 0
                          ? Icons.check_circle_outline
                          : Icons.schedule_outlined,
                    ),
                    title: Text(i.description),
                    subtitle: LocalizedText(
                      '${formatQuantity(i.quantityMilli)} × ${formatMoneyMinor(i.unitPriceMinor)}\n$status · Entregue ${formatQuantity(i.deliveredQuantityMilli)} de ${formatQuantity(i.quantityMilli)}',
                    ),
                    isThreeLine: true,
                    trailing: pending <= 0
                        ? Text(formatMoneyMinor(i.totalMinor))
                        : FilledButton.tonal(
                            onPressed: () => _deliverItem(
                              context,
                              ref.read(databaseProvider),
                              i,
                            ),
                            child: const LocalizedText('Entregar'),
                          ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            LocalizedText(
              'Pagamentos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Card(
              child: Column(
                children: v.payments
                    .map(
                      (p) => ListTile(
                        title: Text(
                          p.method == 'change:cash' ? 'Troco' : p.method,
                        ),
                        trailing: Text(formatMoneyMinor(p.amountMinor)),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _deliverItem(
    BuildContext context,
    AppDatabase db,
    SaleItem item,
  ) async {
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
              decoration: const InputDecoration(
                labelText: 'Quantidade entregue',
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
                return;
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
    if (!context.mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      context.pushReplacement('/sales/$saleId');
    }
  }

  Future<void> _deliverAll(
    BuildContext context,
    AppDatabase db,
    List<SaleItem> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Entregar todos os itens?'),
        content: const LocalizedText(
          'Todos os produtos pendentes desta venda serão marcados como entregues.',
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
    if (!context.mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      context.pushReplacement('/sales/$saleId');
    }
  }

  Future<void> _returnItem(
    BuildContext context,
    AppDatabase db,
    Sale sale,
    List<SaleItem> items,
    Company company,
  ) async {
    var item = items.first;
    final quantity = TextEditingController(text: '1'),
        reason = TextEditingController();
    var restock = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Devolução parcial ou total'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                initialValue: item.id,
                items: [
                  for (final line in items)
                    DropdownMenuItem(
                      value: line.id,
                      child: Text(line.description),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => item = items.firstWhere((i) => i.id == v)),
              ),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantidade'.localized(context),
                ),
              ),
              TextField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: 'Motivo obrigatório'.localized(context),
                ),
              ),
              SwitchListTile(
                title: const LocalizedText('Repor no stock'),
                value: restock,
                onChanged: (v) => setState(() => restock = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final user = await currentSessionUser(db),
        q = int.tryParse(quantity.text) ?? 0;
    final result = await ReturnSale(db)(
      saleId: sale.id,
      lines: [ReturnLineInput(item.id, q * 1000, restock: restock)],
      reason: reason.text,
      userId: user.id,
      deviceId: company.deviceId,
    );
    if (!context.mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      await showAppAlert(context, 'Devolução concluída.');
    }
    if (!context.mounted) return;
    if (result is Success<String>) context.go('/sales');
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.minor);
  final String label;
  final int minor;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Text(
              formatMoneyMinor(minor),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );
}
