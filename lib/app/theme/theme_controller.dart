import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AppPalette {
  const AppPalette({required this.primary, required this.secondary});

  static const defaults = AppPalette(
    primary: Color(0xFF2F6BFF),
    secondary: Color(0xFF1AC6D9),
  );

  final Color primary;
  final Color secondary;

  AppPalette copyWith({Color? primary, Color? secondary}) => AppPalette(
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
  );

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(primary, secondary);
}

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final appLocaleProvider = StateProvider<Locale>((ref) => const Locale('pt'));
final appPaletteProvider = StateProvider<AppPalette>(
  (ref) => AppPalette.defaults,
);
