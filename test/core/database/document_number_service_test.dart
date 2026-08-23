import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/document_number_service.dart';

void main() {
  test('reserves unique sequential document numbers offline', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026);
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: 'c1',
            tradeName: 'Loja',
            createdAt: now,
            updatedAt: now,
            deviceId: 'device-a',
          ),
        );
    final service = DocumentNumberService(db);
    final values = <String>[];
    for (var index = 0; index < 20; index++) {
      values.add(
        await service.next(
          companyId: 'c1',
          type: 'sale',
          prefix: 'VEN',
          deviceId: 'device-a',
          at: now,
        ),
      );
    }
    expect(values.toSet(), hasLength(20));
    expect(values.first, 'VEN-2026-000001-DEVI');
    expect(values.last, 'VEN-2026-000020-DEVI');
  });
}
