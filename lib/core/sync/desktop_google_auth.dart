import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'drive_vault_identity.dart';

/// System browser + loopback redirect + PKCE for installed desktop clients.
class DesktopGoogleAuth {
  DesktopGoogleAuth({this.secrets = const SecureVaultSecrets()});
  final VaultSecrets secrets;
  static const clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  // Installed client credentials identify the app; they are not server secrets.
  static const clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );
  static const scope =
      'openid email https://www.googleapis.com/auth/drive.appdata';
  String randomToken() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<({String token, String accountId, String email})> connect() async {
    if (clientId.isEmpty) {
      throw StateError(
        'A ligação Google Drive ainda não está configurada nesta versão do Systock. Contacte o fornecedor.',
      );
    }
    final verifier = randomToken(), state = randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth2callback';
    final completion = Completer<String>();
    final subscription = server.listen((request) async {
      if (request.uri.path != '/oauth2callback' ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><meta charset="utf-8"><title>Systock</title><p>Pode voltar ao Systock.</p>',
      );
      await request.response.close();
      if (!completion.isCompleted) {
        if (code == null) {
          completion.completeError(
            StateError('A autorização Google foi cancelada.'),
          );
        } else {
          completion.complete(code);
        }
      }
    });
    try {
      final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent select_account',
        'code_challenge': base64UrlEncode(
          sha256.convert(ascii.encode(verifier)).bytes,
        ).replaceAll('=', ''),
        'code_challenge_method': 'S256',
      });
      final codeFuture = completion.future.timeout(const Duration(minutes: 3));
      // Attach a handler before opening the browser, including early failures.
      unawaited(
        codeFuture.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(
          'Não foi possível abrir o navegador para ligar o Google Drive.',
        );
      }
      final code = await codeFuture;
      final tokens = await _exchange({
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
      });
      final refresh = tokens['refresh_token'] as String?;
      if (refresh == null) {
        throw StateError(
          'Autorize o acesso offline ao Google Drive e tente novamente.',
        );
      }
      final result = await _identity(tokens['access_token'] as String);
      await secrets.write(
        'oauth',
        jsonEncode({
          'refreshToken': refresh,
          'clientId': clientId,
          'accountId': result.accountId,
        }),
      );
      return result;
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<({String token, String accountId, String email})?> reconnect() async {
    if (clientId.isEmpty) return null;
    final value = await secrets.read('oauth');
    if (value == null || value.isEmpty) return null;
    final saved = jsonDecode(value) as Map<String, dynamic>;
    if (saved['clientId'] != clientId) return null;
    final tokens = await _exchange({
      'grant_type': 'refresh_token',
      'refresh_token': saved['refreshToken'] as String,
    });
    final result = await _identity(tokens['access_token'] as String);
    if (result.accountId != saved['accountId']) {
      throw StateError(
        'A identidade da conta Google mudou. Volte a ligar a conta.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _exchange(Map<String, String> body) async {
    final response = await http
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {
            ...body,
            'client_id': clientId,
            if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      var reason = 'resposta HTTP ${response.statusCode}';
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        final code = error['error'];
        final description = error['error_description'];
        reason = [code, description].whereType<String>().join(': ');
      } on Object {
        // Keep the provider response out of the UI when it is not JSON.
      }
      if (body['grant_type'] == 'refresh_token') {
        await secrets.write('oauth', '');
        throw StateError(
          'A autorização Google expirou ou foi revogada ($reason). Volte a ligar a conta.',
        );
      }
      throw StateError('A Google recusou a autorização ($reason).');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final granted = (data['scope'] as String?)?.split(' ');
    if (granted != null &&
        !granted.contains('https://www.googleapis.com/auth/drive.appdata')) {
      throw StateError(
        'É necessário autorizar a pasta privada do Systock no Drive.',
      );
    }
    return data;
  }

  Future<({String token, String accountId, String email})> _identity(
    String token,
  ) async {
    final response = await http
        .get(
          Uri.https('openidconnect.googleapis.com', '/v1/userinfo'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Não foi possível verificar a conta Google.');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      token: token,
      accountId: value['sub'] as String,
      email: value['email'] as String,
    );
  }

  Future<void> disconnect() async {
    // Local sign-out must not revoke the grant used by the other devices.
    await secrets.write('oauth', '');
  }
}
