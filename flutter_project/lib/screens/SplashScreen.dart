import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/login_screen.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services_api/auth_service.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Небольшая задержка для инициализации FlutterSecureStorage
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final userId = await _authService.getCurrentUserId();
      print('SplashScreen: User ID: $userId');
      if (userId != null) {
        print('SplashScreen: Navigating to MainScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen(initialIndex: 0)),
        );
      } else {
        print('SplashScreen: Navigating to LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    } catch (e) {
      print('SplashScreen: Error checking auth status: $e');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
