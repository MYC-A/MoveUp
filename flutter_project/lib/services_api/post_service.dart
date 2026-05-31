import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models_api/post.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'geocoding_service.dart';

class PostService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final GeocodingService _geocoding = GeocodingService();

  ApiException _noToken() =>
      ApiException(ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');

  // Получить ленту постов
  Future<List<Post>> getFeed(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/feed?skip=$skip&limit=$limit');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);

      final List<dynamic> data = json.decode(responseBody);
      debugPrint('Лента загружена: ${data.length} постов');
      return data.map((json) => Post.fromJson(json)).toList();
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Лайкнуть/снять лайк (toggle). Возвращает актуальное состояние с сервера.
  Future<({int likesCount, bool liked})> likePost(int postId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/posts/$postId/like');
    final response = await Api.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
    final data = json.decode(utf8.decode(response.bodyBytes));
    return (
      likesCount: (data['likes_count'] as num?)?.toInt() ?? 0,
      liked: data['liked'] == true,
    );
  }

  // Удалить пост (только свой)
  Future<void> deletePost(int postId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/posts/$postId');
    final response = await Api.delete(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Удалить комментарий (автор комментария или владелец поста)
  Future<void> deleteComment(int postId, int commentId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/posts/$postId/comments/$commentId');
    final response = await Api.delete(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Добавить комментарий
  Future<Comment> addComment(int postId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/posts/$postId/create_comment');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'content': content}),
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final decoded = json.decode(responseBody);
      final dynamic commentJson =
          decoded is Map<String, dynamic> && decoded['comment'] is Map
              ? decoded['comment']
              : decoded;

      if (commentJson is Map<String, dynamic>) {
        return Comment.fromJson(commentJson);
      }

      if (commentJson is Map) {
        return Comment.fromJson(Map<String, dynamic>.from(commentJson));
      }

      throw ApiException(ApiErrorKind.unknown,
          'Некорректный ответ сервера при добавлении комментария');
    }

    throw ApiException.fromResponse(response);
  }

  // Получить комментарии для поста с пагинацией
  Future<List<Comment>> getComments(int postId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse(
        '$baseUrl/post/posts/$postId/comments?skip=$skip&limit=$limit');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = json.decode(responseBody);
      return data.map((json) => Comment.fromJson(json)).toList();
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Загрузить данные поста по его postId
  Future<Post> getPostDetails(int postId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/post/posts/$postId/details');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final Map<String, dynamic> data = json.decode(responseBody);
      return Post.fromJson(data['post']);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить ID текущего пользователя
  Future<int> getCurrentUserId() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) throw _noToken();

    final url = Uri.parse('$baseUrl/auth/current_user');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as int;
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Создание поста
// В PostService.dart
  Future<void> createPost({
    required String content,
    required double distance,
    required int duration,
    required List<Map<String, dynamic>> routeData,
    required List<String> photoPaths,
  }) async {
    try {
      debugPrint(
          'Создание поста: photos=${photoPaths.length}, routePoints=${routeData.length}');
      final token = await storage.read(key: 'access_token');
      if (token == null) throw _noToken();

      // Определяем город старта по первой точке маршрута (необязательно).
      String? city;
      if (routeData.isNotEmpty) {
        final first = routeData.first;
        final lat = (first['latitude'] as num?)?.toDouble();
        final lon = (first['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          city = await _geocoding.reverseCity(lat, lon);
        }
      }

      final postData = {
        'content': content,
        'distance': distance,
        'duration': duration,
        if (city != null && city.isNotEmpty) 'city': city,
        'route_data': routeData,
      };

      Uri url = Uri.parse('$baseUrl/post/posts_create');

      Future<http.MultipartRequest> createRequest(Uri uri) async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Cookie'] = 'users_access_token=$token';
        request.fields['post'] = json.encode(postData);

        for (final photoPath in photoPaths) {
          final file = await http.MultipartFile.fromPath('photos', photoPath);
          request.files.add(file);
        }

        return request;
      }

      var request = await createRequest(url);
      var response = await Api.send(request);
      await response.stream.bytesToString();
      debugPrint('Создание поста завершено со статусом ${response.statusCode}');

      // Обработка перенаправления
      if (response.statusCode == 307) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          url = Uri.parse(redirectUrl);
          final newRequest = await createRequest(url); // ← новое создание!
          response = await Api.send(newRequest);
          await response.stream.bytesToString();
          debugPrint(
              'Создание поста после перенаправления: ${response.statusCode}');
        }
      }

      if (response.statusCode != 200) {
        throw ApiException.fromStatus(response.statusCode);
      }
    } catch (e) {
      debugPrint('Ошибка в createPost: $e');
      throw ApiException.fromError(e);
    }
  }
}

class Comment {
  final int id;
  final int userId;
  final String content;
  final DateTime createdAt;
  final String userFullName;
  final String? userAvatarUrl;

  Comment({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.userFullName,
    this.userAvatarUrl,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final avatarUrl = user['avatar_url'] as String?;

    return Comment(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      content: json['content'] ?? '',
      createdAt:
          DateTime.parse(json['created_at'] ?? DateTime.now().toString()),
      userFullName: user['full_name'] ?? user['username'] ?? 'Пользователь',
      userAvatarUrl:
          avatarUrl != null ? AppConfig.normalizeMediaUrl(avatarUrl) : null,
    );
  }
}
