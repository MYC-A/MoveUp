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
  if (options == null) return;

  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    // FCM-сообщения теперь содержат поле notification, поэтому ОС показывает
    // уведомление в трее автоматически (background/killed). Вызывать
    // showRemoteMessage здесь не нужно — это создало бы дублирующее уведомление.
  } catch (e) {
    debugPrint('Failed to initialize Firebase in background handler: $e');
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

  static Future<void> initialize() async {
    if (_initialized || _initializing) return;
    if (!_isSupportedPlatform) {
      debugPrint('Push disabled: unsupported platform');
      return;
    }

    final options = AppFirebaseOptions.currentPlatform;
    if (options == null) {
      final missingKeys = AppFirebaseOptions.missingConfigKeys.join(', ');
      debugPrint(
        'Push disabled: Firebase dart-defines are not configured; '
        'missing=$missingKeys',
      );
      return;
    }

    try {
      _initializing = true;
      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _initializeLocalNotifications();
      await _requestPermissions();

      FirebaseMessaging.onMessage.listen(showRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      _initialized = true;
      await registerCurrentDeviceToken();
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerTokenOnBackend);
    } catch (e) {
      debugPrint('Failed to initialize push notifications: $e');
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
      final missingKeys = AppFirebaseOptions.missingConfigKeys.join(', ');
      debugPrint(
        'Push token registration requested before initialization; '
        'trying to initialize. firebaseConfigured=${AppFirebaseOptions.isConfigured} '
        'missing=$missingKeys',
      );
      await initialize();
    }

    if (!_initialized) {
      debugPrint('Push token registration skipped: service is not initialized');
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('FCM token received; registering on backend');
        await _registerTokenOnBackend(token);
      } else {
        debugPrint('FCM token is empty; backend registration skipped');
      }
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }
  }

  static Future<void> unregisterCurrentDeviceToken() async {
    if (!_initialized) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      final accessToken = await _storage.read(key: 'access_token');
      if (token == null || token.isEmpty || accessToken == null) return;

      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/push/tokens/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'users_access_token=$accessToken',
        },
        body: json.encode({'token': token}),
      );

      if (response.statusCode >= 400) {
        debugPrint('Failed to delete push token: ${response.body}');
      }
    } catch (e) {
      debugPrint('Failed to unregister push token: $e');
    }
  }

  static void openPendingNotificationIfAny() {
    _openPendingNotification();
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) return;

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
  }

  static Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _registerTokenOnBackend(String token) async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) {
      debugPrint(
        'FCM token backend registration skipped: access token is missing',
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/push/tokens'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'users_access_token=$accessToken',
        },
        body: json.encode({
          'token': token,
          'platform': _platformName,
        }),
      );

      if (response.statusCode >= 400) {
        debugPrint('Failed to register push token: ${response.body}');
      } else {
        debugPrint('FCM token registered on backend');
      }
    } catch (e) {
      debugPrint('Failed to send push token to backend: $e');
    }
  }

  static Future<void> showRemoteMessage(RemoteMessage message) async {
    await _initializeLocalNotifications();

    final data = message.data;
    if (data['type'] != 'chat_message') return;

    final conversationType = data['conversation_type'] ?? 'personal';
    final conversationId =
        int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationId == null) return;

    final key = _conversationKey(conversationType, conversationId);
    if (_activeConversationKey == key) return;

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
  }

  static Future<List<String>> _loadConversationLines(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('push_lines_$key');
      if (stored != null) {
        _conversationLines[key] = List<String>.from(stored);
      }
    } catch (e) {
      debugPrint('Failed to read push lines: $e');
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
      debugPrint('Failed to read push total: $e');
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
      debugPrint('Failed to save push state: $e');
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
      debugPrint('Failed to clear push state: $e');
    }
  }

  static void _handleMessageTap(RemoteMessage message) {
    debugPrint('FCM notification opened: ${message.data}');
    _handleNotificationData(message.data);
  }

  static void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = json.decode(payload);
      if (decoded is Map<String, dynamic>) {
        _handleNotificationData(decoded);
      } else if (decoded is Map) {
        _handleNotificationData(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (e) {
      debugPrint('Failed to parse push notification payload: $e');
    }
  }

  static void _handleNotificationData(Map<String, dynamic> data) {
    if (data['type'] != 'chat_message') return;

    _pendingNotificationData = Map<String, dynamic>.from(data);
    _openPendingNotification();
  }

  static void _openPendingNotification() {
    final data = _pendingNotificationData;
    final handler = notificationNavigationHandler;
    if (data == null || handler == null) return;

    final didOpen = handler(data);
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
