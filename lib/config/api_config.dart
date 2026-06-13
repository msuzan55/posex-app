/// PosEx API configuration — mirrors posex_test web defaults.
class ApiConfig {
  ApiConfig._();

  /// Production PosEx API (nginx proxies `/api` on same host).
  static const String productionBaseUrl = 'https://posex.lk';

  /// Staging / dev API when testing against posex.lk/test.
  static const String stagingBaseUrl = 'https://posex.lk';

  /// Default for local emulator pointing at posex-docker-stack backend.
  static const String localBaseUrl = 'http://10.0.2.2:18000';

  static const String authLoginPath = '/api/v2/auth/login';
  static const String syncChangesPath = '/api/v2/sync/changes';
  static const String syncPushPath = '/api/v2/sync/push';

  static String resolveBaseUrl({bool useStaging = false, bool useLocal = false}) {
    if (useLocal) return localBaseUrl;
    if (useStaging) return stagingBaseUrl;
    return productionBaseUrl;
  }
}
