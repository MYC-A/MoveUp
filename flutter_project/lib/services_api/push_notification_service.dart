import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/config/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = AppFirebaseOptions.currentPlatform;
  if (options == null) {
    debugPrint('PUSH BG: Firebase options are not configured');
    return;
  }

  try {
    debugPrint(
      'PUSH BG: message received id=${message.messageId ?? '<no-id>'} '
      'type=${message.data['type']}',
    );
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
      debugPrint('PUSH BG: Firebase.initializeApp ok');
    }
    // FCM-сообщения теперь содержат поле notification, поэтому ОС показывает
    // уведомление в трее автоматически (background/killed). Вызывать
    // showRemoteMessage здесь не нужно — это создало бы дублирующее уведомление.
  } catch (e) {
    debugPrint('Ошибка фоновой инициализации Firebase: $e');
  }
}

class PushNotificationService {
  static const String _channelId = 'moveup_messages';
  static const String _channelName = 'Сообщения';
  static const String _groupKey = 'moveup.chat.messages';
  static const int _maxInboxLines = 3;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static final Map<String, List<String>> _conversationLines = {};
  static final Map<String, int> _conversationTotal = {};
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static bool Function(Map<String, dynamic> data)?
      notificationNavigationHandler;

  static bool _initialized = false;
  static bool _initializing = false;
  static bool _localNotificationsReady = false;
  static String? _activeConversationKey;
  static Map<String, dynamic>? _pendingNotificationData;

  static bool get isInitialized => _initialized;

