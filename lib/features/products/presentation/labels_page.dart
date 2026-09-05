import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/printing/label_pdf.dart';

class LabelsPage extends ConsumerStatefulWidget {
  const LabelsPage({super.key});
  @override
  ConsumerState<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends ConsumerState<LabelsPage> {
  String? productId;
  final copies = TextEditingController(text: '1');
  double width = 50, height = 30;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Etiquetas de produtos'),
      ),
      body: FutureBuilder(
        future: db.select(db.products).get(),
        builder: (context, snapshot) {
          final products = snapshot.data ?? const [];
          if (products.isEmpty) {
            return const Center(
              child: LocalizedText(
                'Cadastre produtos antes de criar etiquetas.',
              ),
            );
          }
          productId ??= products.first.id;
          final product = products.firstWhere((p) => p.id == productId);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: productId,
                        decoration: InputDecoration(
                          labelText: 'Produto'.localized(context),
                        ),
                        items: [
                          for (final p in products)
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => setState(() => productId = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: copies,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Cópias'.localized(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  '${width.toInt()}x${height.toInt()}',
                              decoration: InputDecoration(
                                labelText: 'Tamanho'.localized(context),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: '50x30',
                                  child: LocalizedText('50 × 30 mm'),
                                ),
                                DropdownMenuItem(
                                  value: '40x25',
                                  child: LocalizedText('40 × 25 mm'),
                                ),
                                DropdownMenuItem(
                                  value: '60x40',
                                  child: LocalizedText('60 × 40 mm'),
                                ),
                              ],
                              onChanged: (v) {
                                final size = v!.split('x');
                                setState(() {
                                  width = double.parse(size[0]);
                                  height = double.parse(size[1]);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _print(product.id),
                        icon: const Icon(Icons.print),
                        label: const LocalizedText('Pré-visualizar e imprimir'),
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

  Future<void> _print(String id) async {
    final db = ref.read(databaseProvider);
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingle();
    final barcode =
        await (db.select(db.productBarcodes)
              ..where((b) => b.productId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (!mounted) return;
    if (barcode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Este produto não possui código de barras.'),
        ),
      );
      return;
    }
    final bytes = await buildProductLabels(
      name: product.name,
      barcode: barcode.barcode,
      priceMinor: product.saleMinor,
      copies: int.tryParse(copies.text) ?? 1,
      widthMm: width,
      heightMm: height,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'etiquetas-${barcode.barcode}',
    );
  }
}
