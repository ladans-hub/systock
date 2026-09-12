import 'package:systock/core/widgets/action_colors.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/features/quotes/application/quote_service.dart';

class QuoteDetailPage extends ConsumerStatefulWidget {
  const QuoteDetailPage(this.id, {super.key});
  final String id;

  @override
  ConsumerState<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends ConsumerState<QuoteDetailPage> {
  Future<({Quote quote, List<QuoteItem> items})> _load(AppDatabase db) async =>
      (
        quote: await (db.select(
          db.quotes,
        )..where((q) => q.id.equals(widget.id))).getSingle(),
        items: await (db.select(
          db.quoteItems,
        )..where((item) => item.quoteId.equals(widget.id))).get(),
      );

  String _kind(String value) => value == 'budget' ? 'Orçamento' : 'Cotação';
  String _status(String value) => switch (value) {
    'draft' => 'Rascunho',
    'accepted' => 'Aceite',
    'rejected' => 'Rejeitado',
    'converted' => 'Convertido',
    _ => value,
  };

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder(
      future: _load(db),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final date = data.quote.createdAt.toLocal();
        return Scaffold(
          appBar: AppBar(
            leading: const AdaptiveBackButton(fallbackPath: '/quotes'),
            title: Text(data.quote.documentNumber),
            actions: [
              IconButton(
                tooltip: 'Editar'.localized(context),
                onPressed: () => _edit(db, data.quote, data.items),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Apagar'.localized(context),
                onPressed: () => _archive(db, data.quote),
                color: removalActionColor,
                icon: const Icon(Icons.delete_outline),
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
                  _Info('Documento', _kind(data.quote.kind)),
                  _Info('Estado', _status(data.quote.status)),
                  _Info(
                    'Data',
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                  ),
                  _Info('Total', formatMoneyMinor(data.quote.totalMinor)),
                ],
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'Itens',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final item in data.items)
                      ListTile(
                        title: Text(item.description),
                        subtitle: LocalizedText(
                          '${item.quantityMilli / 1000} × ${formatMoneyMinor(item.unitPriceMinor)}',
                        ),
                        trailing: Text(
                          formatMoneyMinor(item.totalMinor),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
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

  Future<void> _edit(
    AppDatabase db,
    Quote quote,
    List<QuoteItem> currentItems,
  ) async {
    final products = await (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull() & p.active.equals(true))).get();
    if (!mounted || products.isEmpty || currentItems.isEmpty) {
      if (mounted) {
        showAppError(context, 'Não existem itens disponíveis para editar.');
      }
      return;
    }
    final existing = currentItems.first;
    var kind = quote.kind == 'budget' ? 'budget' : 'quote';
    var product = products.firstWhere(
      (item) => item.id == existing.productId,
      orElse: () => products.first,
    );
    final quantity = TextEditingController(
      text: (existing.quantityMilli / 1000).toString(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: LocalizedText('Editar ${_kind(kind).toLowerCase()}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: 'Documento'.localized(context),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'quote',
                      child: LocalizedText('Cotação'),
                    ),
                    DropdownMenuItem(
                      value: 'budget',
                      child: LocalizedText('Orçamento'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => kind = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: product.id,
                  decoration: InputDecoration(
                    labelText: 'Produto'.localized(context),
                  ),
                  items: [
                    for (final item in products)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (value) => setDialogState(
                    () => product = products.firstWhere(
                      (item) => item.id == value,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantidade'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Guardar alterações'),
            ),
          ],
        ),
      ),
    );
    final parsed = double.tryParse(quantity.text.replaceAll(',', '.'));
    if (confirmed != true || parsed == null || parsed <= 0) return;
    final result = await QuoteService(db).update(
      current: quote,
      kind: kind,
      lines: [
        QuoteLineInput(
          product.id,
          product.name,
          (parsed * 1000).round(),
          product.saleMinor,
        ),
      ],
    );
    if (!mounted) return;
    if (result case Failure(:final error)) {
      showAppFailure(context, error);
    } else {
      _message('Documento atualizado.');
    }
    if (result is Success<void>) setState(() {});
  }

  Future<void> _archive(AppDatabase db, Quote quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: LocalizedText('Apagar ${_kind(quote.kind).toLowerCase()}?'),
        content: const LocalizedText(
          'O documento deixará de aparecer na listagem, mas o registo histórico será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: removalActionColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await QuoteService(db).archive(quote);
    if (!mounted) return;
    switch (result) {
      case Success():
        context.go('/quotes');
      case Failure(:final error):
        showAppFailure(context, error);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}
