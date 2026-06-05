import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ChatService.dart';

class ChatOverviewController extends ChangeNotifier {
  ChatOverviewController({ChatService? chatService})
      : _chatService = chatService ?? ChatService();

  static const Duration _fallbackPollingInterval = Duration(seconds: 45);
  static const Duration _realtimeRefreshDelay = Duration(milliseconds: 250);

  final ChatService _chatService;
  Timer? _fallbackTimer;
  Timer? _realtimeRefreshTimer;

  bool _isRunning = false;
  bool _overviewActive = false;
  bool _isRefreshingOverview = false;
  bool _isRefreshingUnread = false;
  bool _disposed = false;
  int? _connectedUserId;

  bool isLoadingOverview = true;
  int? currentUserId;
  List<Map<String, dynamic>> users = const [];
  List<Map<String, dynamic>> groupChats = const [];
  Map<int, int> unreadPersonalMessagesCount = const {};
  Map<int, int> unreadGroupMessagesCount = const {};

  int get totalUnreadConversations {
    final personal =
        unreadPersonalMessagesCount.values.where((value) => value > 0).length;
    final group =
        unreadGroupMessagesCount.values.where((value) => value > 0).length;
    return personal + group;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _startFallbackPolling();
    unawaited(refreshUnreadCount());
    unawaited(_connectRealtime());
  }

  void stop() {
    _isRunning = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _chatService.disconnect();
    _connectedUserId = null;
  }

  void reset() {
    stop();
    _overviewActive = false;
    currentUserId = null;
    users = const [];
    groupChats = const [];
    unreadPersonalMessagesCount = const {};
    unreadGroupMessagesCount = const {};
    isLoadingOverview = true;
    _notify();
  }

  void setOverviewActive(bool active) {
    _overviewActive = active;
    if (active) {
      unawaited(refreshOverview(
        showLoading: users.isEmpty && groupChats.isEmpty,
      ));
    }
  }

  Future<void> refreshAfterConversationChanged() async {
    await refreshUnreadCount();
    if (_overviewActive) {
      await refreshOverview(showLoading: false);
    }
  }

  Future<void> refreshOverview({bool showLoading = false}) async {
    if (_isRefreshingOverview) return;
    _isRefreshingOverview = true;

    if (showLoading) {
      isLoadingOverview = true;
      _notify();
    }

    try {
      final results = await Future.wait<dynamic>([
        _chatService.getChatData(),
        _chatService.getUnreadMessagesCount(),
      ]);

      final data = results[0] as Map<String, dynamic>;
      final count = results[1] as Map<String, Map<int, int>>;
      final user = data['user'];
      final rawUserId = user is Map ? user['id'] : null;
      currentUserId = rawUserId is num ? rawUserId.toInt() : null;
      users = List<Map<String, dynamic>>.from(
        data['users_with_messages'] as List? ?? const [],
      );
      groupChats = List<Map<String, dynamic>>.from(
        data['group_chats'] as List? ?? const [],
      );
      _setUnreadMaps(count);
      isLoadingOverview = false;
      _notify();
      unawaited(_connectRealtime());
    } catch (e) {
      debugPrint('Ошибка загрузки данных чата: $e');
      isLoadingOverview = false;
      _notify();
    } finally {
      _isRefreshingOverview = false;
    }
  }

  Future<void> refreshUnreadCount() async {
    if (_isRefreshingUnread) return;
    _isRefreshingUnread = true;

    try {
      final count = await _chatService.getUnreadMessagesCount();
      _setUnreadMaps(count);
      _notify();
      unawaited(_connectRealtime());
    } catch (e) {
      debugPrint('Ошибка загрузки количества непрочитанных сообщений: $e');
    } finally {
      _isRefreshingUnread = false;
    }
  }

  void _setUnreadMaps(Map<String, Map<int, int>> count) {
    unreadPersonalMessagesCount = Map<int, int>.from(count['personal'] ?? {});
    unreadGroupMessagesCount = Map<int, int>.from(count['group'] ?? {});
  }

  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(_fallbackPollingInterval, (_) {
      if (_overviewActive) {
        unawaited(refreshOverview(showLoading: false));
      } else {
        unawaited(refreshUnreadCount());
      }
    });
  }

  Future<void> _connectRealtime() async {
    if (!_isRunning) return;
    try {
      final cachedUserId = await _chatService.getCachedCurrentUserId();
      final userId = cachedUserId ?? currentUserId;
      if (!_isRunning || userId == null) return;
      currentUserId = userId;
      if (_connectedUserId == userId) return;
      _connectedUserId = userId;
      _chatService.connectToChat(userId, _onWebSocketMessage);
    } catch (e) {
      debugPrint('Ошибка подключения realtime чата: $e');
    }
  }

  void _onWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    if (type != 'personal' && type != 'group' && type != 'message_deleted') {
      return;
    }

    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(_realtimeRefreshDelay, () {
      if (_overviewActive) {
        unawaited(refreshOverview(showLoading: false));
      } else {
        unawaited(refreshUnreadCount());
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
