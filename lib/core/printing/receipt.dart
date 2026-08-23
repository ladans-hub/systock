class ReceiptLine {
  const ReceiptLine({
    required this.description,
    required this.quantityMilli,
    required this.unitPriceMinor,
    required this.totalMinor,
  });
  final String description;
  final int quantityMilli, unitPriceMinor, totalMinor;
}

class Receipt {
  const Receipt({
    required this.company,
    required this.documentNumber,
    required this.issuedAt,
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.payments,
    this.taxId,
    this.address,
    this.footer,
  });
  final String company, documentNumber;
  final DateTime issuedAt;
  final List<ReceiptLine> lines;
  final int subtotalMinor, discountMinor, totalMinor;
  final Map<String, int> payments;
  final String? taxId, address, footer;
}

sealed class PrintResult {
  const PrintResult();
}

class PrintSuccess extends PrintResult {
  const PrintSuccess();
}

class PrintFailure extends PrintResult {
  const PrintFailure(this.message, [this.cause]);
  final String message;
  final Object? cause;
}

abstract interface class ReceiptPrinter {
  Future<PrintResult> print(Receipt receipt);
}
