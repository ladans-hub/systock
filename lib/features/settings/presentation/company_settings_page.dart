import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';

class CompanySettingsPage extends ConsumerStatefulWidget {
  const CompanySettingsPage({super.key});
  @override
  ConsumerState<CompanySettingsPage> createState() =>
      _CompanySettingsPageState();
}

class _CompanySettingsPageState extends ConsumerState<CompanySettingsPage> {
  final trade = TextEditingController(),
      legal = TextEditingController(),
      tax = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      address = TextEditingController(),
      footer = TextEditingController();
  final subtitle = TextEditingController(text: 'Gestão de Stock');
  String currency = 'MZN', timezone = 'Africa/Maputo';
  String? logoPath;
  bool loaded = false, saving = false;

  void load(Company company) {
    if (loaded) return;
    loaded = true;
    trade.text = company.tradeName;
    legal.text = company.legalName ?? '';
    tax.text = company.taxId ?? '';
    phone.text = company.phone ?? '';
    email.text = company.email ?? '';
    address.text = company.address ?? '';
    footer.text = company.receiptFooter ?? '';
    currency = company.currencyCode;
    logoPath = company.logoPath;
    timezone = company.timezone;
  }

  String? optional(String value) => value.trim().isEmpty ? null : value.trim();

  Future<void> _loadBranding(AppDatabase db) async {
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('branding.subtitle'))).getSingleOrNull();
    if (setting != null && mounted) subtitle.text = setting.valueJson;
  }

  Future<void> _pickLogo() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked?.path == null) return;
    final source = File(picked!.path!);
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory('${docs.path}/company_branding');
    await directory.create(recursive: true);
    final extension = source.path.split('.').last.toLowerCase();
    final destination = '${directory.path}/logo.$extension';
    await source.copy(destination);
    if (mounted) setState(() => logoPath = destination);
  }

  Future<void> save(AppDatabase db, Company company) async {
    if (trade.text.trim().isEmpty) return;
    setState(() => saving = true);
    await (db.update(
      db.companies,
    )..where((c) => c.id.equals(company.id))).write(
      CompaniesCompanion(
        tradeName: Value(trade.text.trim()),
        legalName: Value(optional(legal.text)),
        taxId: Value(optional(tax.text)),
        phone: Value(optional(phone.text)),
        email: Value(optional(email.text)),
        address: Value(optional(address.text)),
        receiptFooter: Value(optional(footer.text)),
        logoPath: Value(logoPath),
        currencyCode: Value(currency),
        timezone: Value(timezone),
        updatedAt: Value(DateTime.now().toUtc()),
        version: Value(company.version + 1),
      ),
    );
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'branding.subtitle',
            valueJson: subtitle.text.trim().isEmpty
                ? 'Gestão de Stock'
                : subtitle.text.trim(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    if (!mounted) return;
    setState(() => saving = false);
    await showAppAlert(context, 'Dados da empresa atualizados.');
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const AppBarTitle('Empresa'),
      ),
      body: FutureBuilder<Company>(
        future: db.select(db.companies).getSingle(),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final company = snapshot.data!;
          load(company);
          if (loaded && subtitle.text == 'Gestão de Stock') {
            _loadBranding(db);
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _pickLogo,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: logoPath == null
                              ? const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 38,
                                )
                              : Image.file(
                                  File(logoPath!),
                                  fit: BoxFit.contain,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const LocalizedText('Logotipo da empresa'),
                      const SizedBox(height: 20),
                      TextField(
                        controller: trade,
                        decoration: InputDecoration(
                          labelText: 'Nome comercial *'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: subtitle,
                        decoration: InputDecoration(
                          labelText: 'Subtítulo da aplicação'.localized(
                            context,
                          ),
                          hintText: 'Gestão de Stock'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: legal,
                        decoration: InputDecoration(
                          labelText: 'Razão social'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tax,
                        decoration: InputDecoration(
                          labelText: 'NUIT / NIF'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phone,
                        decoration: InputDecoration(
                          labelText: 'Telefone'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        decoration: InputDecoration(
                          labelText: 'Email'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: address,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Endereço'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: footer,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Rodapé dos recibos'.localized(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField(
                              initialValue: currency,
                              decoration: InputDecoration(
                                labelText: 'Moeda'.localized(context),
                              ),
                              items: const ['MZN', 'USD', 'EUR', 'ZAR']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => currency = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: saving ? null : () => save(db, company),
                          icon: const Icon(Icons.save),
                          label: Text(saving ? 'Salvando…' : 'Salvar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
