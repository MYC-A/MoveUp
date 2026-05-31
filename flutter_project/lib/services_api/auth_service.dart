import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

class AuthService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  Future<void> _clearAuthData() async {
    await storage.delete(key: 'access_token');
    await storage.delete(key: 'refresh_token');
    await storage.delete(key: 'user_id');
  }

  // Пытается обновить access по refresh-токену. true — успех.
  Future<bool> tryRefreshTokens() async {
    final refreshToken = await storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;
    try {
      final response = await Api.post(
        Uri.parse('$baseUrl/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = json.decode(utf8.decode(response.bodyBytes));
      final access = data['access_token'];
      final refresh = data['refresh_token'];
      if (access == null) return false;
      await storage.write(key: 'access_token', value: access);
      if (refresh != null) {
        await storage.write(key: 'refresh_token', value: refresh);
      }
      return true;
    } catch (e) {
      debugPrint('Не удалось обновить токен: $e');
      return false;
    }
  }

  // Регистрация пользователя
  Future<Map<String, dynamic>> register({
    required String email,
    required String fullName,
    required String password,
    required String passwordCheck,
    String? city,
    double? weight,
    double? height,
  }) async {
    final url = Uri.parse('$baseUrl/auth/register/');
    final response = await Api.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'full_name': fullName,
        'password': password,
        'password_check': passwordCheck,
        if (city != null && city.isNotEmpty) 'city': city,
        if (weight != null) 'weight': weight,
        if (height != null) 'height': height,
      }),
    );
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      return json.decode(responseBody);
    } else if (response.statusCode == 400 ||
        response.statusCode == 409 ||
        response.statusCode == 422) {
      final errorBody = json.decode(responseBody);
      throw Exception('Ошибка регистрации: ${_extractDetail(errorBody)}');
    } else {
      throw Exception('Ошибка соединения: ${response.statusCode}');
    }
  }

  // Подтверждение email кодом из письма. На успехе сохраняет токен (авто-вход).
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse('$baseUrl/auth/verify_email/');
    final response = await Api.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'code': code}),
    );
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      final data = json.decode(responseBody);
      final accessToken = data['access_token'];
      if (accessToken != null) {
        await storage.write(key: 'access_token', value: accessToken);
        final refreshToken = data['refresh_token'];
        if (refreshToken != null) {
          await storage.write(key: 'refresh_token', value: refreshToken);
        }
        final userId = await getCurrentUserId();
        if (userId != null) {
          await storage.write(key: 'user_id', value: userId.toString());
        }
      }
      return data;
    } else {
      final errorBody = json.decode(responseBody);
      throw Exception(_extractDetail(errorBody));
    }
  }

  // Повторная отправка кода подтверждения.
  Future<void> resendCode(String email) async {
    final url = Uri.parse('$baseUrl/auth/resend_code/');
    final response = await Api.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );
    if (response.statusCode != 200) {
      final errorBody = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(_extractDetail(errorBody));
    }
  }

  // Смена пароля авторизованным пользователем.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final token = await storage.read(key: 'access_token');
    final url = Uri.parse('$baseUrl/auth/change_password/');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      final errorBody = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(_extractDetail(errorBody));
    }
  }

  // Достаёт человекочитаемый текст ошибки из тела ответа FastAPI.
  String _extractDetail(dynamic body) {
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
      return detail.toString();
    }
    return 'Неизвестная ошибка';
  }

// Вход пользователя
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/auth/login/');
    final response = await Api.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );

    debugPrint('Login: Response status: ${response.statusCode}');
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      final data = json.decode(responseBody);
      final accessToken = data['access_token'];
      if (accessToken == null) {
        throw Exception('Сервер не вернул access_token');
      }
      await storage.write(key: 'access_token', value: accessToken);
      final refreshToken = data['refresh_token'];
      if (refreshToken != null) {
        await storage.write(key: 'refresh_token', value: refreshToken);
      }
      // Проверяем, сохранен ли токен
      final savedToken = await storage.read(key: 'access_token');
      if (savedToken != accessToken) {
        throw Exception('Ошибка сохранения токена');
      }
      // Кэшируем user_id
      final userId = await getCurrentUserId();
      if (userId != null) {
        await storage.write(key: 'user_id', value: userId.toString());
      } else {
        debugPrint('Login: Failed to fetch user_id');
      }
      return data;
    } else if (response.statusCode == 403) {
      // Email не подтверждён — сигнал экрану, чтобы увёл на ввод кода.
      throw Exception('EMAIL_NOT_VERIFIED');
    } else if (response.statusCode == 400) {
      final errorBody = json.decode(responseBody);
      throw Exception(
          'Ошибка входа: ${errorBody['detail'] ?? 'Неизвестная ошибка'}');
    } else if (response.statusCode == 401) {
      throw Exception('Неверный email или пароль');
    } else {
      throw Exception('Ошибка соединения: ${response.statusCode}');
    }
  }

  // Выход пользователя
  Future<void> logout() async {
    final url = Uri.parse('$baseUrl/auth/logout/');
    final token = await storage.read(key: 'access_token');
    await PushNotificationService.unregisterCurrentDeviceToken();
    final response = await Api.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    await storage.delete(key: 'access_token');
    await storage.delete(key: 'user_id');
    if (response.statusCode != 200) {
      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('Logout failed with status: ${response.statusCode}');
      throw Exception('Ошибка выхода: ${json.decode(responseBody)}');
    }
    debugPrint('Logout successful');
  }

  // Проверка текущего пользователя
  Future<int?> getCurrentUserId() async {
    var token = await storage.read(key: 'access_token');

    if (token == null) {
      await storage.delete(key: 'user_id');
      return null;
    }

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    int retries = 0;
    bool triedRefresh = false;

    final url = Uri.parse('$baseUrl/auth/current_user');
    while (retries < maxRetries) {
      try {
        final response = await Api.get(
          url,
          headers: {'Cookie': 'users_access_token=$token'},
        );

        debugPrint(
            'getCurrentUserId: Response status: ${response.statusCode}');
        final responseBody = utf8.decode(response.bodyBytes);

        if (response.statusCode == 200) {
          int? userId;
          try {
            final data = json.decode(responseBody);
            if (data is int) {
              userId = data; // Ответ — число
            } else if (data is Map<String, dynamic>) {
              userId = data['id'] ?? data['user_id'];
            }
          } catch (e) {
            // Если JSON-декодирование не удалось, пробуем интерпретировать как число
            try {
              userId = int.parse(responseBody);
            } catch (_) {
              debugPrint(
                  'getCurrentUserId: Failed to parse response body as integer');
            }
          }

          if (userId == null) {
            await _clearAuthData();
            return null;
          }

          // Кэшируем user_id
          await storage.write(key: 'user_id', value: userId.toString());
          return userId;
        } else if (response.statusCode == 401) {
          // Access истёк — пробуем один раз обновить по refresh-токену.
          if (!triedRefresh) {
            triedRefresh = true;
            if (await tryRefreshTokens()) {
              token = await storage.read(key: 'access_token');
              if (token != null) continue; // повтор с новым токеном
            }
          }
          await _clearAuthData();
          return null;
        } else {
          debugPrint(
              'getCurrentUserId: Failed with status: ${response.statusCode}');
          retries++;
          if (retries == maxRetries) {
            return null;
          }
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        debugPrint('getCurrentUserId: Error: $e');
        retries++;
        if (retries == maxRetries) {
          return null;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }
}
