import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Тонкая обёртка над `http` с единым таймаутом и преобразованием транспортных
/// ошибок (нет сети / таймаут) в [ApiException]. Статус-коды обрабатывают сами
/// сервисы (через [ApiException.fromResponse] на не-2xx), чтобы не менять их
/// логику.
class Api {
  static const Duration timeout = Duration(seconds: 20);

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _guard(() => http.get(url, headers: headers));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _guard(() => http.post(url, headers: headers, body: body));

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _guard(() => http.put(url, headers: headers, body: body));

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _guard(() => http.delete(url, headers: headers, body: body));

  /// Отправка готового запроса (multipart и т.п.).
  static Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await request.send().timeout(timeout);
    } catch (e) {
      throw ApiException.fromError(e);
    }
  }

  static Future<http.Response> _guard(
      Future<http.Response> Function() run) async {
    try {
      return await run().timeout(timeout);
    } catch (e) {
      throw ApiException.fromError(e);
    }
  }
}
