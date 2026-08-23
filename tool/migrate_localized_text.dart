import 'dart:io';

void main() {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/l10n/generated/') ||
        entity.path.endsWith('localized_text.dart')) {
      continue;
    }
    final source = entity.readAsStringSync();
    var updated = source.replaceAllMapped(
      RegExp(r'''(?<![\w.])Text\(\s*(?=['"])'''),
      (_) => 'LocalizedText(',
    );
    updated = updated.replaceAllMapped(
      RegExp(
        r'''(labelText|hintText|helperText|tooltip):\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")''',
      ),
      (match) => '${match[1]}: ${match[2]}.localized(context)',
    );
    updated = updated.replaceAll('const InputDecoration(', 'InputDecoration(');
    if (updated == source) continue;
    const localizationImport =
        "import 'package:systock/l10n/localized_text.dart';";
    if (!updated.contains(localizationImport)) {
      const materialImport = "import 'package:flutter/material.dart';";
      if (updated.contains(materialImport)) {
        updated = updated.replaceFirst(
          materialImport,
          '$materialImport\n$localizationImport',
        );
      } else {
        final firstImportEnd = updated.indexOf(';', updated.indexOf('import '));
        updated = updated.replaceRange(
          firstImportEnd + 1,
          firstImportEnd + 1,
          '\n$localizationImport',
        );
      }
    }
    entity.writeAsStringSync(updated);
  }
}
