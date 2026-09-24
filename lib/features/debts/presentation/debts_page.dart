import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/core/utils/money.dart';
import 'package:systock/core/widgets/error_dialog.dart';
import 'package:systock/features/customers/application/debt_service.dart';
import 'package:systock/l10n/localized_text.dart';

class DebtsPage extends ConsumerStatefulWidget {
  const DebtsPage({super.key});

  @override
  ConsumerState<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends ConsumerState<DebtsPage> {
  bool showSettled = true;
  bool processing = false;
  String search = '';
  late Future<
    ({Company company, List<CustomerDebt> debts, DebtSummary summary})
  >
  data;

  @override
  void initState() {
    super.initState();
    data = _load();
  }

  Future<({Company company, List<CustomerDebt> debts, DebtSummary summary})>
  _load() async {
    final db = ref.read(databaseProvider);
    final company = await db.select(db.companies).getSingle();
    final service = DebtService(db);
    return (
      company: company,
      debts: await service.debts(company.id),
      summary: await service.summary(company.id),
    );
  }

  void _reload() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nextData = _load();
      setState(() {
        data = nextData;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Gestão de dívidas'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilterChip(
              label: const LocalizedText('Mostrar liquidadas'),
              selected: showSettled,
              onSelected: (value) => setState(() => showSettled = value),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: FutureBuilder(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          final normalized = search.trim().toLowerCase();
          final debts = result.debts.where((debt) {
            if (!showSettled && debt.balanceMinor <= 0) return false;
            if (normalized.isEmpty) return true;
            return debt.customerName.toLowerCase().contains(normalized) ||
                debt.documentNumber.toLowerCase().contains(normalized) ||
                debt.status.toLowerCase().contains(normalized);
          }).toList();
          final currency = result.company.currencyCode == 'MZN'
              ? 'MT'
              : result.company.currencyCode;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Pesquisar cliente ou documento',
                ),
                onChanged: (value) => setState(() => search = value),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(
                    'Total em dívida',
                    result.summary.originalMinor,
                    currency,
                  ),
                  _Metric(
                    'Valor liquidado',
                    result.summary.paidMinor,
                    currency,
                  ),
                  _Metric(
                    'Saldo a receber',
                    result.summary.outstandingMinor,
                    currency,
                  ),
                  _MetricCount(
                    'Dívidas não liquidadas',
                    result.summary.openCount,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (debts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: LocalizedText('Sem dívidas registadas.'),
                    ),
                  ),
                )
              else
                for (final debt in debts)
                  _DebtCard(
                    debt: debt,
                    currency: currency,
                    processing: processing,
                    onRemove: () => _removeDebt(DebtService(db), debt),
                    onPay: () => _recordPayment(
                      DebtService(db),
                      debt,
                      result.company.deviceId,
                      currency,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeDebt(DebtService service, CustomerDebt debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Remover dívida liquidada?'),
        content: LocalizedText(
          'A dívida de ${debt.customerName} deixará de aparecer nesta gestão. A venda continuará preservada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const LocalizedText('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await service.removeSettled(debt);
    if (!mounted) return;
    if (result case Failure(:final error)) {
      await showAppFailure(context, error);
    } else {
      _reload();
      await showAppAlert(context, 'Dívida liquidada removida.');
    }
  }

  Future<void> _recordPayment(
    DebtService service,
    CustomerDebt debt,
    String deviceId,
    String currency,
  ) async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Liquidar dívida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(debt.customerName),
            const SizedBox(height: 6),
            Text(
              'Saldo: ${formatMoneyMinor(debt.balanceMinor, symbol: currency)}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Valor recebido'),
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
                Navigator.pop(dialog, parseMoneyMinor(controller.text));
              } on FormatException {
                return;
              }
            },
            child: const LocalizedText('Registrar pagamento'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    if (processing) return;
    setState(() => processing = true);
    try {
      final result = await service.recordPayment(
        debt: debt,
        amountMinor: amount,
        deviceId: deviceId,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (result case Failure(:final error)) {
        await showAppFailure(context, error);
      } else {
        await showAppAlert(context, 'Pagamento registrado.');
        _reload();
      }
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => processing = false);
        });
      }
    }
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.debt,
    required this.currency,
    required this.processing,
    required this.onRemove,
    required this.onPay,
  });

  final CustomerDebt debt;
  final String currency;
  final bool processing;
  final VoidCallback onRemove, onPay;

  @override
  Widget build(BuildContext context) {
    final todayValue = DateTime.now();
    final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
    final dueAt = debt.dueAt;
    final dueDate = dueAt == null
        ? null
        : DateTime(dueAt.year, dueAt.month, dueAt.day);
    final daysRemaining = dueDate?.difference(today).inDays;
    final open = debt.balanceMinor > 0;
    final overdue = open && daysRemaining != null && daysRemaining < 0;
    final dueSoon =
        open &&
        daysRemaining != null &&
        daysRemaining >= 0 &&
        daysRemaining <= 3;
    final scheme = Theme.of(context).colorScheme;
    const settledColor = Color(0xFF159F68);
    final background = !open
        ? Color.alphaBlend(settledColor.withValues(alpha: .12), scheme.surface)
        : overdue
        ? Color.alphaBlend(scheme.error.withValues(alpha: .11), scheme.surface)
        : dueSoon
        ? Color.alphaBlend(
            const Color(0xFFF6B800).withValues(alpha: .14),
            scheme.surface,
          )
        : null;
    final border = !open
        ? settledColor.withValues(alpha: .78)
        : overdue
        ? scheme.error.withValues(alpha: .75)
        : dueSoon
        ? const Color(0xFFD69E00)
        : null;
    final dueText = dueDate == null
        ? 'Vencimento não informado'
        : 'Vencimento: ${_DebtsPageState._date(dueDate)}';
    final urgency = overdue
        ? 'Vencida há ${daysRemaining.abs()} ${daysRemaining.abs() == 1 ? 'dia' : 'dias'}'
        : dueSoon
        ? daysRemaining == 0
              ? 'Vence hoje'
              : 'Vence em $daysRemaining ${daysRemaining == 1 ? 'dia' : 'dias'}'
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: border == null
              ? BorderSide.none
              : BorderSide(color: border, width: 1.5),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          leading: Icon(
            overdue
                ? Icons.error_outline
                : dueSoon
                ? Icons.warning_amber_rounded
                : open
                ? Icons.account_balance_wallet_outlined
                : Icons.check_circle_outline,
            color: !open ? settledColor : border,
          ),
          title: Text(debt.customerName),
          subtitle: Text(
            '${debt.documentNumber} · ${_DebtsPageState._date(debt.createdAt)}\n$dueText${urgency == null ? '' : ' · $urgency'}\n${debt.status}',
          ),
          isThreeLine: true,
          trailing: !open
              ? IconButton(
                  tooltip: 'Remover dívida liquidada',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoneyMinor(debt.balanceMinor, symbol: currency),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'de ${formatMoneyMinor(debt.originalMinor, symbol: currency)}',
                    ),
                  ],
                ),
          onTap: !open || processing ? null : onPay,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.currency);
  final String label, currency;
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(label),
            const SizedBox(height: 8),
            Text(
              formatMoneyMinor(value, symbol: currency),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MetricCount extends StatelessWidget {
  const _MetricCount(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(label),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}
