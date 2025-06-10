// lib/services/lk_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LkService {
  final String baseUrl =
      'http://91.200.84.206/api'; // Для Android-эмулятора // Замените на ваш URL
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // Получить данные профиля
  // Получить данные профиля
  Future<Map<String, dynamic>> fetchProfile() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse(
          '$baseUrl/profile/?format=json'), // Убедитесь, что URL корректен
      headers: {'Cookie': 'users_access_token=$token'},
    );

    // Логируем ответ сервера для отладки
    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      try {
        final String responseBody = utf8.decode(response.bodyBytes);
        return json.decode(responseBody);
      } catch (e) {
        throw FormatException('Ошибка при декодировании JSON: $e');
      }
    } else {
      throw Exception('Ошибка при загрузке профиля: ${response.statusCode}');
    }
  }

  Future<void> markNotificationAsRead(int eventId, String type) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.post(
      Uri.parse('$baseUrl/profile/profile/notifications/mark_as_read_single'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'event_id': eventId, 'type': type}),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Ошибка при обновлении уведомления: ${response.statusCode}');
    }
  }

  // Получить подписчиков
  Future<Map<String, dynamic>> fetchFollowers(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/profile/followers?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Failed to load followers: ${response.body}');
    }
  }

  // Получить подписки
  Future<Map<String, dynamic>> fetchFollowing(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/profile/following?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Failed to load following: ${response.body}');
    }
  }

  // Получить мероприятия пользователя
  Future<Map<String, dynamic>> fetchEvents(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/profile/events?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Failed to load events: ${response.body}');
    }
  }

  // Получить заявки на мероприятие
  Future<Map<String, dynamic>> fetchEventApplications(
      int eventId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/applications?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Failed to load event applications: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> approveApplication(
      int eventId, int participantId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.post(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/applications/$participantId/approve'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      // Возвращаем данные мероприятия из ответа
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody); // Может содержать group_chat_id == null
    } else {
      // Выбрасываем исключение с сообщением об ошибке
      throw Exception('Ошибка одобрения заявки: ${response.bodyBytes}');
    }
  }

  // Отклонить заявку
  Future<void> rejectApplication(int eventId, int participantId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.post(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/applications/$participantId/reject'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to reject application: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> fetchEventDetails(int eventId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception(
          'Ошибка при загрузке деталей мероприятия: ${response.statusCode}');
    }
  }

  Future<void> updateProfile(
      {String? fullName, String? bio, String? avatarPath}) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/profile/'));
    ;
    request.headers['Cookie'] = 'users_access_token=$token';
    if (fullName != null) request.fields['full_name'] = fullName;
    if (bio != null) request.fields['bio'] = bio;
    if (avatarPath != null) {
      request.files
          .add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception(
          'Ошибка при обновлении профиля: ${response.statusCode}, ${responseBody}');
    }
  }

  Future<Map<String, dynamic>> fetchNotifications() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/profile/profile/notifications'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Failed to load notifications: ${response.body}');
    }
  }

  Future<void> markNotificationsAsRead() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/profile/profile/notifications/mark_as_read'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark notifications as read: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> fetchUserApplications(
      int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final response = await http.get(
      Uri.parse("$baseUrl/profile/user/applications?skip=$skip&limit=$limit"),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception("Ошибка загрузки заявок: ${response.statusCode}");
    }
  }
}
