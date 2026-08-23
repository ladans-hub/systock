import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('Database provider requires a bootstrap override'),
);
