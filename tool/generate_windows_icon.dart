import 'dart:io';

import 'package:image/image.dart' as image;

void main() {
  final source = image.decodePng(
    File('assets/branding/systock_logo_transparent.png').readAsBytesSync(),
  );
  if (source == null) {
    throw StateError('Não foi possível ler o ícone principal.');
  }

  final icon = image.copyResize(
    source,
    width: 256,
    height: 256,
    interpolation: image.Interpolation.cubic,
  );
  File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true)
    ..writeAsBytesSync(image.encodeIco(icon));
}
