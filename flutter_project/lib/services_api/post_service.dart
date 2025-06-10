import 'dart:convert';
import 'package:flutter_application_1/models/RunningRoute.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models_api/post.dart';

class PostService {
  final String baseUrl =
      'http://91.200.84.206/api'; // Для Android-эмулятора // Замените на ваш URL
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // Получить ленту постов
  Future<List<Post>> getFeed(int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/post/feed?skip=$skip&limit=$limit');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);

      final List<dynamic> data = json.decode(responseBody);
      print('Тело ответа: ${responseBody}');
      return data.map((json) => Post.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка загрузки ленты: ${response.body}');
    }
  }

  // Лайкнуть пост
  Future<void> likePost(int postId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/post/posts/$postId/like');
    final response = await http.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка лайка: ${response.body}');
    }
  }

  // Добавить комментарий
  Future<void> addComment(int postId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/post/posts/$postId/create_comment');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'content': content}),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка добавления комментария: ${response.body}');
    }
  }

  // Получить комментарии для поста с пагинацией
  Future<List<Comment>> getComments(int postId, int skip, int limit) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse(
        '$baseUrl/post/posts/$postId/comments?skip=$skip&limit=$limit');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = json.decode(responseBody);
      return data.map((json) => Comment.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка загрузки комментариев: ${response.body}');
    }
  }

  // Загрузить данные поста по его postId
  Future<Post> getPostDetails(int postId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/post/posts/$postId/details');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final Map<String, dynamic> data = json.decode(responseBody);
      return Post.fromJson(data['post']);
    } else {
      throw Exception('Ошибка загрузки деталей поста: ${response.body}');
    }
  }

  // Получить ID текущего пользователя
  Future<int> getCurrentUserId() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/auth/current_user');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as int;
    } else {
      throw Exception(
          'Ошибка загрузки текущего пользователя: ${response.body}');
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
      print('Начало createPost: content=$content, photos=${photoPaths.length}');
      final token = await storage.read(key: 'access_token');
      print('Токен: ${token != null ? 'найден' : 'не найден'}');
      if (token == null) {
        throw Exception('Токен не найден');
      }

      final postData = {
        'content': content,
        'distance': distance,
        'duration': duration,
        'route_data': routeData,
      };
      print('postData: $postData');

      Uri url = Uri.parse('$baseUrl/post/posts_create');
      print('Создание запроса на: $url');

      Future<http.MultipartRequest> createRequest(Uri uri) async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Cookie'] = 'users_access_token=$token';
        request.fields['post'] = json.encode(postData);
        print('Добавлены поля: ${request.fields}');

        for (final photoPath in photoPaths) {
          print('Добавление файла: $photoPath');
          final file = await http.MultipartFile.fromPath('photos', photoPath);
          request.files.add(file);
        }

        return request;
      }

      var request = await createRequest(url);
      print('Отправка запроса...');
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      print('Ответ сервера: ${response.statusCode}, тело: $responseBody');

      // Обработка перенаправления
      if (response.statusCode == 307) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          print('Перенаправление на: $redirectUrl');
          url = Uri.parse(redirectUrl);
          final newRequest = await createRequest(url); // ← новое создание!
          response = await newRequest.send();
          responseBody = await response.stream.bytesToString();
          print(
              'Ответ сервера после перенаправления: ${response.statusCode}, тело: $responseBody');
        }
      }

      if (response.statusCode != 200) {
        throw Exception('Ошибка создания поста: $responseBody');
      }
    } catch (e, stackTrace) {
      print('Ошибка в createPost: $e, StackTrace: $stackTrace');
      rethrow;
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
    return Comment(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      content: json['content'] ?? '',
      createdAt:
          DateTime.parse(json['created_at'] ?? DateTime.now().toString()),
      userFullName: json['user']['username'] ?? 'Пользователь',
      userAvatarUrl: json['user']['avatar_url'] != null
          ? json['user']['avatar_url']
              .replaceAll('localhost:9000', '91.200.84.206/minio')
          : null,
    );
  }
}