  static void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('PUSH: $message');
    }
  }

  static String _shortToken(String? token) {
    if (token == null || token.isEmpty) return '<empty>';
    if (token.length <= 12) return token;
    return '${token.substring(0, 6)}...${token.substring(token.length - 6)}';
  }

  static String _messageSummary(RemoteMessage message) {
    return 'id=${message.messageId ?? '<no-id>'} '
        'type=${message.data['type']} '
        'conversation=${message.data['conversation_type']}:${message.data['conversation_id']} '
        'hasNotification=${message.notification != null}';
  }

  static Future<void> initialize() async {
    if (_initialized) {
      _debugLog('initialize skipped: already initialized');
      return;
    }
    if (_initializing) {
      _debugLog('initialize skipped: initialization is already running');
      return;
    }
    _initializing = true;
    if (!_isSupportedPlatform) {
      _debugLog('disabled: unsupported platform=$defaultTargetPlatform');
      _initializing = false;
      return;
    }

    final options = AppFirebaseOptions.currentPlatform;
    if (options == null) {
      _debugLog(
        'disabled: Firebase dart-defines are not configured; '
        'missing=${AppFirebaseOptions.missingConfigKeys.join(', ')}',
      );
      _initializing = false;
      return;
    }

    try {
      _debugLog(
        'initialize start platform=$_platformName '
        'project=${AppFirebaseOptions.projectId} '
        'sender=${AppFirebaseOptions.messagingSenderId}',
      );
      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
        _debugLog('Firebase.initializeApp ok');
      } else {
        _debugLog('Firebase already initialized apps=${Firebase.apps.length}');
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _initializeLocalNotifications();
      await _requestPermissions();

      FirebaseMessaging.onMessage.listen(showRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _debugLog('initial message found: ${_messageSummary(initialMessage)}');
        _handleMessageTap(initialMessage);
      } else {
        _debugLog('initial message: none');
      }

      _initialized = true;
      _debugLog('initialize ok; registering current device token');
      await registerCurrentDeviceToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _debugLog('token refresh: ${_shortToken(token)}');
        unawaited(_registerTokenOnBackend(token));
      });
    } catch (e, stackTrace) {
      _debugLog('initialize failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _initializing = false;
    }
  }

  static void setActiveConversation({
    required String conversationType,
    required int conversationId,
  }) {
    final key = _conversationKey(conversationType, conversationId);
    _activeConversationKey = key;
    unawaited(_clearConversationNotification(key));
  }

  static void clearActiveConversation({
    required String conversationType,
    required int conversationId,
  }) {
    final key = _conversationKey(conversationType, conversationId);
    if (_activeConversationKey == key) {
      _activeConversationKey = null;
    }
  }

  static Future<void> registerCurrentDeviceToken() async {
    if (!_initialized) {
      _debugLog(
        'register token requested before push init; trying initialize. '
        'firebaseConfigured=${AppFirebaseOptions.isConfigured} '
        'missing=${AppFirebaseOptions.missingConfigKeys.join(', ')}',
      );
      await initialize();
      if (!_initialized) {
        _debugLog('register token skipped: service is still not initialized');
        return;
      }
    }

    try {
      _debugLog('requesting FCM token');
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        _debugLog('FCM token is empty');
        return;
      }
      _debugLog('FCM token received: ${_shortToken(token)}');
      await _registerTokenOnBackend(token);
    } catch (e, stackTrace) {
      _debugLog('failed to get FCM token: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> unregisterCurrentDeviceToken() async {
    if (!_initialized) {
      _debugLog('unregister token skipped: service is not initialized');
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      final accessToken = await _storage.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        _debugLog('unregister token skipped: FCM token is empty');
        return;
      }
      if (accessToken == null) {
        _debugLog(
          'unregister token skipped: no access token for ${_shortToken(token)}',
        );
        return;
      }

      _debugLog('unregister token on backend: ${_shortToken(token)}');
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/push/tokens/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'users_access_token=$accessToken',
        },
        body: json.encode({'token': token}),
      );

      _debugLog(
        'unregister token response: status=${response.statusCode} '
        'body=${_truncate(response.body, maxLength: 180)}',
      );
    } catch (e, stackTrace) {
      _debugLog('failed to unregister token: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void openPendingNotificationIfAny() {
    _openPendingNotification();
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) {
      _debugLog('local notifications already initialized');
      return;
    }

    _debugLog('initializing local notifications channel=$_channelId');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationPayload(response.payload);
      },
    );

    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _debugLog('app launched from local notification payload');
      _handleNotificationPayload(launchDetails?.notificationResponse?.payload);
    }

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Новые личные и групповые сообщения',
      importance: Importance.high,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _localNotificationsReady = true;
    _debugLog('local notifications ready channel=$_channelId');
  }

  static Future<void> _requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _debugLog(
      'FCM permission: authorization=${settings.authorizationStatus} '
      'alert=${settings.alert} badge=${settings.badge} sound=${settings.sound}',
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    final androidPermission = await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _debugLog('Android POST_NOTIFICATIONS permission=$androidPermission');
  }

  static Future<void> _registerTokenOnBackend(String token) async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      _debugLog(
        'backend token registration skipped: no access token for ${_shortToken(token)}',
      );
      return;
    }

    try {
      final url = Uri.parse('${AppConfig.apiBaseUrl}/push/tokens');
      _debugLog(
        'register token on backend: url=$url platform=$_platformName '
        'token=${_shortToken(token)}',
      );
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'users_access_token=$accessToken',
        },
        body: json.encode({
          'token': token,
          'platform': _platformName,
        }),
      );

      _debugLog(
        'register token response: status=${response.statusCode} '
        'body=${_truncate(response.body, maxLength: 180)}',
      );
    } catch (e, stackTrace) {
      _debugLog('failed to send token to backend: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> showRemoteMessage(RemoteMessage message) async {
    _debugLog('foreground message received: ${_messageSummary(message)}');
    await _initializeLocalNotifications();

    final data = message.data;
    final messageType = data['type']?.toString();
    if (messageType == 'push_debug') {
      await _showSimpleLocalNotification(
        message: message,
        data: data,
        key: 'push_debug:${data['debug_at'] ?? message.messageId ?? DateTime.now().microsecondsSinceEpoch}',
        fallbackTitle: 'MoveUp test push',
      );
      return;
    }

    if (messageType != 'chat_message') {
      _debugLog('foreground message ignored: unsupported type=$messageType');
      return;
    }

    final conversationType = data['conversation_type'] ?? 'personal';
    final conversationId =
        int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationId == null) {
      _debugLog('foreground message ignored: conversation_id is missing');
      return;
    }

    final key = _conversationKey(conversationType, conversationId);
    if (_activeConversationKey == key) {
      _debugLog('foreground message ignored: active conversation=$key');
      return;
    }

    final title = message.notification?.title ??
        data['title']?.toString() ??
        'Новое сообщение';
    final body =
        _truncate(message.notification?.body ?? data['body']?.toString() ?? '');
    final unreadCount =
        int.tryParse(data['unread_count']?.toString() ?? '') ?? 1;

    final lines = await _loadConversationLines(key);
    lines.add(body);
    if (lines.length > _maxInboxLines) {
      lines.removeRange(0, lines.length - _maxInboxLines);
    }

    final totalInCurrentSession = await _loadConversationTotal(key) + 1;
    await _storeConversationState(key, lines, totalInCurrentSession);
    final hiddenCount = totalInCurrentSession - lines.length;
    final style = InboxStyleInformation(
      List<String>.from(lines),
      contentTitle: title,
      summaryText: hiddenCount > 0 ? 'Еще $hiddenCount сообщ.' : null,
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Новые личные и групповые сообщения',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: style,
      groupKey: _groupKey,
      number: unreadCount,
      onlyAlertOnce: false,
    );

    await _localNotifications.show(
      _notificationIdFor(key),
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: json.encode(data),
    );
    _debugLog(
      'local notification shown: key=$key id=${_notificationIdFor(key)} '
      'unread=$unreadCount title=$title',
    );
  }

  static Future<void> _showSimpleLocalNotification({
    required RemoteMessage message,
    required Map<String, dynamic> data,
    required String key,
    required String fallbackTitle,
  }) async {
    final title = message.notification?.title ??
        data['title']?.toString() ??
        fallbackTitle;
    final body = _truncate(
      message.notification?.body ?? data['body']?.toString() ?? '',
    );

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Диагностические и системные уведомления MoveUp',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _localNotifications.show(
      _notificationIdFor(key),
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: json.encode(data),
    );
    _debugLog(
      'simple local notification shown: key=$key id=${_notificationIdFor(key)} '
      'type=${data['type']} title=$title',
    );
  }

  static Future<List<String>> _loadConversationLines(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('push_lines_$key');
      if (stored != null) {
        _conversationLines[key] = List<String>.from(stored);
      }
    } catch (e) {
      debugPrint('Ошибка чтения push-lines: $e');
    }

    return List<String>.from(
      _conversationLines.putIfAbsent(key, () => <String>[]),
    );
  }

  static Future<int> _loadConversationTotal(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt('push_total_$key');
      if (stored != null) {
        _conversationTotal[key] = stored;
      }
    } catch (e) {
      debugPrint('Ошибка чтения push-total: $e');
    }

    return _conversationTotal[key] ?? 0;
  }

  static Future<void> _storeConversationState(
    String key,
    List<String> lines,
    int total,
  ) async {
    _conversationLines[key] = List<String>.from(lines);
    _conversationTotal[key] = total;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('push_lines_$key', lines);
      await prefs.setInt('push_total_$key', total);
    } catch (e) {
      debugPrint('Ошибка сохранения push-state: $e');
    }
  }

  static Future<void> _clearConversationNotification(String key) async {
    _conversationLines.remove(key);
    _conversationTotal.remove(key);

    try {
      await _localNotifications.cancel(_notificationIdFor(key));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('push_lines_$key');
      await prefs.remove('push_total_$key');
    } catch (e) {
      debugPrint('Ошибка очистки push-state: $e');
    }
  }

  static void _handleMessageTap(RemoteMessage message) {
    _debugLog('FCM notification opened: ${_messageSummary(message)}');
    _handleNotificationData(message.data);
  }

  static void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      _debugLog('local notification payload ignored: empty');
      return;
    }

    try {
      _debugLog('local notification payload received: $payload');
      final decoded = json.decode(payload);
      if (decoded is Map<String, dynamic>) {
        _handleNotificationData(decoded);
      } else if (decoded is Map) {
        _handleNotificationData(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (e, stackTrace) {
      _debugLog('failed to parse notification payload: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void _handleNotificationData(Map<String, dynamic> data) {
    if (data['type'] != 'chat_message') {
      _debugLog('notification data ignored: unsupported type=${data['type']}');
      return;
    }

    _debugLog(
      'notification data queued: '
      '${data['conversation_type']}:${data['conversation_id']}',
    );
    _pendingNotificationData = Map<String, dynamic>.from(data);
    _openPendingNotification();
  }

  static void _openPendingNotification() {
    final data = _pendingNotificationData;
    final handler = notificationNavigationHandler;
    if (data == null) {
      _debugLog('open pending notification skipped: no pending data');
      return;
    }
    if (handler == null) {
      _debugLog('open pending notification delayed: navigation handler is null');
      return;
    }

    final didOpen = handler(data);
    _debugLog('open pending notification result=$didOpen data=$data');
    if (didOpen) {
      _pendingNotificationData = null;
    }
  }

  static bool get _isSupportedPlatform {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String get _platformName {
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }

  static String _conversationKey(String conversationType, int conversationId) {
    return '$conversationType:$conversationId';
  }

  static String _truncate(String value, {int maxLength = 120}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1)}...';
  }

  static int _notificationIdFor(String key) {
    var hash = 0;
    for (final codeUnit in key.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
