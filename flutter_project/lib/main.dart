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
import 'package:flutter_application_1/services_api/chat_overview_controller.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

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
    return ChangeNotifierProvider(
      create: (_) => ChatOverviewController(),
      child: MaterialApp(
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
      ),
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
  late int _selectedIndex;
  List<Widget?> _screens = [];
  final AuthService _authService = AuthService();
  ChatOverviewController? _chatOverviewController;
  int _totalUnreadMessages = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex;
    _screens.addAll(List.filled(5, null));
    PushNotificationService.registerCurrentDeviceToken();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.openPendingNotificationIfAny();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatOverviewController>();
    if (_chatOverviewController == controller) return;

    _chatOverviewController?.removeListener(_handleChatOverviewChanged);
    _chatOverviewController = controller;
    controller.addListener(_handleChatOverviewChanged);
    controller.start();
    controller.setOverviewActive(_selectedIndex == 3);
    _handleChatOverviewChanged();
  }

  @override
  void dispose() {
    _chatOverviewController?.removeListener(_handleChatOverviewChanged);
    _chatOverviewController?.setOverviewActive(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chatOverviewController?.start();
      _chatOverviewController?.setOverviewActive(_selectedIndex == 3);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _chatOverviewController?.setOverviewActive(false);
      _chatOverviewController?.stop();
    }
  }

  void _handleChatOverviewChanged() {
    final total = _chatOverviewController?.totalUnreadConversations ?? 0;
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
          _screens[index] = ProfileScreen(onLogout: _logout);
          break;
        case 3:
          _screens[index] = ChatListScreen(
            initiallyActive: _selectedIndex == 3,
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
    final isEnteringChatTab = _selectedIndex != 3 && index == 3;

    if (isLeavingChatTab) {
      _chatOverviewController?.setOverviewActive(false);
    }

    setState(() {
      _selectedIndex = index;
    });

    if (isEnteringChatTab) {
      _chatOverviewController?.setOverviewActive(true);
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
      _chatOverviewController?.reset();
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
                color: AppColors.danger,
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
