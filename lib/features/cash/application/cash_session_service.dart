import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/errors/result.dart';
import 'package:uuid/uuid.dart';

class CashSessionService {
  CashSessionService(this._db) : _uuid = const Uuid();
  final AppDatabase _db;
  final Uuid _uuid;
  Future<Result<String>> open({
    required String registerId,
    required String userId,
    required String deviceId,
    required int openingMinor,
  }) async {
    if (openingMinor < 0) {
      return const Failure(
        ValidationFailure('O saldo inicial não pode ser negativo.'),
      );
    }
    try {
      final existing =
          await (_db.select(_db.cashSessions)..where(
                (s) =>
                    s.cashRegisterId.equals(registerId) &
                    s.status.equals('open'),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return const Failure(
          ValidationFailure('Este caixa já possui um turno aberto.'),
        );
      }
      final now = DateTime.now().toUtc(), id = _uuid.v7();
      await _db
          .into(_db.cashSessions)
          .insert(
            CashSessionsCompanion.insert(
              id: id,
              cashRegisterId: registerId,
              openedBy: userId,
              openingMinor: openingMinor,
              createdAt: now,
              updatedAt: now,
              deviceId: deviceId,
            ),
          );
      return Success(id);
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível abrir o caixa.', cause: error),
      );
    }
  }

  Future<Result<int>> close({
    required String sessionId,
    required String userId,
    required int countedMinor,
  }) async {
    try {
      return await _db.transaction(() async {
        final session =
            await (_db.select(_db.cashSessions)..where(
                  (s) => s.id.equals(sessionId) & s.status.equals('open'),
                ))
                .getSingle();
        final movements = await (_db.select(
          _db.cashMovements,
        )..where((m) => m.cashSessionId.equals(sessionId))).get();
        final expected =
            session.openingMinor +
            movements.fold<int>(0, (sum, m) => sum + m.amountMinor);
        await (_db.update(
          _db.cashSessions,
        )..where((s) => s.id.equals(sessionId))).write(
          CashSessionsCompanion(
            status: const Value('closed'),
            closedBy: Value(userId),
            expectedMinor: Value(expected),
            countedMinor: Value(countedMinor),
            closedAt: Value(DateTime.now().toUtc()),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
        return Success(countedMinor - expected);
      });
    } catch (error) {
      return Failure(
        StorageFailure('Não foi possível fechar o caixa.', cause: error),
      );
    }
  }
}
