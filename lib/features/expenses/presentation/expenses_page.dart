import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/expenses/application/expense_service.dart';
import 'package:uuid/uuid.dart';

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        q = db.select(db.expenses)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(200);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Despesas'),
        actions: [
          FilledButton.icon(
            onPressed: () => add(context, db),
            icon: const Icon(Icons.add),
            label: const LocalizedText('Registrar'),
          ),
        ],
      ),
      body: StreamBuilder<List<Expense>>(
        stream: q.watch(),
        builder: (context, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.isEmpty) {
            return const Center(
              child: LocalizedText('Ainda não existem despesas.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: s.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = s.data![i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.payments_outlined),
                  ),
                  title: Text(e.description),
                  subtitle: LocalizedText(
                    '${e.paymentMethod} • ${e.createdAt.toLocal()}',
                  ),
                  trailing: LocalizedText(
                    '- ${formatMoneyMinor(e.amountMinor)}',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> add(BuildContext context, AppDatabase db) async {
    var categories = await db.select(db.expenseCategories).get();
    final company = await db.select(db.companies).getSingle(),
        user = await currentSessionUser(db),
        now = DateTime.now().toUtc();
    if (categories.isEmpty) {
      for (final name in const [
        'Energia',
        'Transporte',
        'Salários',
        'Internet',
        'Aluguer',
        'Manutenção',
        'Outros',
      ]) {
        await db
            .into(db.expenseCategories)
            .insert(
              ExpenseCategoriesCompanion.insert(
                id: const Uuid().v7(),
                companyId: company.id,
                name: name,
                createdAt: now,
                updatedAt: now,
                deviceId: company.deviceId,
              ),
            );
      }
      categories = await db.select(db.expenseCategories).get();
    }
    if (!context.mounted) return;
    String category = categories.first.id, method = 'cash';
    final description = TextEditingController(),
        amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Registrar despesa'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: category,
                  items: categories
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => category = v!),
                  decoration: InputDecoration(
                    labelText: 'Categoria'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  decoration: InputDecoration(
                    labelText: 'Descrição'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Valor'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: method,
                  items: const ['cash', 'card', 'mpesa', 'emola', 'transfer']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setDialog(() => method = v!),
                  decoration: InputDecoration(
                    labelText: 'Pagamento'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const LocalizedText('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final session = await (db.select(
      db.cashSessions,
    )..where((s) => s.status.equals('open'))).getSingleOrNull();
    final result = await ExpenseService(db).create(
      companyId: company.id,
      categoryId: category,
      description: description.text,
      amountMinor:
          ((double.tryParse(amount.text.replaceAll(',', '.')) ?? 0) * 100)
              .round(),
      paymentMethod: method,
      userId: user.id,
      deviceId: company.deviceId,
      cashSessionId: method == 'cash' ? session?.id : null,
    );
    if (context.mounted) {
      if (result case Failure(:final error)) {
        showAppFailure(context, error);
      }
    }
  }
}
