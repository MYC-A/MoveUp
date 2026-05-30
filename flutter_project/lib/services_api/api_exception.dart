import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Тип ошибки запроса — чтобы UI мог различать сеть/таймаут/401 и т.д.
enum ApiErrorKind {
  network, // нет интернета / не достучались до сервера
  timeout, // превышено время ожидания
  unauthorized, // 401 — сессия истекла
  forbidden, // 403 — нет прав
  notFound, // 404
  server, // 5xx
  unknown,
}

/// Единая типизированная ошибка работы с API.
///
/// `message` — человекочитаемый текст для пользователя (НЕ сырое тело ответа).
/// Реализует `Exception` и имеет `toString() => message`, поэтому даже старый
/// код вида `SnackBar(Text('Ошибка: $e'))` покажет нормальный текст.
class ApiException implements Exception {
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  ApiException(this.kind, this.message, {this.statusCode});

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
  bool get isOffline =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  /// Маппинг HTTP-ответа (не 2xx) в понятную ошибку. Пытается достать `detail`
  /// из JSON, иначе подставляет дефолтный текст по статусу.
  factory ApiException.fromResponse(http.Response response) {
    final code = response.statusCode;
    String? detail;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) {
        final d = decoded['detail'];
        detail = d is String ? d : d.toString();
      }
    } catch (_) {
      // тело не JSON — игнорируем, покажем дефолтный текст
    }

    final kind = _kindForStatus(code);
    // Для 401/5xx не показываем серверный detail (часто технический), для
    // остального — показываем detail, если он есть.
    final useDetail = detail != null &&
        detail.isNotEmpty &&
        kind != ApiErrorKind.unauthorized &&
        kind != ApiErrorKind.server;
    return ApiException(
      kind,
      useDetail ? detail : _defaultMessage(kind),
      statusCode: code,
    );
  }

  /// Ошибка по одному статус-коду (когда нет полного [http.Response], например
  /// для multipart-ответа).
  factory ApiException.fromStatus(int statusCode, {String? detail}) {
    final kind = _kindForStatus(statusCode);
    final useDetail = detail != null &&
        detail.isNotEmpty &&
        kind != ApiErrorKind.unauthorized &&
        kind != ApiErrorKind.server;
    return ApiException(
      kind,
      useDetail ? detail : _defaultMessage(kind),
      statusCode: statusCode,
    );
  }

  /// Маппинг произвольной ошибки (сеть/таймаут/прочее) в ApiException.
  factory ApiException.fromError(Object error) {
    if (error is ApiException) return error;
    if (error is TimeoutException) {
      return ApiException(ApiErrorKind.timeout,
          'Превышено время ожидания. Проверьте соединение и попробуйте снова.');
    }
    if (error is SocketException) {
      return ApiException(
          ApiErrorKind.network, 'Нет подключения к интернету.');
    }
    if (error is http.ClientException) {
      return ApiException(
          ApiErrorKind.network, 'Не удалось связаться с сервером.');
    }
    if (error is HttpException) {
      return ApiException(
          ApiErrorKind.network, 'Не удалось связаться с сервером.');
    }
    return ApiException(
        ApiErrorKind.unknown, 'Что-то пошло не так. Попробуйте ещё раз.');
  }

  static ApiErrorKind _kindForStatus(int code) {
    if (code == 401) return ApiErrorKind.unauthorized;
    if (code == 403) return ApiErrorKind.forbidden;
    if (code == 404) return ApiErrorKind.notFound;
    if (code >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  static String _defaultMessage(ApiErrorKind kind) {
    switch (kind) {
      case ApiErrorKind.unauthorized:
        return 'Сессия истекла. Войдите снова.';
      case ApiErrorKind.forbidden:
        return 'Недостаточно прав для этого действия.';
      case ApiErrorKind.notFound:
        return 'Запрашиваемые данные не найдены.';
      case ApiErrorKind.server:
        return 'Ошибка на сервере. Попробуйте позже.';
      case ApiErrorKind.network:
        return 'Нет подключения к интернету.';
      case ApiErrorKind.timeout:
        return 'Превышено время ожидания.';
      case ApiErrorKind.unknown:
        return 'Что-то пошло не так. Попробуйте ещё раз.';
    }
  }

  @override
  String toString() => message;
}
