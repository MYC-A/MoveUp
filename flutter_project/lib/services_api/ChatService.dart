import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';

import 'api_client.dart';
import 'api_exception.dart';

class ChatService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final String wsBaseUrl = AppConfig.wsBaseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  IOWebSocketChannel? _channel;
  StreamSubscription? _chatSubscription;

  // Управление переподключением чата.
  int? _chatUserId;
  Function(Map<String, dynamic>)? _chatCallback;
  bool _chatManuallyClosed = false;
  int _chatRetryAttempt = 0;
  Timer? _chatReconnectTimer;

  Future<int?> getCachedCurrentUserId() async {
    final cachedUserId = await storage.read(key: 'user_id');
    final parsedCachedUserId =
        cachedUserId == null ? null : int.tryParse(cachedUserId);
    if (parsedCachedUserId != null) {
      return parsedCachedUserId;
    }

    final data = await getChatData();
    final userId = data['user']?['id'];
    if (userId is int) {
      await storage.write(key: 'user_id', value: userId.toString());
      return userId;
    }
    return null;
  }

  // Получить данные чата (GET /chat/)
  Future<Map<String, dynamic>> getChatData() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/?format=json');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить пользователей с перепиской (GET /chat/users_with_messages)
  Future<List<int>> getUsersWithMessages() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/users_with_messages');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List data = json.decode(responseBody);
      return data.cast<int>();
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить сообщения с пользователем (GET /chat/messages/{user_id})
  Future<List<Map<String, dynamic>>> getMessagesBetweenUsers(
    int userId, {
    int limit = 30,
    int? beforeId,
  }) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/messages/$userId').replace(
      queryParameters: {
        'limit': limit.toString(),
        if (beforeId != null) 'before_id': beforeId.toString(),
      },
    );
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List data = json.decode(responseBody);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  // Отправить личное сообщение (POST /chat/messages)
  Future<void> sendMessage(int recipientId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/messages');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({
        'recipient_id': recipientId,
        'content': content,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить сообщения группового чата (GET /chat/group_chats/{group_chat_id}/get_messages)
  Future<List<Map<String, dynamic>>> getGroupMessages(
    int groupChatId, {
    int limit = 30,
    int? beforeId,
  }) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats/$groupChatId/get_messages')
        .replace(
      queryParameters: {
        'limit': limit.toString(),
        if (beforeId != null) 'before_id': beforeId.toString(),
      },
    );
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final List data = json.decode(utf8.decode(response.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw ApiException.fromResponse(response);
  }

  // Отправить сообщение в групповой чат (POST /chat/group_chats/messages)
  Future<void> sendGroupMessage(int groupChatId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats/messages');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({
        'group_chat_id': groupChatId,
        'content': content,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Отметить групповые сообщения как прочитанные (POST /chat/group_chats/{group_chat_id}/mark_as_read)
  Future<void> markGroupMessagesAsRead(int groupChatId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/mark_as_read');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Получить количество непрочитанных сообщений (GET /chat/unread_messages_count)
  Future<Map<String, Map<int, int>>> getUnreadMessagesCount() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/unread_messages_count');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final Map data = json.decode(utf8.decode(response.bodyBytes));
      debugPrint('Количество непрочитанных сообщений загружено');
      return {
        'personal':
            (data['personal'] as Map).map((k, v) => MapEntry(int.parse(k), v)),
        'group':
            (data['group'] as Map).map((k, v) => MapEntry(int.parse(k), v)),
      };
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<void> markMessagesAsRead(int recipientId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/mark_as_read');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'recipient_id': recipientId}),
    );
    debugPrint('markMessagesAsRead status: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Создать групповой чат (POST /chat/group_chats)
  Future<void> createGroupChat(String name, List<int> participants) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({
        'name': name,
        'participants': participants,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Добавить одного участника в групповой чат (POST /chat/group_chats/{group_chat_id}/add_participant)
  Future<void> addParticipantToGroupChat(int groupChatId, int userId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/add_participant');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({
        'user_id': userId,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Список участников группового чата (GET /chat/group_chats/{id}/participants)
  Future<List<Map<String, dynamic>>> getGroupChatParticipants(
      int groupChatId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/participants');
    final response = await Api.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      return List<Map<String, dynamic>>.from(json.decode(body));
    }
    throw ApiException.fromResponse(response);
  }

  // Покинуть групповой чат (POST /chat/group_chats/{group_chat_id}/leave)
  Future<void> leaveGroupChat(int groupChatId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats/$groupChatId/leave');
    final response = await Api.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Удалён метод addParticipantsToGroupChat, так как он отсутствует в документации FastAPI

  // Подключиться к WebSocket для чата (WebSocket /chat/ws/{user_id})
  void connectToChat(
      int userId, Function(Map<String, dynamic>) onMessageReceived) {
    _chatUserId = userId;
    _chatCallback = onMessageReceived;
    _chatManuallyClosed = false;
    _openChatChannel();
  }

  void _openChatChannel() {
    // Закрываем предыдущее соединение перед открытием нового.
    _chatReconnectTimer?.cancel();
    _chatSubscription?.cancel();
    _channel?.sink.close();

    final userId = _chatUserId;
    if (userId == null) return;

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/chat/ws/$userId'),
      );
      _chatSubscription = _channel!.stream.listen(
        (message) {
          _chatRetryAttempt = 0;
          try {
            final data = json.decode(message);
            if (data is Map<String, dynamic>) {
              debugPrint(
                  'Получено WebSocket-сообщение чата: ${data['type'] ?? 'unknown'}');
              _chatCallback?.call(data);
            }
          } catch (e) {
            debugPrint('WebSocket: ошибка разбора сообщения чата: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error (чат): $error');
          _scheduleChatReconnect();
        },
        onDone: () {
          debugPrint('WebSocket соединение для чата закрыто');
          _scheduleChatReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Ошибка подключения к WebSocket: $e');
      _scheduleChatReconnect();
    }
  }

  void _scheduleChatReconnect() {
    if (_chatManuallyClosed || _chatUserId == null) return;
    _chatReconnectTimer?.cancel();

    final seconds = (1 << _chatRetryAttempt).clamp(1, 30);
    _chatRetryAttempt = (_chatRetryAttempt + 1).clamp(0, 5);
    debugPrint('WebSocket: переподключение к чату через ${seconds}s');

    _chatReconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_chatManuallyClosed) _openChatChannel();
    });
  }

  // Закрыть WebSocket-соединение (ручное — без переподключения)
  void disconnect() {
    _chatManuallyClosed = true;
    _chatReconnectTimer?.cancel();
    _chatSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
