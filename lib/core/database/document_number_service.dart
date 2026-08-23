import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';

class DocumentNumberService {
  const DocumentNumberService(this._db);
  final AppDatabase _db;

  Future<String> next({
    required String companyId,
    required String type,
    required String prefix,
    required String deviceId,
    DateTime? at,
  }) => _db.transaction(
    () => _next(
      companyId: companyId,
      type: type,
      prefix: prefix,
      deviceId: deviceId,
      at: at,
    ),
  );

  Future<String> _next({
    required String companyId,
    required String type,
    required String prefix,
    required String deviceId,
    DateTime? at,
  }) async {
    final year = (at ?? DateTime.now().toUtc()).year;
    final current =
        await (_db.select(_db.documentSequences)..where(
              (s) =>
                  s.companyId.equals(companyId) &
                  s.documentType.equals(type) &
                  s.year.equals(year),
            ))
            .getSingleOrNull();
    final value = current?.nextValue ?? 1;
    if (current == null) {
      await _db
          .into(_db.documentSequences)
          .insert(
            DocumentSequencesCompanion.insert(
              companyId: companyId,
              documentType: type,
              year: year,
              nextValue: const Value(2),
            ),
          );
    } else {
      await (_db.update(_db.documentSequences)..where(
            (s) =>
                s.companyId.equals(companyId) &
                s.documentType.equals(type) &
                s.year.equals(year),
          ))
          .write(DocumentSequencesCompanion(nextValue: Value(value + 1)));
    }
    final normalizedDevice = '${deviceId.replaceAll('-', '')}0000';
    final deviceSuffix = normalizedDevice.substring(0, 4).toUpperCase();
    return '$prefix-$year-${value.toString().padLeft(6, '0')}-$deviceSuffix';
  }
}
