import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';

class ChatService {
  final String baseUrl = 'http://91.200.84.206/api'; // Базовый URL для VPS
  final String wsBaseUrl = 'ws://91.200.84.206/api'; // WebSocket URL для VPS
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  IOWebSocketChannel? _channel;

  // Получить данные чата (GET /chat/)
  Future<Map<String, dynamic>> getChatData() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/?format=json');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      return json.decode(responseBody);
    } else {
      throw Exception('Ошибка загрузки данных чата: ${response.body}');
    }
  }

  // Получить пользователей с перепиской (GET /chat/users_with_messages)
  Future<List<int>> getUsersWithMessages() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/users_with_messages');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List data = json.decode(responseBody);
      return data.cast<int>();
    } else {
      throw Exception(
          'Ошибка загрузки пользователей с перепиской: ${response.body}');
    }
  }

  // Получить сообщения с пользователем (GET /chat/messages/{user_id})
  Future<List<Map<String, dynamic>>> getMessagesBetweenUsers(int userId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/messages/$userId');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List data = json.decode(responseBody);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Ошибка загрузки сообщений: ${response.body}');
    }
  }

  // Отправить личное сообщение (POST /chat/messages)
  Future<void> sendMessage(int recipientId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/messages');
    final response = await http.post(
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
      throw Exception('Ошибка отправки сообщения: ${response.body}');
    }
  }

  // Получить сообщения группового чата (GET /chat/group_chats/{group_chat_id}/get_messages)
  Future<List<Map<String, dynamic>>> getGroupMessages(int groupChatId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/get_messages');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final List data = json.decode(utf8.decode(response.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Ошибка загрузки групповых сообщений: ${response.body}');
  }

  // Отправить сообщение в групповой чат (POST /chat/group_chats/messages)
  Future<void> sendGroupMessage(int groupChatId, String content) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats/messages');
    final response = await http.post(
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
      throw Exception('Ошибка отправки группового сообщения: ${response.body}');
    }
  }

  // Отметить групповые сообщения как прочитанные (POST /chat/group_chats/{group_chat_id}/mark_as_read)
  Future<void> markGroupMessagesAsRead(int groupChatId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/mark_as_read');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Ошибка при отметке групповых сообщений: ${response.body}');
    }
  }

  // Получить количество непрочитанных сообщений (GET /chat/unread_messages_count)
  Future<Map<String, Map<int, int>>> getUnreadMessagesCount() async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/unread_messages_count');
    final response = await http.get(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );
    if (response.statusCode == 200) {
      final Map data = json.decode(utf8.decode(response.bodyBytes));
      print("Ответ сервера unread_messages_count: $data");
      return {
        'personal':
            (data['personal'] as Map).map((k, v) => MapEntry(int.parse(k), v)),
        'group':
            (data['group'] as Map).map((k, v) => MapEntry(int.parse(k), v)),
      };
    } else {
      throw Exception(
          'Ошибка загрузки количества непрочитанных сообщений: ${response.body}');
    }
  }

  Future<void> markMessagesAsRead(int recipientId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/mark_as_read');
    print('Отправка POST $url с recipient_id: $recipientId');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: json.encode({'recipient_id': recipientId}),
    );
    print(
        'Ответ от /chat/mark_as_read: ${response.statusCode}, ${response.body}');
    if (response.statusCode != 200) {
      throw Exception(
          'Ошибка при отметке сообщений как прочитанных: ${response.body}');
    }
  }

  // Создать групповой чат (POST /chat/group_chats)
  Future<void> createGroupChat(String name, List<int> participants) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url = Uri.parse('$baseUrl/chat/group_chats');
    final response = await http.post(
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
      throw Exception('Ошибка создания группового чата: ${response.body}');
    }
  }

  // Добавить одного участника в групповой чат (POST /chat/group_chats/{group_chat_id}/add_participant)
  Future<void> addParticipantToGroupChat(int groupChatId, int userId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }
    final url =
        Uri.parse('$baseUrl/chat/group_chats/$groupChatId/add_participant');
    final response = await http.post(
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
      throw Exception('Ошибка добавления участника: ${response.body}');
    }
  }

  // Удалён метод addParticipantsToGroupChat, так как он отсутствует в документации FastAPI

  // Подключиться к WebSocket для чата (WebSocket /chat/ws/{user_id})
  void connectToChat(
      int userId, Function(Map<String, dynamic>) onMessageReceived) {
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/chat/ws/$userId'),
      );
      _channel!.stream.listen(
        (message) {
          final data = json.decode(message);
          print('Получен message: $data');
          onMessageReceived(data);
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket соединение для чата закрыто');
        },
      );
    } catch (e) {
      print('Ошибка подключения к WebSocket: $e');
    }
  }

  // Закрыть WebSocket-соединение
  void disconnect() {
    _channel?.sink.close();
  }
}
