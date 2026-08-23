import 'dart:convert';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';

class BusinessRulesPage extends ConsumerStatefulWidget {
  const BusinessRulesPage({super.key});
  @override
  ConsumerState<BusinessRulesPage> createState() => _BusinessRulesPageState();
}

class _BusinessRulesPageState extends ConsumerState<BusinessRulesPage> {
  String negativeStock = 'no';
  Future<void> saveSetting() async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'inventory.negative_stock',
            valueJson: jsonEncode({'policy': negativeStock}),
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> addTax(AppDatabase db) async {
    final name = TextEditingController(), rate = TextEditingController();
    var included = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Nova taxa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: 'Nome'.localized(context),
                ),
              ),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Percentual'.localized(context),
                ),
              ),
              SwitchListTile(
                title: const LocalizedText('Preço inclui imposto'),
                value: included,
                onChanged: (v) => setState(() => included = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('Adicionar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final company = await db.select(db.companies).getSingle(),
        now = DateTime.now().toUtc();
    final basisPoints = ((int.tryParse(rate.text) ?? 0) * 100);
    await db
        .into(db.taxRates)
        .insert(
          TaxRatesCompanion.insert(
            id: const Uuid().v7(),
            companyId: company.id,
            name: name.text.trim(),
            rateBasisPoints: basisPoints,
            priceIncludesTax: Value(included),
            createdAt: now,
            updatedAt: now,
            deviceId: company.deviceId,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Stock, preços e impostos'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    'Stock negativo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  RadioGroup<String>(
                    groupValue: negativeStock,
                    onChanged: (v) {
                      setState(() => negativeStock = v!);
                      saveSetting();
                    },
                    child: const Column(
                      children: [
                        RadioListTile(
                          value: 'no',
                          title: LocalizedText('Não permitir'),
                        ),
                        RadioListTile(
                          value: 'yes',
                          title: LocalizedText('Permitir'),
                        ),
                        RadioListTile(
                          value: 'admin',
                          title: LocalizedText('Apenas administradores'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              LocalizedText(
                'Impostos configuráveis',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => addTax(db),
                icon: const Icon(Icons.add),
                label: const LocalizedText('Taxa'),
              ),
            ],
          ),
          StreamBuilder<List<TaxRate>>(
            stream: db.select(db.taxRates).watch(),
            builder: (_, snapshot) => Card(
              child: Column(
                children: [
                  for (final tax in snapshot.data ?? const [])
                    ListTile(
                      title: Text(tax.name),
                      subtitle: LocalizedText('${tax.rateBasisPoints / 100}%'),
                      trailing: Chip(
                        label: Text(
                          tax.priceIncludesTax ? 'Incluído' : 'Excluído',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
