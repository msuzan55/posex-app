/// PosEx API configuration — matches posex web app endpoints.
class ApiConfig {
  ApiConfig._();

  /// Production PosEx API (nginx proxies `/api` on same host).
  static const String productionBaseUrl = 'https://posex.lk';

  /// Android emulator → posex-docker-stack backend on host.
  static const String localBaseUrl = 'http://10.0.2.2:18000';

  static const String authLogin = '/api/v1/auth/login';
  static const String authMe = '/api/v1/auth/me';
  static const String productsList = '/api/v1/products/';

  static String resolveBaseUrl({bool useLocal = false}) {
    if (useLocal) return localBaseUrl;
    return productionBaseUrl;
  }

  static String productUploadPrefix(String baseUrl) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base/upload/products/';
  }
}
