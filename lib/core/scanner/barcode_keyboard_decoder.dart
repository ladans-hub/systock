class BarcodeKeyboardDecoder {
  BarcodeKeyboardDecoder({
    this.maxGap = const Duration(milliseconds: 80),
    this.minimumLength = 4,
  });
  final Duration maxGap;
  final int minimumLength;
  final _buffer = StringBuffer();
  DateTime? _last;
  String? add(String character, DateTime timestamp) {
    if (_last != null && timestamp.difference(_last!) > maxGap) _buffer.clear();
    _last = timestamp;
    if (character == '\n' || character == '\r') {
      final value = _buffer.toString();
      _buffer.clear();
      _last = null;
      return value.length >= minimumLength ? value : null;
    }
    if (character.length == 1) _buffer.write(character);
    return null;
  }

  void reset() {
    _buffer.clear();
    _last = null;
  }
}
