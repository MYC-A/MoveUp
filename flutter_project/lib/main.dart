import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Добавляем для локализации
import 'package:flutter_application_1/screens/LiveTrackerScreen.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/screens_api/event_screen.dart';
import 'package:flutter_application_1/screens_api/feed_screen.dart';
import 'package:flutter_application_1/screens_api/login_screen.dart';
import 'package:flutter_application_1/screens_api/profile_screen.dart';
import 'package:flutter_application_1/screens_api/register_screen.dart';
import 'package:flutter_application_1/screens/SplashScreen.dart';
import 'package:flutter_application_1/services_api/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  initializeDateFormatting('ru', null).then((_) {
    Intl.defaultLocale = 'ru';
    runApp(MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoveUp',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.amber[800],
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
        ),
      ),
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

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  List<Widget?> _screens = [];
  bool _isChatScreenInitialized = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _screens.addAll(List.filled(5, null));
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
          _screens[index] = ChatListScreen();
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
    setState(() {
      _selectedIndex = index;
      if (index == 3 && !_isChatScreenInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_screens[index] is ChatListScreen) {
            (_screens[index] as ChatListScreen).reloadChatData();
            _isChatScreenInitialized = true;
          }
        });
      }
      if (index != 3) {
        _isChatScreenInitialized = false;
      }
    });
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
        items: const [
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
            icon: Icon(Icons.chat),
            label: 'Чаты',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.track_changes),
            label: 'Трекер',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
