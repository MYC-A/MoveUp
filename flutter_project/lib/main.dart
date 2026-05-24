import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Добавляем для локализации
import 'package:flutter_application_1/screens/LiveTrackerScreen.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/screens_api/event_screen.dart';
import 'package:flutter_application_1/screens_api/feed_screen.dart';
import 'package:flutter_application_1/screens_api/login_screen.dart';
import 'package:flutter_application_1/screens_api/profile_screen.dart';
import 'package:flutter_application_1/screens_api/register_screen.dart';
import 'package:flutter_application_1/screens/SplashScreen.dart';
import 'package:flutter_application_1/services_api/auth_service.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  Intl.defaultLocale = 'ru';
  await PushNotificationService.initialize();
  _configurePushNavigation();
  runApp(MyApp());
}

void _configurePushNavigation() {
  PushNotificationService.notificationNavigationHandler = (data) {
    final navigator = PushNotificationService.navigatorKey.currentState;
    if (navigator == null) return false;

    final conversationType = data['conversation_type']?.toString();
    final conversationId =
        int.tryParse(data['conversation_id']?.toString() ?? '');
    if (conversationType == null || conversationId == null) return false;

    if (conversationType == 'group') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupChatId: conversationId,
            groupChatName:
                data['conversation_title']?.toString() ?? 'Групповой чат',
          ),
        ),
      );
      return true;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(recipientId: conversationId),
      ),
    );
    return true;
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      title: 'MoveUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Настройка локализаций
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ru', 'RU'), // Русская локаль
      ],
      locale:
          const Locale('ru', 'RU'), // Устанавливаем русскую локаль по умолчанию
      home: SplashScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/main': (context) => MainScreen(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final int initialIndex;
  MainScreen({this.initialIndex = 0});
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const Duration _unreadPollingInterval = Duration(seconds: 15);

  late int _selectedIndex;
  List<Widget?> _screens = [];
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  Timer? _unreadTimer;
  int _totalUnreadMessages = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex;
    _screens.addAll(List.filled(5, null));
    _startUnreadPolling();
    _loadUnreadMessagesCount();
    PushNotificationService.registerCurrentDeviceToken();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.openPendingNotificationIfAny();
    });
  }

  @override
  void dispose() {
    _stopUnreadPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startUnreadPolling();
      _loadUnreadMessagesCount();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopUnreadPolling();
    }
  }

  void _startUnreadPolling() {
    _unreadTimer?.cancel();
    _unreadTimer = Timer.periodic(_unreadPollingInterval, (_) {
      _loadUnreadMessagesCount();
    });
  }

  void _stopUnreadPolling() {
    _unreadTimer?.cancel();
    _unreadTimer = null;
  }

  Future<void> _loadUnreadMessagesCount() async {
    try {
      final unread = await _chatService.getUnreadMessagesCount();
      _setTotalUnreadMessages(_countUnreadMessages(unread));
    } catch (e) {
      debugPrint('Ошибка загрузки общего количества сообщений: $e');
    }
  }

  int _countUnreadMessages(Map<String, Map<int, int>> unread) {
    var total = 0;
    for (final group in unread.values) {
      total += group.values.where((value) => value > 0).length;
    }
    return total;
  }

  void _setTotalUnreadMessages(int total) {
    if (!mounted || _totalUnreadMessages == total) return;
    setState(() {
      _totalUnreadMessages = total;
    });
  }

  Widget _getScreen(int index) {
    if (_screens[index] == null) {
      switch (index) {
        case 0:
          _screens[index] = FeedScreen();
          break;
        case 1:
          _screens[index] = EventScreen();
          break;
        case 2:
          _screens[index] = ProfileScreen();
          break;
        case 3:
          _screens[index] = ChatListScreen(
            initiallyActive: _selectedIndex == 3,
            onUnreadTotalChanged: _setTotalUnreadMessages,
          );
          break;
        case 4:
          _screens[index] = LiveTrackerScreen();
          break;
        default:
          _screens[index] = Container();
      }
    }
    return _screens[index]!;
  }

  void _onItemTapped(int index) {
    final isLeavingChatTab = _selectedIndex == 3 && index != 3;
    if (isLeavingChatTab) {
      ChatListScreen.setActivePolling(false);
    }

    setState(() {
      _selectedIndex = index;
    });

    if (index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ChatListScreen.setActivePolling(true);
        _loadUnreadMessagesCount();
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выхода: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MoveUp'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(_screens.length, (index) {
          return PageStorage(
            bucket: PageStorageBucket(),
            child: _getScreen(index),
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: _buildBottomNavigationItems(),
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  List<BottomNavigationBarItem> _buildBottomNavigationItems() {
    return [
      BottomNavigationBarItem(
        icon: Icon(Icons.list),
        label: 'Лента',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.event),
        label: 'События',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.person),
        label: 'Профиль',
      ),
      BottomNavigationBarItem(
        icon: _buildChatTabIcon(),
        label: 'Чаты',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.track_changes),
        label: 'Трекер',
      ),
    ];
  }

  Widget _buildChatTabIcon() {
    final badgeText =
        _totalUnreadMessages > 99 ? '99+' : _totalUnreadMessages.toString();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.chat),
        if (_totalUnreadMessages > 0)
          Positioned(
            right: -10,
            top: -7,
            child: Container(
              constraints: BoxConstraints(minWidth: 18, minHeight: 18),
              padding: EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
