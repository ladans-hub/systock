import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class OAuthTokenStore {
  Future<void> writeRefreshToken(String token);
  Future<String?> readRefreshToken();
  Future<void> clear();
}

class SecureOAuthTokenStore implements OAuthTokenStore {
  const SecureOAuthTokenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;
  static const _key = 'google_drive_refresh_token';
  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);
  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
