import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LkUsersService {
  final String baseUrl =
      'http://91.200.84.206/api'; // Для Android-эмулятора // Замените на ваш URL
  final storage = FlutterSecureStorage();

  // Получить данные профиля пользователя
  Future<Map<String, dynamic>> fetchUserProfile(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/profile/view/$userId?format=json'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Ошибка при загрузке профиля: ${response.statusCode}');
    }
  }

  // Получить посты пользователя с пагинацией
  Future<List<dynamic>> fetchUserPosts(int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/profile/$userId/posts?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Ошибка при загрузке постов: ${response.statusCode}');
    }
  }

  // Подписаться на пользователя
  Future<void> followUser(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.post(
      Uri.parse('$baseUrl/friends/follow/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при подписке: ${response.statusCode}');
    }
  }

  // Отписаться от пользователя
  Future<void> unfollowUser(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.delete(
      Uri.parse('$baseUrl/friends/unfollow/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при отписке: ${response.statusCode}');
    }
  }

  // Проверка, подписан ли текущий пользователь на указанного пользователя
  Future<Map<String, dynamic>> isFollowing(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/friends/is_following/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception(
          'Ошибка при проверке статуса подписки: ${response.statusCode}');
    }
  }

  // Получить список подписчиков пользователя
  Future<Map<String, dynamic>> fetchUserFollowers(
      int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/profile/$userId/followers?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception(
          'Ошибка при загрузке подписчиков: ${response.statusCode}');
    }
  }

  // Получить список подписок пользователя
  Future<Map<String, dynamic>> fetchUserFollowing(
      int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/profile/$userId/following?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Ошибка при загрузке подписок: ${response.statusCode}');
    }
  }
}
