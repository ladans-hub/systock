import 'dart:io';

class ConnectivityService {
  const ConnectivityService();

  /// Tests actual reachability, not merely Wi-Fi/mobile interface presence.
  Future<bool> hasInternet() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      try {
        final request = await client.getUrl(
          Uri.https('www.googleapis.com', '/discovery/v1/apis/drive/v3/rest'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        await response.drain<void>();
        return response.statusCode >= 200 && response.statusCode < 500;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }
}
