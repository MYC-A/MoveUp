import 'package:flutter_application_1/config/app_config.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'api_exception.dart';

class LkUsersService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final storage = FlutterSecureStorage();

  // Получить данные профиля пользователя
  Future<Map<String, dynamic>> fetchUserProfile(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.get(
      Uri.parse('$baseUrl/profile/view/$userId?format=json'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить посты пользователя с пагинацией
  Future<List<dynamic>> fetchUserPosts(int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.get(
      Uri.parse('$baseUrl/profile/$userId/posts?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Подписаться на пользователя
  Future<void> followUser(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.post(
      Uri.parse('$baseUrl/friends/follow/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Отписаться от пользователя
  Future<void> unfollowUser(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.delete(
      Uri.parse('$baseUrl/friends/unfollow/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Проверка, подписан ли текущий пользователь на указанного пользователя
  Future<Map<String, dynamic>> isFollowing(int userId) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.get(
      Uri.parse('$baseUrl/friends/is_following/$userId'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить список подписчиков пользователя
  Future<Map<String, dynamic>> fetchUserFollowers(
      int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.get(
      Uri.parse('$baseUrl/profile/$userId/followers?skip=$skip&limit=$limit'),
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить список подписок пользователя
  Future<Map<String, dynamic>> fetchUserFollowing(
      int userId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    final response = await Api.get(
      Uri.parse('$baseUrl/profile/$userId/following?skip=$skip&limit=$limit'),
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
