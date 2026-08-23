import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final appLocaleProvider = StateProvider<Locale>((ref) => const Locale('pt'));
