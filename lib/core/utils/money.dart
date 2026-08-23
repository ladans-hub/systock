import 'package:intl/intl.dart';

/// Converts localized decimal text to minor units without binary floating point.
int parseMoneyMinor(String input, {int fractionDigits = 2}) {
  var value = input.trim().replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (value.isEmpty) throw const FormatException('empty amount');
  final negative = value.startsWith('-');
  value = value.replaceAll('-', '');
  final comma = value.lastIndexOf(','), dot = value.lastIndexOf('.');
  final separator = comma > dot ? comma : dot;
  final wholeRaw = separator < 0 ? value : value.substring(0, separator);
  final fractionRaw = separator < 0 ? '' : value.substring(separator + 1);
  final whole = int.parse(
    wholeRaw.replaceAll(RegExp(r'[^0-9]'), '').isEmpty
        ? '0'
        : wholeRaw.replaceAll(RegExp(r'[^0-9]'), ''),
  );
  final normalizedFraction = fractionRaw.replaceAll(RegExp(r'[^0-9]'), '');
  final fraction = int.parse(
    (normalizedFraction + ('0' * fractionDigits)).substring(0, fractionDigits),
  );
  final factor = _pow10(fractionDigits);
  return (whole * factor + fraction) * (negative ? -1 : 1);
}

String formatMoneyMinor(
  int minor, {
  String locale = 'pt_MZ',
  String symbol = 'MT',
}) {
  if (locale.startsWith('pt')) {
    final negative = minor < 0;
    final absolute = minor.abs();
    final whole = (absolute ~/ 100).toString();
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$grouped,$fraction $symbol';
  }
  return NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 2,
  ).format(minor / 100);
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
