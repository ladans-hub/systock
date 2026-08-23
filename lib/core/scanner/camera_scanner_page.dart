import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScannerPage extends StatefulWidget {
  const CameraScannerPage({super.key});
  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage> {
  bool _handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Digitalizar produto')),
    body: MobileScanner(
      onDetect: (capture) {
        if (_handled) return;
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (value == null || value.isEmpty) return;
        _handled = true;
        Navigator.of(context).pop(value);
      },
    ),
  );
}
