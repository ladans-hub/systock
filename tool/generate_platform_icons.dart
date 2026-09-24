import 'dart:io';

import 'package:image/image.dart' as image;

const _sourcePath = 'assets/branding/systock_logo_transparent.png';

void main() {
  final source = image.decodePng(File(_sourcePath).readAsBytesSync());
  if (source == null) {
    throw StateError('Não foi possível ler o ícone principal.');
  }

  _writePng(source, 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48);
  _writePng(source, 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72);
  _writePng(
    source,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
    96,
  );
  _writePng(
    source,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
    144,
  );
  _writePng(
    source,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    192,
  );

  final iosIcons = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  for (final entry in iosIcons.entries) {
    _writePng(
      source,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
      entry.value,
      flatten: true,
    );
  }

  for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
    _writePng(
      source,
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
      size,
      flatten: true,
    );
  }

  final windowsIcon = image.copyResize(
    source,
    width: 256,
    height: 256,
    interpolation: image.Interpolation.cubic,
  );
  File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true)
    ..writeAsBytesSync(image.encodeIco(windowsIcon));
}

void _writePng(
  image.Image source,
  String path,
  int size, {
  bool flatten = false,
}) {
  final resized = image.copyResize(
    source,
    width: size,
    height: size,
    interpolation: image.Interpolation.cubic,
  );
  final output = flatten
      ? image.compositeImage(
          image.Image(width: size, height: size)
            ..clear(image.ColorRgb8(0, 0, 0)),
          resized,
        )
      : resized;
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(image.encodePng(output));
}
