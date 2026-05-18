class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://91.200.84.206/api',
  );

  static const wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://91.200.84.206/api',
  );

  static const mediaBaseUrl = String.fromEnvironment(
    'MEDIA_BASE_URL',
    defaultValue: 'http://91.200.84.206/minio',
  );

  static const openRouteServiceApiKey = String.fromEnvironment(
    'OPEN_ROUTE_API_KEY',
    defaultValue: '',
  );

  static String get mediaBaseUrlWithoutScheme {
    return mediaBaseUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceAll(RegExp(r'/$'), '');
  }

  static String normalizeMediaUrl(String url) {
    final normalizedBaseUrl = mediaBaseUrl.replaceAll(RegExp(r'/$'), '');

    return url
        .replaceFirst('http://localhost:9000', normalizedBaseUrl)
        .replaceFirst('https://localhost:9000', normalizedBaseUrl)
        .replaceFirst('localhost:9000', mediaBaseUrlWithoutScheme);
  }
}
