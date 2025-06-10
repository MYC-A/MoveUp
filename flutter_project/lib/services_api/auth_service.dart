import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final String baseUrl = 'http://91.200.84.206/api'; // Для Android-эмулятора
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // Регистрация пользователя
  Future<Map<String, dynamic>> register({
    required String email,
    required String fullName,
    required String password,
    required String passwordCheck,
  }) async {
    final url = Uri.parse('$baseUrl/auth/register/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'full_name': fullName,
        'password': password,
        'password_check': passwordCheck,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 400) {
      final errorBody = json.decode(response.body);
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
    print('Login: Sending request to $url');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );

    print('Login: Response status: ${response.statusCode}');
    print('Login: Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final accessToken = data['access_token'];
      if (accessToken == null) {
        print('Login: No access_token in response');
        throw Exception('Сервер не вернул access_token');
      }
      print('Login: Saving access_token: $accessToken');
      await storage.write(key: 'access_token', value: accessToken);
      // Проверяем, сохранен ли токен
      final savedToken = await storage.read(key: 'access_token');
      print('Login: Verified saved access_token: $savedToken');
      if (savedToken != accessToken) {
        print('Login: Failed to save access_token');
        throw Exception('Ошибка сохранения токена');
      }
      // Кэшируем user_id
      final userId = await getCurrentUserId();
      if (userId != null) {
        await storage.write(key: 'user_id', value: userId.toString());
        print('Login: Saved user_id: $userId');
      } else {
        print('Login: Failed to fetch user_id');
      }
      return data;
    } else if (response.statusCode == 400) {
      final errorBody = json.decode(response.body);
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
    print('Logout: Token read: $token');
    final response = await http.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    await storage.delete(key: 'access_token');
    await storage.delete(key: 'user_id');
    if (response.statusCode != 200) {
      print('Logout failed: ${response.body}');
      throw Exception('Ошибка выхода: ${json.decode(response.body)}');
    }
    print('Logout successful');
  }

  // Проверка текущего пользователя
  Future<int?> getCurrentUserId() async {
    // Проверяем кэшированный user_id
    final cachedUserId = await storage.read(key: 'user_id');
    if (cachedUserId != null) {
      print('getCurrentUserId: Cached user_id: $cachedUserId');
      return int.parse(cachedUserId);
    }

    final token = await storage.read(key: 'access_token');
    print('getCurrentUserId: Token read: $token');

    if (token == null) {
      print('getCurrentUserId: No token found');
      return null;
    }

    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    int retries = 0;

    final url = Uri.parse('$baseUrl/auth/current_user');
    while (retries < maxRetries) {
      try {
        final response = await http.get(
          url,
          headers: {'Cookie': 'users_access_token=$token'},
        );

        print('getCurrentUserId: Response status: ${response.statusCode}');
        print('getCurrentUserId: Response body: ${response.body}');

        if (response.statusCode == 200) {
          int? userId;
          try {
            final data = json.decode(response.body);
            if (data is int) {
              userId = data; // Ответ — число
            } else if (data is Map<String, dynamic>) {
              userId = data['id'] ?? data['user_id'];
            }
          } catch (e) {
            print('getCurrentUserId: JSON decode error: $e');
            // Если JSON-декодирование не удалось, пробуем интерпретировать как число
            try {
              userId = int.parse(response.body);
            } catch (_) {
              print(
                  'getCurrentUserId: Failed to parse response body as integer');
            }
          }

          if (userId == null) {
            print('getCurrentUserId: No user ID in response');
            await storage.delete(key: 'access_token');
            await storage.delete(key: 'user_id');
            return null;
          }

          print('getCurrentUserId: User ID: $userId');
          // Кэшируем user_id
          await storage.write(key: 'user_id', value: userId.toString());
          print('getCurrentUserId: Saved user_id: $userId');
          return userId;
        } else if (response.statusCode == 401) {
          print('getCurrentUserId: Unauthorized, deleting token');
          await storage.delete(key: 'access_token');
          await storage.delete(key: 'user_id');
          return null;
        } else {
          print('getCurrentUserId: Failed with status: ${response.statusCode}');
          retries++;
          if (retries == maxRetries) {
            print('getCurrentUserId: Max retries reached');
            return null;
          }
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        print('getCurrentUserId: Error: $e');
        retries++;
        if (retries == maxRetries) {
          print('getCurrentUserId: Max retries reached');
          return null;
        }
        await Future.delayed(retryDelay);
      }
    }
    return null;
  }
}
