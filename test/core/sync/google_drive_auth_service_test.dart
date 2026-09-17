import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systock/core/sync/google_drive_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android requests Drive access without Android or desktop server ids',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('plugins.flutter.io/google_sign_in');
      Map<dynamic, dynamic>? parameters;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'init':
                parameters = call.arguments as Map<dynamic, dynamic>;
                return null;
              case 'signIn':
                return {'email': 'test@example.com', 'id': 'account'};
              case 'getTokens':
                return {'accessToken': 'test-token'};
              default:
                return null;
            }
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = GoogleDriveAuthService.instance;
      expect(service.configuredClientId, isNull);
      final session = await service.connect();
      addTearDown(session.client.close);
      expect(session.accountId, 'account');
      expect(parameters?['clientId'], isNull);
      expect(parameters?['serverClientId'], isNull);
      expect(
        parameters?['scopes'],
        contains('https://www.googleapis.com/auth/drive.appdata'),
      );
    },
  );
}
