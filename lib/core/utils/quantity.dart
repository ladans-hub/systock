import 'package:systock/core/database/app_database.dart';

/// Existing installations seeded KG and L without decimalPlaces.
int quantityPrecision(Unit? unit) {
  if (unit == null) return 0;
  if (const {'KG', 'L'}.contains(unit.code.toUpperCase())) return 3;
  return unit.decimalPlaces.clamp(0, 3);
}

int parseQuantityMilli(String input, {int decimalPlaces = 3}) {
  final value = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Quantidade inválida.');
  }
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimalPlaces) {
    throw FormatException(
      decimalPlaces == 0
          ? 'Esta unidade aceita apenas quantidades inteiras.'
          : 'Informe até $decimalPlaces casas decimais.',
    );
  }
  return int.parse(parts[0]) * 1000 + int.parse(fraction.padRight(3, '0'));
}

String formatQuantity(int milli) {
  final sign = milli < 0 ? '-' : '';
  final absolute = milli.abs();
  final fraction = (absolute % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$sign${absolute ~/ 1000}${fraction.isEmpty ? '' : ',$fraction'}';
}
