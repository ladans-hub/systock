import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado apenas em memória. Terminar sessão nunca remove os dados locais.
final sessionLockedProvider = StateProvider<bool>((ref) => false);
