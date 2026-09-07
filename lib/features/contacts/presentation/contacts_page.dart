import 'package:systock/core/widgets/error_dialog.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/utils/money.dart';
import 'package:uuid/uuid.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/customers/application/customer_credit_service.dart';

enum ContactKind { customer, supplier }

class ContactsPage extends ConsumerWidget {
  const ContactsPage(this.kind, {super.key});
  final ContactKind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider),
        customers = kind == ContactKind.customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(customers ? 'Clientes' : 'Fornecedores'),
        actions: [
          IconButton(
            onPressed: () => add(context, db),
            icon: const Icon(Icons.person_add),
          ),
        ],
      ),
      body: customers
          ? StreamBuilder<List<Customer>>(
              stream: (db.select(
                db.customers,
              )..where((c) => c.deletedAt.isNull())).watch(),
              builder: (context, s) => list(
                context,
                s.data?.map((c) => (c.name, c.phone, c.balanceMinor)).toList(),
                customers: s.data,
                db: db,
              ),
            )
          : StreamBuilder<List<Supplier>>(
              stream: (db.select(
                db.suppliers,
              )..where((s) => s.deletedAt.isNull())).watch(),
              builder: (context, s) => list(
                context,
                s.data?.map((c) => (c.name, c.phone, c.balanceMinor)).toList(),
              ),
            ),
    );
  }

  Widget list(
    BuildContext context,
    List<(String, String?, int)>? rows, {
    List<Customer>? customers,
    AppDatabase? db,
  }) {
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return const Center(child: LocalizedText('Ainda não existem registros.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => Card(
        child: ListTile(
          onTap: customers == null || db == null
              ? null
              : () => _customerDetails(context, db, customers[i]),
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(rows[i].$1),
          subtitle: Text(rows[i].$2 ?? 'Sem telefone'),
          trailing: Text(formatMoneyMinor(rows[i].$3)),
        ),
      ),
    );
  }

  Future<void> _customerDetails(
    BuildContext context,
    AppDatabase db,
    Customer customer,
  ) async {
    final amount = TextEditingController();
    final movements =
        await (db.select(db.customerAccountMovements)
              ..where((m) => m.customerId.equals(customer.id))
              ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
            .get();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(customer.name),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                'Saldo: ${formatMoneyMinor(customer.balanceMinor)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Registrar pagamento'.localized(context),
                ),
              ),
              const SizedBox(height: 12),
              LocalizedText('Últimos movimentos (${movements.length})'),
              for (final movement in movements.take(5))
                LocalizedText(
                  '${movement.type}: ${formatMoneyMinor(movement.amountMinor)}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const LocalizedText('Fechar'),
          ),
          FilledButton(
            onPressed: customer.balanceMinor <= 0
                ? null
                : () async {
                    int value;
                    try {
                      value = parseMoneyMinor(amount.text);
                    } on FormatException {
                      return;
                    }
                    final result = await CustomerCreditService(db)
                        .recordPayment(
                          customerId: customer.id,
                          amountMinor: value,
                          deviceId: customer.deviceId,
                        );
                    if (!dialog.mounted) return;
                    Navigator.pop(dialog);
                    if (result case Failure(:final error)) {
                      showAppFailure(context, error);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Pagamento registrado.')),
                      );
                    }
                  },
            child: const LocalizedText('Registrar'),
          ),
        ],
      ),
    );
  }

  Future<void> add(BuildContext context, AppDatabase db) async {
    final name = TextEditingController(), phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          kind == ContactKind.customer ? 'Novo cliente' : 'Novo fornecedor',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Nome'.localized(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              decoration: InputDecoration(
                labelText: 'Telefone'.localized(context),
              ),
            ),
          ],
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
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc(),
        id = const Uuid().v7();
    if (kind == ContactKind.customer) {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: id,
              companyId: company.id,
              name: name.text.trim(),
              phone: Value(
                phone.text.trim().isEmpty ? null : phone.text.trim(),
              ),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
    } else {
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: id,
              companyId: company.id,
              name: name.text.trim(),
              phone: Value(
                phone.text.trim().isEmpty ? null : phone.text.trim(),
              ),
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
    }
  }
}
