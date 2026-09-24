import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

pw.Widget pdfWatermark(Uint8List bytes) => pw.FullPage(
  ignoreMargins: true,
  child: pw.Center(
    child: pw.Opacity(
      opacity: .055,
      child: pw.Image(
        pw.MemoryImage(bytes),
        width: 260,
        height: 260,
        fit: pw.BoxFit.contain,
      ),
    ),
  ),
);

pw.Widget pdfPageBackground(Uint8List bytes) => pdfWatermark(bytes);
