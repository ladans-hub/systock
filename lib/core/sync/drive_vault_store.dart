import 'dart:convert';
import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class VaultFile {
  const VaultFile(this.id, this.name, this.createdAt);
  final String id, name;
  final DateTime createdAt;
}

abstract interface class DriveVaultStore {
  Future<List<VaultFile>> list(String prefix);
  Future<Uint8List> read(String id);
  Future<String> create(String name, List<int> bytes);
  Future<void> delete(String id);
}

/// All writes create immutable files. There is no mutable "latest" pointer.
class GoogleDriveVaultStore implements DriveVaultStore {
  GoogleDriveVaultStore(http.Client client) : api = drive.DriveApi(client);
  final drive.DriveApi api;
  @override
  Future<List<VaultFile>> list(String prefix) async {
    final result = <VaultFile>[];
    String? token;
    do {
      final page = await retry(
        () => api.files.list(
          spaces: 'appDataFolder',
          q: "name contains '${prefix.replaceAll("'", "\\'")}' and trashed = false",
          pageToken: token,
          pageSize: 1000,
          $fields: 'nextPageToken,files(id,name,createdTime)',
        ),
      );
      for (final file in page.files ?? <drive.File>[]) {
        if (file.id != null && (file.name ?? '').startsWith(prefix)) {
          result.add(
            VaultFile(
              file.id!,
              file.name!,
              file.createdTime ?? DateTime.utc(1970),
            ),
          );
        }
      }
      token = page.nextPageToken;
    } while (token != null);
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<Uint8List> read(String id) => retry(() async {
    final media =
        await api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  });
  @override
  Future<String> create(String name, List<int> bytes) async {
    // Retrying by a unique name also handles an upload whose response was lost.
    return retry(() async {
      final existing = await list(name);
      if (existing.any((f) => f.name == name))
        return existing.firstWhere((f) => f.name == name).id;
      final file = await api.files.create(
        drive.File(
          name: name,
          parents: ['appDataFolder'],
          mimeType: 'application/octet-stream',
        ),
        uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
        $fields: 'id',
      );
        return file.id!;
    });
  }

  @override
  Future<void> delete(String id) => retry(() => api.files.delete(id));
  static Future<T> retry<T>(Future<T> Function() action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } on drive.DetailedApiRequestError catch (e) {
        final transient =
            e.status == 429 ||
            (e.status ?? 0) >= 500 ||
            (e.status == 403 &&
                e.errors.any(
                      (v) =>
                          v.reason == 'rateLimitExceeded' ||
                          v.reason == 'userRateLimitExceeded',
                    ) ==
                    true);
        if (!transient || attempt >= 3) rethrow;
      } on http.ClientException {
        if (attempt >= 3) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
    }
  }
}

Map<String, dynamic> decodeVaultJson(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
