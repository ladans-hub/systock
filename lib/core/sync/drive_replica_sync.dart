import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import 'drive_vault_store.dart';
import 'vault_cipher.dart';

/// Immutable encrypted change batches, with durable local baselines and outbox.
/// Runs under VaultLock, shared with connect/disconnect and the automatic timer.
class DriveReplicaSync {
  DriveReplicaSync(
    this.db,
    this.store, {
    required this.companyId,
    required this.deviceId,
    required this.key,
    required this.documents,
  });

  final AppDatabase db;
  final DriveVaultStore store;
  final String companyId, deviceId, key;
  final Directory documents;
  static const _prefix = 'sync.replica.';
  static const _excluded = {
    'inventory_balances',
    'document_sequences',
    'sync_operations',
    'applied_operations',
    'sync_states',
    'sync_conflicts',
    'backups',
    'app_settings',
    'devices',
    'notifications',
  };
  late final Map<String, TableInfo> _tables = {
    for (final table in db.allTables)
      if (!_excluded.contains(table.actualTableName))
        table.actualTableName: table,
  };

  String get _remotePrefix => 'systock-v3-changes-$companyId-';

  /// Publishes an existing validated backup into the common change history.
  Future<int> publishInitial() async {
    await db.transaction(_capture);
    return _upload();
  }

