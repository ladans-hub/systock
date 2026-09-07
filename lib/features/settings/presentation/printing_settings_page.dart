import 'package:systock/core/widgets/error_dialog.dart';
import 'dart:convert';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/printing/esc_pos_printer.dart';
import 'package:systock/core/printing/pdf_receipt_printer.dart';
import 'package:systock/core/printing/receipt.dart';

class PrintingSettingsPage extends ConsumerStatefulWidget {
  const PrintingSettingsPage({super.key});
  @override
  ConsumerState<PrintingSettingsPage> createState() =>
      _PrintingSettingsPageState();
}

class _PrintingSettingsPageState extends ConsumerState<PrintingSettingsPage> {
  String type = 'system', width = '80';
  final host = TextEditingController(),
      port = TextEditingController(text: '9100');
  bool busy = false;

  Future<void> save() async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'printing.receipts',
            valueJson: jsonEncode({
              'type': type,
              'width': width,
              'host': host.text.trim(),
              'port': int.tryParse(port.text) ?? 9100,
            }),
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Perfil de impressão salvo.')),
      );
    }
  }

  Future<void> test() async {
    setState(() => busy = true);
    final receipt = Receipt(
      company: 'SYSTOCK',
      documentNumber: 'TESTE-001',
      issuedAt: DateTime.now(),
      lines: const [
        ReceiptLine(
          description: 'Página de teste',
          quantityMilli: 1000,
          unitPriceMinor: 10000,
          totalMinor: 10000,
        ),
      ],
      subtotalMinor: 10000,
      discountMinor: 0,
      totalMinor: 10000,
      payments: const {'Dinheiro': 10000},
      footer: 'Impressora configurada com sucesso.',
    );
    final ReceiptPrinter printer = type == 'network'
        ? EscPosReceiptPrinter(
            NetworkPrinterTransport(
              host.text.trim(),
              port: int.tryParse(port.text) ?? 9100,
            ),
          )
        : SystemReceiptPrinter();
    final result = await printer.print(receipt);
    if (!mounted) return;
    setState(() => busy = false);
    if (result is PrintFailure) {
      await showAppError(context, result.message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result is PrintSuccess
              ? 'Página de teste enviada.'
              : (result as PrintFailure).message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AdaptiveBackButton(),
      title: const LocalizedText('Impressão e recibos'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                DropdownButtonFormField(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: 'Impressora de recibos'.localized(context),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'system',
                      child: LocalizedText('Sistema / AirPrint / PDF'),
                    ),
                    DropdownMenuItem(
                      value: 'network',
                      child: LocalizedText('Térmica ESC/POS por rede'),
                    ),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: width,
                  decoration: InputDecoration(
                    labelText: 'Largura térmica'.localized(context),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '58',
                      child: LocalizedText('58 mm'),
                    ),
                    DropdownMenuItem(
                      value: '80',
                      child: LocalizedText('80 mm'),
                    ),
                  ],
                  onChanged: (v) => setState(() => width = v!),
                ),
                if (type == 'network') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: host,
                          decoration: InputDecoration(
                            labelText: 'IP / host'.localized(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Porta'.localized(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: save,
                      icon: const Icon(Icons.save),
                      label: const LocalizedText('Salvar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : test,
                      icon: const Icon(Icons.print),
                      label: Text(
                        busy ? 'Enviando…' : 'Imprimir página de teste',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const LocalizedText(
                  'Bluetooth e USB usam o mesmo adaptador ESC/POS e são disponibilizados quando o driver da plataforma expõe o canal.',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
