// lib/services/lk_service.dart
import 'dart:convert';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'api_exception.dart';

class LkService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // Получить данные профиля
  // Получить данные профиля
  Future<Map<String, dynamic>> fetchProfile() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
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
        final data = json.decode(responseBody);
        // Кэшируем вес, чтобы экраны маршрутов/трекер считали калории по
        // реальному весу пользователя без отдельного запроса.
        final weight = data['user']?['weight'];
        if (weight is num) {
          await storage.write(key: 'user_weight', value: weight.toString());
        }
        return data;
      } catch (e) {
        throw FormatException('Ошибка при декодировании JSON: $e');
      }
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<void> markNotificationAsRead(int eventId, String type) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.post(
      Uri.parse('$baseUrl/profile/profile/notifications/mark_as_read_single'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'event_id': eventId, 'type': type}),
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Помечает прочитанным персистентное уведомление (раздел event_updates).
  Future<void> markEventUpdateRead(int notificationId) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.post(
      Uri.parse('$baseUrl/profile/profile/notifications/mark_update_read'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'notification_id': notificationId}),
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить подписчиков
  Future<Map<String, dynamic>> fetchFollowers(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse('$baseUrl/profile/followers?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить подписки
  Future<Map<String, dynamic>> fetchFollowing(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse('$baseUrl/profile/following?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить мероприятия пользователя
  Future<Map<String, dynamic>> fetchEvents(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse('$baseUrl/profile/events?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить заявки на мероприятие
  Future<Map<String, dynamic>> fetchEventApplications(
      int eventId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/applications?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<Map<String, dynamic>> fetchEventParticipants(
      int eventId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/participants?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<Map<String, dynamic>> approveApplication(
      int eventId, int participantId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.post(
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
      throw ApiException.fromResponse(response);
    }
  }

  // Отклонить заявку
  Future<void> rejectApplication(int eventId, int participantId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.post(
      Uri.parse(
          '$baseUrl/profile/event/$eventId/applications/$participantId/reject'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  Future<Map<String, dynamic>> removeEventParticipant(
      int eventId, int participantId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.delete(
      Uri.parse('$baseUrl/profile/event/$eventId/participants/$participantId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    }
    throw ApiException.fromResponse(response);
  }

  Future<Map<String, dynamic>> fetchEventDetails(int eventId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse('$baseUrl/events/$eventId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? bio,
    String? avatarPath,
    String? city,
    double? weight,
    double? height,
  }) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/profile/'));
    request.headers['Cookie'] = 'users_access_token=$token';
    if (fullName != null) request.fields['full_name'] = fullName;
    if (bio != null) request.fields['bio'] = bio;
    if (city != null) request.fields['city'] = city;
    if (weight != null) request.fields['weight'] = weight.toString();
    if (height != null) request.fields['height'] = height.toString();
    if (avatarPath != null) {
      request.files
          .add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }

    final response = await Api.send(request);
    await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw ApiException.fromStatus(response.statusCode);
    }
  }

  Future<Map<String, dynamic>> fetchNotifications() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse('$baseUrl/profile/profile/notifications'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<void> markNotificationsAsRead() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.post(
      Uri.parse('$baseUrl/profile/profile/notifications/mark_as_read'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  Future<Map<String, dynamic>> fetchUserApplications(
      int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final response = await Api.get(
      Uri.parse("$baseUrl/profile/user/applications?skip=$skip&limit=$limit"),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }
}
