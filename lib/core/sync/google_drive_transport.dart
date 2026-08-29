import 'dart:convert';
import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:systock/core/sync/sync_transport.dart';

class GoogleDriveSyncTransport implements SyncTransport {
  GoogleDriveSyncTransport(http.Client authenticatedClient)
    : _api = drive.DriveApi(authenticatedClient);
  final drive.DriveApi _api;
  static const requiredScope = drive.DriveApi.driveAppdataScope;

  Future<void> uploadRecoverySnapshot({
    required List<int> databaseBytes,
    required Map<String, Object> metadata,
  }) async {
    await _upsertFile(
      'latest-recovery-snapshot.sqlite',
      'application/vnd.sqlite3',
      databaseBytes,
    );
    await _upsertFile(
      'latest-recovery-snapshot.json',
      'application/json',
      utf8.encode(jsonEncode(metadata)),
    );
  }

  Future<({Uint8List bytes, Map<String, dynamic> metadata})?>
  downloadRecoverySnapshot() async {
    final database = await _findByName('latest-recovery-snapshot.sqlite');
    final metadata = await _findByName('latest-recovery-snapshot.json');
    if (database?.id == null || metadata?.id == null) return null;
    final databaseBytes = await _downloadBytes(database!.id!);
    final metadataBytes = await _downloadBytes(metadata!.id!);
    return (
      bytes: databaseBytes,
      metadata: jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>,
    );
  }

  Future<drive.File?> _findByName(String name) async {
    final result = await _retry(
      () => _api.files.list(
        spaces: 'appDataFolder',
        q: "name = '${_q(name)}' and trashed = false",
        pageSize: 1,
        $fields: 'files(id,name,modifiedTime)',
      ),
    );
    return result.files?.firstOrNull;
  }

  Future<Uint8List> _downloadBytes(String id) async {
    final media =
        await _retry(
              () => _api.files.get(
                id,
                downloadOptions: drive.DownloadOptions.fullMedia,
              ),
            )
            as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _upsertFile(
    String name,
    String mimeType,
    List<int> bytes,
  ) async {
    final existing = await _findByName(name);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existing?.id != null) {
      await _retry(
        () => _api.files.update(
          drive.File(mimeType: mimeType),
          existing!.id!,
          uploadMedia: media,
        ),
      );
      return;
    }
    await _retry(
      () => _api.files.create(
        drive.File(
          name: name,
          parents: const ['appDataFolder'],
          mimeType: mimeType,
        ),
        uploadMedia: media,
      ),
    );
  }

  @override
  Future<void> upload(List<SyncEnvelope> operations) async {
    for (var offset = 0; offset < operations.length; offset += 100) {
      final end = offset + 100 < operations.length
          ? offset + 100
          : operations.length;
      final batch = operations.sublist(offset, end);
      if (batch.isEmpty) continue;
      final name =
          'sync-${batch.first.deviceId}-${batch.first.operationId}-${batch.last.operationId}.json';
      final existing = await _retry(
        () => _api.files.list(
          spaces: 'appDataFolder',
          q: "name = '${_q(name)}' and trashed = false",
          $fields: 'files(id)',
        ),
      );
      if (existing.files?.isNotEmpty ?? false) continue;
      final bytes = utf8.encode(jsonEncode(batch.map(_toJson).toList()));
      await _retry(
        () => _api.files.create(
          drive.File(
            name: name,
            parents: const ['appDataFolder'],
            mimeType: 'application/json',
          ),
          uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
        ),
      );
    }
  }

  @override
  Future<List<SyncEnvelope>> download({
    required Set<String> excludingOperationIds,
  }) async {
    final result = <SyncEnvelope>[];
    String? token;
    do {
      final page = await _retry(
        () => _api.files.list(
          spaces: 'appDataFolder',
          q: "name contains 'sync-' and trashed = false",
          pageToken: token,
          pageSize: 1000,
          $fields: 'nextPageToken,files(id,name)',
        ),
      );
      for (final file in page.files ?? const <drive.File>[]) {
        if (file.id == null) continue;
        try {
          final media =
              await _retry(
                    () => _api.files.get(
                      file.id!,
                      downloadOptions: drive.DownloadOptions.fullMedia,
                    ),
                  )
                  as drive.Media;
          final content = await utf8.decoder.bind(media.stream).join();
          final decoded = jsonDecode(content);
          final entries = decoded is List<dynamic> ? decoded : [decoded];
          for (final entry in entries) {
            final envelope = _fromJson(entry as Map<String, dynamic>);
            if (!excludingOperationIds.contains(envelope.operationId)) {
              result.add(envelope);
            }
          }
        } on FormatException {
          // A malformed immutable package must not block valid packages.
        } on TypeError {
          // Ignore documents that do not implement the sync envelope schema.
        }
      }
      token = page.nextPageToken;
    } while (token != null);
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  static String _q(String value) => value.replaceAll("'", "\\'");
  Future<T> _retry<T>(Future<T> Function() action) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await action();
      } catch (error) {
        last = error;
        if (attempt == 3) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (1 << attempt) + attempt * 137),
        );
      }
    }
    throw StateError('Retry exhausted: $last');
  }

  static Map<String, Object> _toJson(SyncEnvelope o) => {
    'operationId': o.operationId,
    'deviceId': o.deviceId,
    'entityType': o.entityType,
    'entityId': o.entityId,
    'operation': o.operation,
    'version': o.version,
    'payloadJson': o.payloadJson,
    'checksum': o.checksum,
    'createdAt': o.createdAt.toIso8601String(),
  };
  static SyncEnvelope _fromJson(Map<String, dynamic> j) => SyncEnvelope(
    operationId: j['operationId'] as String,
    deviceId: j['deviceId'] as String,
    entityType: j['entityType'] as String,
    entityId: j['entityId'] as String,
    operation: j['operation'] as String,
    version: j['version'] as int,
    payloadJson: j['payloadJson'] as String,
    checksum: j['checksum'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}
