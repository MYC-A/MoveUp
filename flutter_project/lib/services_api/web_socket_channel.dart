import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Тип текущего подключения, чтобы знать, что переоткрывать после обрыва.
enum _WsTarget { none, feed, post }

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Function(Map<String, dynamic>)? _updateCallback;

  _WsTarget _target = _WsTarget.none;
  int? _postId;

  // Управление переподключением.
  bool _manuallyClosed = false;
  int _retryAttempt = 0;
  Timer? _reconnectTimer;
  static const Duration _maxBackoff = Duration(seconds: 30);

  // Установка callback для обновлений
  void setUpdateCallback(Function(Map<String, dynamic>) callback) {
    _updateCallback = callback;
  }

  // Подключение к WebSocket для ленты новостей
  void connectToFeed() {
    _target = _WsTarget.feed;
    _postId = null;
    _manuallyClosed = false;
    _connect('${AppConfig.wsBaseUrl}/post/ws/feed', 'ленты');
  }

  // Подключение к WebSocket для отдельного поста
  void connectToPost(int postId) {
    _target = _WsTarget.post;
    _postId = postId;
    _manuallyClosed = false;
    _connect('${AppConfig.wsBaseUrl}/post/ws/post/$postId', 'поста $postId');
  }

  void _connect(String url, String label) {
    // Закрываем предыдущее соединение, чтобы не плодить подписки/каналы.
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      debugPrint('WebSocket: подключение к $label установлено');

      _subscription = _channel!.stream.listen(
        (message) {
          // Успешное сообщение — сбрасываем счётчик попыток.
          _retryAttempt = 0;
          try {
            final update = json.decode(message);
            if (update is Map<String, dynamic>) {
              _updateCallback?.call(update);
            }
          } catch (e) {
            debugPrint('WebSocket: ошибка разбора сообщения: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error ($label): $error');
          _scheduleReconnect(label);
        },
        onDone: () {
          debugPrint('WebSocket: соединение $label закрыто');
          _scheduleReconnect(label);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WebSocket: ошибка подключения к $label: $e');
      _scheduleReconnect(label);
    }
  }

  void _scheduleReconnect(String label) {
    if (_manuallyClosed || _target == _WsTarget.none) return;
    _reconnectTimer?.cancel();

    // Экспоненциальный backoff: 1s, 2s, 4s, ... до 30s.
    final seconds = (1 << _retryAttempt).clamp(1, _maxBackoff.inSeconds);
    _retryAttempt = (_retryAttempt + 1).clamp(0, 5);
    final delay = Duration(seconds: seconds);
    debugPrint('WebSocket: переподключение к $label через ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () {
      if (_manuallyClosed) return;
      switch (_target) {
        case _WsTarget.feed:
          _connect('${AppConfig.wsBaseUrl}/post/ws/feed', 'ленты');
          break;
        case _WsTarget.post:
          if (_postId != null) {
            _connect(
                '${AppConfig.wsBaseUrl}/post/ws/post/$_postId', 'поста $_postId');
          }
          break;
        case _WsTarget.none:
          break;
      }
    });
  }

  // Переключение на ленту новостей
  void switchToFeed() {
    connectToFeed();
  }

  // Переключение на пост
  void switchToPost(int postId) {
    connectToPost(postId);
  }

  // Закрытие соединения (ручное — без переподключения)
  void disconnect() {
    _manuallyClosed = true;
    _target = _WsTarget.none;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
