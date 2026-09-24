import 'package:systock/core/widgets/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/cash/application/cash_session_service.dart';
import 'package:uuid/uuid.dart';

class CashPage extends ConsumerWidget {
  const CashPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Controle de caixa')),
      body: FutureBuilder(
        future: load(db),
        builder: (context, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = s.data!, session = data.$2;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session == null ? 'Caixa fechado' : 'Caixa aberto',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (session != null)
                        LocalizedText(
                          'Saldo inicial: ${formatMoneyMinor(session.openingMinor)}\nAberto em: ${session.createdAt.toLocal()}',
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => session == null
                            ? open(context, db, data.$1)
                            : close(context, db, session),
                        icon: Icon(
                          session == null ? Icons.lock_open : Icons.lock,
                        ),
                        label: Text(
                          session == null ? 'Abrir caixa' : 'Fechar caixa',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (session != null) ...[
                const SizedBox(height: 16),
                StreamBuilder<List<CashMovement>>(
                  stream: (db.select(
                    db.cashMovements,
                  )..where((m) => m.cashSessionId.equals(session.id))).watch(),
                  builder: (context, m) => Card(
                    child: Column(
                      children: (m.data ?? [])
                          .map(
                            (x) => ListTile(
                              title: Text(x.reason),
                              subtitle: Text(x.type),
                              trailing: Text(formatMoneyMinor(x.amountMinor)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<(CashRegister, CashSession?)> load(AppDatabase db) async {
    var register = await db.select(db.cashRegisters).getSingleOrNull();
    if (register == null) {
      final company = await db.select(db.companies).getSingle(),
          warehouse = await db.select(db.warehouses).getSingle(),
          now = DateTime.now().toUtc();
      await db
          .into(db.cashRegisters)
          .insert(
            CashRegistersCompanion.insert(
              id: const Uuid().v7(),
              companyId: company.id,
              warehouseId: warehouse.id,
              name: 'Caixa Principal',
              createdAt: now,
              updatedAt: now,
              deviceId: company.deviceId,
            ),
          );
      register = await db.select(db.cashRegisters).getSingle();
    }
    return (
      register,
      await (db.select(db.cashSessions)
            ..where((s) => s.cashRegisterId.equals(register!.id))
            ..where((s) => s.status.equals('open')))
          .getSingleOrNull(),
    );
  }

  Future<void> open(
    BuildContext context,
    AppDatabase db,
    CashRegister register,
  ) async {
    final input = TextEditingController(text: '0'),
        ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const LocalizedText('Abrir caixa'),
            content: TextField(
              controller: input,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Saldo inicial'.localized(context),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const LocalizedText('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const LocalizedText('Abrir'),
              ),
            ],
          ),
        );
    if (ok != true) return;
    final user = await currentSessionUser(db),
        company = await db.select(db.companies).getSingle();
    await CashSessionService(db).open(
      registerId: register.id,
      userId: user.id,
      deviceId: company.deviceId,
      openingMinor:
          ((double.tryParse(input.text.replaceAll(',', '.')) ?? 0) * 100)
              .round(),
    );
    if (context.mounted) (context as Element).markNeedsBuild();
  }

  Future<void> close(
    BuildContext context,
    AppDatabase db,
    CashSession session,
  ) async {
    final input = TextEditingController(),
        ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const LocalizedText('Fechar caixa'),
            content: TextField(
              controller: input,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Saldo contado'.localized(context),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const LocalizedText('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const LocalizedText('Fechar'),
              ),
            ],
          ),
        );
    if (ok != true) return;
    final user = await currentSessionUser(db),
        result = await CashSessionService(db).close(
          sessionId: session.id,
          userId: user.id,
          countedMinor:
              ((double.tryParse(input.text.replaceAll(',', '.')) ?? 0) * 100)
                  .round(),
        );
    if (!context.mounted) return;
    if (result case Success(:final value)) {
      await showAppAlert(
        context,
        'Caixa fechado. Diferença: ${formatMoneyMinor(value)}',
      );
      (context as Element).markNeedsBuild();
    } else if (result case Failure(:final error)) {
      showAppFailure(context, error);
    }
  }
}
