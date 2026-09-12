import 'dart:convert';
import 'package:systock/core/utils/quantity.dart';
import 'dart:typed_data';
import 'package:systock/core/printing/receipt.dart';
import 'package:systock/core/utils/money.dart';

String _money(int minor) => formatMoneyMinor(minor);

class EscPosEncoder {
  const EscPosEncoder({this.charactersPerLine = 42});
  final int charactersPerLine;
  Uint8List encode(Receipt r) {
    final out = <int>[
      0x1b,
      0x40,
      0x1b,
      0x61,
      1,
      ...latin1.encode('${r.company}\n'),
      0x1b,
      0x61,
      0,
    ];
    void line(String left, String right) {
      final room = charactersPerLine - right.length;
      final clipped = left.length > room ? left.substring(0, room) : left;
      out.addAll(latin1.encode('${clipped.padRight(room)}$right\n'));
    }

    out.addAll(latin1.encode('${'-' * charactersPerLine}\n'));
    for (final item in r.lines) {
      line(item.description, _money(item.totalMinor));
      line(
        '${formatQuantity(item.quantityMilli)} x ${_money(item.unitPriceMinor)}',
        '',
      );
    }
    out.addAll(latin1.encode('${'-' * charactersPerLine}\n'));
    line('TOTAL', _money(r.totalMinor));
    out.addAll(latin1.encode('\n${r.documentNumber}\n\n\n'));
    out.addAll([0x1d, 0x56, 1]);
    return Uint8List.fromList(out);
  }
}
