import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/quotes/application/quote_service.dart';
import 'package:systock/core/utils/money.dart';
import 'package:go_router/go_router.dart';

class QuotesPage extends ConsumerWidget {
  const QuotesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Cotações e orçamentos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, db),
        icon: const Icon(Icons.add),
        label: const LocalizedText('Nova cotação'),
      ),
      body: StreamBuilder<List<Quote>>(
        stream:
            (db.select(db.quotes)
                  ..where((q) => q.deletedAt.isNull())
                  ..orderBy([(q) => OrderingTerm.desc(q.createdAt)]))
                .watch(),
        builder: (_, snapshot) {
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem cotações.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final quote = rows[i];
              return Card(
                child: ListTile(
                  onTap: () => context.go('/quotes/${quote.id}'),
                  leading: const Icon(Icons.request_quote_outlined),
                  title: Text(quote.documentNumber),
                  subtitle: LocalizedText(
                    '${_kindLabel(quote.kind)} · ${_statusLabel(quote.status)} · ${_date(quote.createdAt)}',
                  ),
                  trailing: Text(formatMoneyMinor(quote.totalMinor)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _kindLabel(String kind) => kind == 'budget' ? 'Orçamento' : 'Cotação';

  String _statusLabel(String status) => switch (status) {
    'draft' => 'Rascunho',
    'accepted' => 'Aceite',
    'rejected' => 'Rejeitado',
    'converted' => 'Convertido',
    _ => status,
  };

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _create(BuildContext context, AppDatabase db) async {
    final products = await (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull() & p.active.equals(true))).get();
    if (products.isEmpty || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'Cadastre um produto antes de criar o documento.',
            ),
          ),
        );
      }
      return;
    }
    var product = products.first, kind = 'quote';
    final quantity = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const LocalizedText('Nova cotação'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
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
                  onChanged: (v) => setState(() => kind = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: product.id,
                  decoration: InputDecoration(
                    labelText: 'Produto'.localized(context),
                  ),
                  items: [
                    for (final p in products)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(
                    () => product = products.firstWhere((p) => p.id == v),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantidade'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = int.tryParse(quantity.text) ?? 0;
    if (q <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('Informe uma quantidade válida.'),
          ),
        );
      }
      return;
    }
    final company = await db.select(db.companies).getSingleOrNull();
    final warehouse =
        await (db.select(db.warehouses)
              ..where((w) => w.deletedAt.isNull() & w.active.equals(true))
              ..limit(1))
            .getSingleOrNull();
    final user =
        await (db.select(db.users)
              ..where((u) => u.deletedAt.isNull() & u.active.equals(true))
              ..limit(1))
            .getSingleOrNull();
    if (company == null || warehouse == null || user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'Empresa, armazém ou utilizador não configurado.',
            ),
          ),
        );
      }
      return;
    }
    final result = await QuoteService(db).create(
      companyId: company.id,
      warehouseId: warehouse.id,
      userId: user.id,
      deviceId: company.deviceId,
      kind: kind,
      lines: [
        QuoteLineInput(product.id, product.name, q * 1000, product.saleMinor),
      ],
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Success() =>
            kind == 'budget'
                ? 'Orçamento guardado com sucesso.'
                : 'Cotação guardada com sucesso.',
          Failure(:final error) => error.userMessage,
        }),
      ),
    );
  }
}
