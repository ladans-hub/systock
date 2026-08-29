import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:systock/core/sync/google_drive_transport.dart';

class GoogleDriveSession {
  GoogleDriveSession({required this.email, required this.client});
  final String email;
  final http.Client client;
}

class GoogleDriveAuthService {
  GoogleDriveAuthService._();
  static final instance = GoogleDriveAuthService._();
  final _signIn = GoogleSignIn.instance;
  bool _initialized = false;

  static const _appleClientId = String.fromEnvironment(
    'GOOGLE_APPLE_CLIENT_ID',
  );
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// OAuth identifiers are supplied at build time and never committed.
  /// Apple builds may alternatively obtain the client id from
  /// GoogleService-Info.plist.
  String? get configuredClientId {
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        _appleClientId.isNotEmpty) {
      return _appleClientId;
    }
    return null;
  }

  Future<void> initialize({String? clientId, String? serverClientId}) async {
    if (_initialized) return;
    await _signIn.initialize(
      clientId: clientId ?? configuredClientId,
      serverClientId:
          serverClientId ?? (_serverClientId.isEmpty ? null : _serverClientId),
    );
    _initialized = true;
  }

  Future<GoogleDriveSession> connect() async {
    await initialize();
    final account = await _signIn.authenticate(
      scopeHint: const [GoogleDriveSyncTransport.requiredScope],
    );
    final authorization = await account.authorizationClient.authorizeScopes(
      const [GoogleDriveSyncTransport.requiredScope],
    );
    return GoogleDriveSession(
      email: account.email,
      client: _BearerClient(authorization.accessToken),
    );
  }

  Future<GoogleDriveSession?> reconnectSilently() async {
    await initialize();
    final account = await _signIn.attemptLightweightAuthentication();
    if (account == null) return null;
    final authorization = await account.authorizationClient
        .authorizationForScopes(const [GoogleDriveSyncTransport.requiredScope]);
    if (authorization == null) return null;
    return GoogleDriveSession(
      email: account.email,
      client: _BearerClient(authorization.accessToken),
    );
  }

  Future<void> disconnect() async {
    await initialize();
    await _signIn.disconnect();
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
