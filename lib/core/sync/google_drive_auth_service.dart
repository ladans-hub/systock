import 'desktop_google_auth.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:systock/core/sync/google_drive_transport.dart';

class GoogleDriveSession {
  GoogleDriveSession({
    required this.email,
    required this.accountId,
    required this.client,
  });
  final String accountId;
  final String email;
  final http.Client client;
}

class GoogleDriveAuthService {
  GoogleDriveAuthService._();
  static final instance = GoogleDriveAuthService._();
  GoogleSignIn? _signIn;
  bool _initialized = false;
  final _desktop = DesktopGoogleAuth();
  bool get usesDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      (defaultTargetPlatform == TargetPlatform.macOS &&
          DesktopGoogleAuth.clientId.isNotEmpty);

  static const _appleClientId = String.fromEnvironment(
    'GOOGLE_APPLE_CLIENT_ID',
  );
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// OAuth identifiers are supplied at build time and never committed.
  /// Apple builds may alternatively obtain the client id from
  /// GoogleService-Info.plist.
  String? get configuredClientId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (_iosClientId.isNotEmpty) return _iosClientId;
      if (_appleClientId.isNotEmpty) return _appleClientId;
    }
    // Android identifies the app by package name and signing certificate.
    // Passing its Android OAuth id here incorrectly requests a server token.
    if (defaultTargetPlatform == TargetPlatform.android) return null;
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        _appleClientId.isNotEmpty) {
      return _appleClientId;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        _iosClientId.isNotEmpty) {
      return _iosClientId;
    }
    return null;
  }

  Future<void> initialize({String? clientId, String? serverClientId}) async {
    if (_initialized) return;
    // Only a Web OAuth client may be used as serverClientId. Drive access
    // with google_sign_in 6.x does not require a backend or server token.
    final configuredServerClientId = _serverClientId.isNotEmpty
        ? _serverClientId
        : null;
    _signIn = GoogleSignIn(
      scopes: const [GoogleDriveSyncTransport.requiredScope],
      clientId: defaultTargetPlatform == TargetPlatform.android
          ? null
          : clientId ?? configuredClientId,
      serverClientId: serverClientId ?? configuredServerClientId,
    );
    _initialized = true;
  }

  Future<GoogleDriveSession> connect() async {
    if (usesDesktop) {
      final result = await _desktop.connect();
      return GoogleDriveSession(
        email: result.email,
        accountId: result.accountId,
        client: _BearerClient(result.token),
      );
    }
    await initialize();
    final account = await _signIn!.signIn().timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException('signIn'),
    );
    if (account == null) {
      throw StateError('O utilizador cancelou o login Google.');
    }
    final token = (await account.authentication).accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('O Google não devolveu um token de acesso ao Drive.');
    }
    return GoogleDriveSession(
      email: account.email,
      accountId: account.id,
      client: _BearerClient(token),
    );
  }

  Future<GoogleDriveSession?> reconnectSilently() async {
    if (usesDesktop) {
      final result = await _desktop.reconnect();
      return result == null
          ? null
          : GoogleDriveSession(
              email: result.email,
              accountId: result.accountId,
              client: _BearerClient(result.token),
            );
    }
    await initialize();
    final account = await _signIn!.signInSilently();
    if (account == null) return null;
    final token = (await account.authentication).accessToken;
    if (token == null || token.isEmpty) return null;
    return GoogleDriveSession(
      email: account.email,
      accountId: account.id,
      client: _BearerClient(token),
    );
  }

  Future<void> disconnect() async {
    if (usesDesktop) {
      await _desktop.disconnect();
      return;
    }
    await initialize();
    await _signIn!.signOut();
  }
}

class _BearerClient extends http.BaseClient {
  _BearerClient(this._token);
  final String _token;
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
