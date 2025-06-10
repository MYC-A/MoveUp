import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';

class WebSocketService {
  WebSocketChannel? _channel; // Используем nullable тип
  Function(Map<String, dynamic>)? _updateCallback;

  // Установка callback для обновлений
  void setUpdateCallback(Function(Map<String, dynamic>) callback) {
    _updateCallback = callback;
  }

  // Подключение к WebSocket для ленты новостей
  void connectToFeed() {
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://91.200.84.206/api/post/ws/feed'),
      );

      print('Подключение к WebSocket для ленты установлено');

      _channel!.stream.listen(
        // Используем !, так как _channel инициализирован
        (message) {
          print('Получено сообщение: $message');
          final update = json.decode(message);
          _updateCallback?.call(update); // Вызов callback
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket соединение для ленты закрыто');
        },
      );
    } catch (e) {
      print('Ошибка подключения к WebSocket: $e');
    }
  }

  // Подключение к WebSocket для отдельного поста
  void connectToPost(int postId) {
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://91.200.84.206/api/post/ws/post/$postId'),
      );

      print('Подключение к WebSocket для поста $postId установлено');

      _channel!.stream.listen(
        // Используем !, так как _channel инициализирован
        (message) {
          print('Получено сообщение: $message');
          final update = json.decode(message);
          _updateCallback?.call(update);
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket соединение для поста закрыто');
        },
      );
    } catch (e) {
      print('Ошибка подключения к WebSocket: $e');
    }
  }

  // Переключение на ленту новостей
  void switchToFeed() {
    disconnect(); // Закрываем текущее соединение
    connectToFeed(); // Открываем соединение для ленты
  }

  // Переключение на пост
  void switchToPost(int postId) {
    disconnect(); // Закрываем текущее соединение
    connectToPost(postId); // Открываем соединение для поста
  }

  // Закрытие соединения
  void disconnect() {
    _channel?.sink.close(); // Используем null-aware оператор
  }
}
