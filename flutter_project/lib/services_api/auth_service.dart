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
    await storage.delete(key: 'user_id');
  }

  // Регистрация пользователя
  Future<Map<String, dynamic>> register({
    required String email,
    required String fullName,
    required String password,
    required String passwordCheck,
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
      }),
    );
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      return json.decode(responseBody);
    } else if (response.statusCode == 400) {
      final errorBody = json.decode(responseBody);
      throw Exception('Ошибка регистрации: ${errorBody['detail']}');
    } else {
      throw Exception('Ошибка соединения: ${response.statusCode}');
    }
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
    final token = await storage.read(key: 'access_token');

    if (token == null) {
      await storage.delete(key: 'user_id');
      return null;
    }

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    int retries = 0;

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