  Future<({int uploaded, int received, int conflicts})> synchronize() async {
    final companies = await db.select(db.companies).get();
    if (companies.length > 1 ||
        (companies.isNotEmpty && companies.single.id != companyId)) {
      throw StateError('A loja local não corresponde à loja do Google Drive.');
    }
    await db.transaction(_capture);
    var uploaded = await _upload();
    final files = await store.list(_remotePrefix);
    files.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time != 0 ? time : a.name.compareTo(b.name);
    });
    final packets = <Map<String, dynamic>>[];
    for (final file in files) {
      if (await _setting('${_prefix}seen.${file.name}') != null) continue;
      final clear = await VaultCipher.decrypt(
        await store.read(file.id),
        key,
        companyId,
      );
      final packet =
          jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, dynamic>;
      if (packet['schema'] != db.schemaVersion ||
          packet['protocol'] != 3 ||
          packet['companyId'] != companyId ||
          file.name != '$_remotePrefix${packet['id']}.bin') {
        throw StateError(
          'Atualize o Systock nos dois aparelhos para sincronizar esta loja.',
        );
      }
      _validate(packet);
      packets.add(packet);
    }
    var received = 0, conflicts = 0;
    if (packets.isNotEmpty) {
      await db.transaction(() async {
        // Capture edits made while the network was busy before applying remote data.
        await _capture();
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        final states = await _states();
        for (final packet in packets) {
          for (final raw in packet['changes'] as List) {
            final change = Map<String, dynamic>.from(raw as Map);
            final table = change['table'] as String;
            final rowKey = _rowKey(
              table,
              Map<String, dynamic>.from(change['pk'] as Map),
            );
            final local = states[table]![rowKey] as Map<String, dynamic>?;
            final comparison = local == null ? 1 : _compare(change, local);
            if (comparison <= 0) continue;
            final same = local != null && _equal(local['data'], change['data']);
            if (!same &&
                local != null &&
                local['source'] != change['source'] &&
                change['base'] != local['revision'] &&
                change['initial'] != true &&
                local['initial'] != true) {
              await db
                  .into(db.syncConflicts)
                  .insert(
                    SyncConflictsCompanion.insert(
                      id: '${change['revision']}-${local['revision']}',
                      entityType: table,
                      entityId: rowKey,
                      localPayloadJson: jsonEncode(local),
                      remotePayloadJson: jsonEncode(change),
                      createdAt: DateTime.now().toUtc(),
                    ),
                    mode: InsertMode.insertOrIgnore,
                  );
              conflicts++;
            }
            states[table]![rowKey] = change;
            if (!same) received++;
          }
        }
        // Write only final winners, as one transaction. Deferred foreign keys
        // allow parent/child batches from different devices in either order.
        for (final table in _tables.keys.toList().reversed) {
          for (final raw in states[table]!.values) {
            final state = raw as Map<String, dynamic>;
            if (state['data'] == null) await _deleteRow(table, state);
          }
        }
        for (final table in _tables.keys) {
          for (final raw in states[table]!.values) {
            final state = raw as Map<String, dynamic>;
            if (state['data'] != null) await _writeRow(table, state);
          }
          await _save('${_prefix}rows.$table', states[table]!);
        }
        await db.rebuildInventoryBalances();
        await db.customStatement('''
          UPDATE customers SET balance_minor = (
            SELECT COALESCE(SUM(amount_minor), 0) FROM customer_account_movements m
            WHERE m.customer_id = customers.id AND m.deleted_at IS NULL
          ) WHERE EXISTS (SELECT 1 FROM customer_account_movements m
                          WHERE m.customer_id = customers.id)
        ''');
        // Derived balances must not become new outbound edits on the next pass.
        await _refreshDerived(states);
        final violations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        if (violations.isNotEmpty) {
          throw StateError(
            'Faltam dados relacionados no Drive. A receção foi adiada; tente sincronizar novamente nos dois aparelhos.',
          );
        }
        for (final packet in packets) {
          await _save('${_prefix}seen.$_remotePrefix${packet['id']}.bin', {
            'ok': true,
          });
        }
      });
      db.markTablesUpdated(db.allTables.toSet());
    }
    // Includes any local work captured during the download.
    uploaded += await _upload();
    return (uploaded: uploaded, received: received, conflicts: conflicts);
  }

  Future<Map<String, Map<String, dynamic>>> _states() async => {
    for (final table in _tables.keys)
      table: await _setting('${_prefix}rows.$table') ?? <String, dynamic>{},
  };

  Future<void> _capture() async {
    final states = await _states();
    final changes = <Map<String, dynamic>>[];
    var clock = (await _setting('${_prefix}clock'))?['value'] as int? ?? 0;
    for (final tableStates in states.values) {
      for (final raw in tableStates.values) {
        clock = math.max(clock, (raw as Map)['clock'] as int);
      }
    }
    for (final table in _tables.keys) {
      final rows = await db.customSelect('SELECT * FROM "$table"').get();
      final currentKeys = <String>{};
      for (final row in rows) {
        final data = await _portable(table, row.data);
        final pk = _primaryKey(table, data);
        final rowKey = _rowKey(table, pk);
        currentKeys.add(rowKey);
        final previous = states[table]![rowKey] as Map<String, dynamic>?;
        if (previous != null && _equal(previous['data'], data)) continue;
        final initial = previous == null;
        final stamp = initial
            ? await _initialClock(table, data)
            : math.max(
                clock + 1,
                DateTime.now().toUtc().microsecondsSinceEpoch,
              );
        clock = math.max(clock, stamp);
        final change = <String, dynamic>{
          'table': table,
          'pk': pk,
          'data': data,
          'clock': stamp,
          'source': deviceId,
          'revision': const Uuid().v4(),
          'base': previous?['revision'],
          'initial': initial,
        };
        states[table]![rowKey] = change;
        changes.add(change);
      }
      for (final rowKey in states[table]!.keys.toList()) {
        final previous = states[table]![rowKey] as Map<String, dynamic>;
        if (currentKeys.contains(rowKey) || previous['data'] == null) continue;
        clock = math.max(
          clock + 1,
          DateTime.now().toUtc().microsecondsSinceEpoch,
        );
        final change = <String, dynamic>{
          ...previous,
          'data': null,
          'clock': clock,
          'source': deviceId,
          'revision': const Uuid().v4(),
          'base': previous['revision'],
          'initial': false,
        };
        states[table]![rowKey] = change;
        changes.add(change);
      }
      await _save('${_prefix}rows.$table', states[table]!);
    }
    if (changes.isEmpty) return;
    final id = const Uuid().v4();
    final legacy = await (db.select(
      db.syncOperations,
    )..where((o) => o.status.equals('pending'))).get();
    await _save('${_prefix}out.$id', {
      'id': id,
      'protocol': 3,
      'schema': db.schemaVersion,
      'companyId': companyId,
      'changes': changes,
      'legacy': legacy.map((o) => o.operationId).toList(),
    });
    await _save('${_prefix}clock', {'value': clock});
  }

  Future<int> _upload() async {
    var count = 0;
    final outbox = await (db.select(
      db.appSettings,
    )..where((s) => s.key.like('${_prefix}out.%'))).get();
    for (final row in outbox) {
      final packet = jsonDecode(row.valueJson) as Map<String, dynamic>;
      final name = '$_remotePrefix${packet['id']}.bin';
      await store.create(
        name,
        await VaultCipher.encrypt(
          gzip.encode(utf8.encode(jsonEncode(packet))),
          key,
          companyId,
        ),
      );
      await db.transaction(() async {
        await _save('${_prefix}seen.$name', {'ok': true});
        await (db.delete(
          db.appSettings,
        )..where((s) => s.key.equals(row.key))).go();
        final ids = (packet['legacy'] as List).cast<String>();
        for (var offset = 0; offset < ids.length; offset += 400) {
          await (db.update(db.syncOperations)..where(
                (o) => o.operationId.isIn(
                  ids.sublist(offset, math.min(offset + 400, ids.length)),
                ),
              ))
              .write(const SyncOperationsCompanion(status: Value('synced')));
        }
      });
      count += (packet['changes'] as List).length;
    }
    return count;
  }

  Future<int> _initialClock(String table, Map<String, dynamic> row) async {
    final at = row['updated_at'] ?? row['created_at'];
    if (at is int) return at * 1000000 + ((row['version'] as int?) ?? 0);
    // Child rows have no timestamp: inherit the owning document's timestamp.
    const parents = {
      'role_permissions': ('roles', 'role_id'),
      'stock_count_items': ('stock_counts', 'stock_count_id'),
      'stock_transfer_items': ('stock_transfers', 'transfer_id'),
      'purchase_order_items': ('purchase_orders', 'purchase_order_id'),
      'purchase_items': ('purchases', 'purchase_id'),
      'sale_items': ('sales', 'sale_id'),
      'price_list_items': ('price_lists', 'price_list_id'),
      'quote_items': ('quotes', 'quote_id'),
      'sale_return_items': ('sale_returns', 'return_id'),
    };
    final parent = parents[table];
    if (parent == null) return 0;
    final found = await db
        .customSelect(
          'SELECT updated_at, version FROM "${parent.$1}" WHERE id = ?',
          variables: [Variable<String>(row[parent.$2] as String)],
        )
        .getSingleOrNull();
    return found == null
        ? 0
        : found.read<int>('updated_at') * 1000000 + found.read<int>('version');
  }

  Future<Map<String, dynamic>> _portable(
    String table,
    Map<String, dynamic> row,
  ) async {
    final data = Map<String, dynamic>.from(row);
    if (table == 'companies') data['device_id'] = 'local';
    final column = table == 'products'
        ? 'image_path'
        : table == 'companies'
        ? 'logo_path'
        : null;
    if (column != null && data[column] != null) {
      final file = File(data[column] as String);
      data[column] = await file.exists()
          ? base64Encode(await file.readAsBytes())
          : null;
    }
    return data;
  }

  Future<void> _writeRow(String table, Map<String, dynamic> change) async {
    final data = Map<String, dynamic>.from(change['data'] as Map);
    if (table == 'companies') {
      final local = await (db.select(
        db.companies,
      )..where((c) => c.id.equals(companyId))).getSingleOrNull();
      // The existing device identity also binds the offline activation code.
      data['device_id'] = local?.deviceId ?? deviceId;
    }
    final column = table == 'products'
        ? 'image_path'
        : table == 'companies'
        ? 'logo_path'
        : null;
    if (column != null && data[column] != null) {
      final bytes = base64Decode(data[column] as String);
      final file = File(
        '${documents.path}/sync-assets/${sha256.convert(bytes)}.img',
      );
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      data[column] = file.path;
    }
    final columns = data.keys.toList();
    final pk = _primaryKey(table, data).keys;
    final updates = columns
        .where((c) => !pk.contains(c))
        .map((c) => '"$c"=excluded."$c"')
        .join(',');
    await db.customStatement(
      'INSERT INTO "$table" (${columns.map((c) => '"$c"').join(',')}) '
      'VALUES (${columns.map((_) => '?').join(',')}) '
      'ON CONFLICT (${pk.map((c) => '"$c"').join(',')}) '
      '${updates.isEmpty ? 'DO NOTHING' : 'DO UPDATE SET $updates'}',
      columns.map((c) => data[c]).toList(),
    );
  }

  Future<void> _deleteRow(String table, Map<String, dynamic> change) async {
    final pk = Map<String, dynamic>.from(change['pk'] as Map);
    await db.customStatement(
      'DELETE FROM "$table" WHERE ${pk.keys.map((c) => '"$c"=?').join(' AND ')}',
      pk.values.toList(),
    );
  }

  Future<void> _refreshDerived(Map<String, Map<String, dynamic>> states) async {
    for (final row in await db.customSelect('SELECT * FROM customers').get()) {
      final rowKey = _rowKey('customers', _primaryKey('customers', row.data));
      final state = states['customers']![rowKey] as Map<String, dynamic>?;
      if (state != null) {
        (state['data'] as Map)['balance_minor'] = row.data['balance_minor'];
      }
    }
    await _save('${_prefix}rows.customers', states['customers']!);
  }

  Map<String, dynamic> _primaryKey(String table, Map<String, dynamic> data) => {
    for (final column in _tables[table]!.$primaryKey)
      column.$name: data[column.$name],
  };
  String _rowKey(String table, Map<String, dynamic> pk) => jsonEncode([
    for (final column in _tables[table]!.$primaryKey) pk[column.$name],
  ]);
  static bool _equal(dynamic a, dynamic b) => _canonical(a) == _canonical(b);
  static String _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    return jsonEncode(value);
  }

  static int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final time = (a['clock'] as int).compareTo(b['clock'] as int);
    if (time != 0) return time;
    final source = (a['source'] as String).compareTo(b['source'] as String);
    return source != 0
        ? source
        : (a['revision'] as String).compareTo(b['revision'] as String);
  }

  void _validate(Map<String, dynamic> packet) {
    for (final raw in packet['changes'] as List) {
      final change = Map<String, dynamic>.from(raw as Map);
      final table = change['table'] as String;
      final info = _tables[table];
      if (info == null ||
          change['clock'] is! int ||
          change['source'] is! String ||
          change['revision'] is! String ||
          change['pk'] is! Map) {
        throw const FormatException('Pacote de sincronização inválido.');
      }
      final pk = Map<String, dynamic>.from(change['pk'] as Map);
      final expectedPk = info.$primaryKey.map((c) => c.$name).toSet();
      if (pk.keys.toSet().difference(expectedPk).isNotEmpty ||
          pk.length != expectedPk.length ||
          pk.values.any((v) => v == null)) {
        throw const FormatException('Identificador de sincronização inválido.');
      }
      if (change['data'] == null) continue;
      final data = Map<String, dynamic>.from(change['data'] as Map);
      final columns = info.$columns.map((c) => c.$name).toSet();
      if (data.length != columns.length ||
          data.keys.toSet().difference(columns).isNotEmpty ||
          !_equal(_primaryKey(table, data), pk) ||
          (data.containsKey('company_id') && data['company_id'] != companyId) ||
          (table == 'companies' && data['id'] != companyId)) {
        throw const FormatException(
          'Os dados recebidos não correspondem à loja.',
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _setting(String name) async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(name))).getSingleOrNull();
    return row == null
        ? null
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
  }

  Future<void> _save(String name, Map<String, dynamic> value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: name,
            valueJson: jsonEncode(value),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }
}
