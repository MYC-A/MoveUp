import 'package:flutter/material.dart';
import 'register_screen.dart';
import '../screens/LiveTrackerScreen.dart';
import 'dart:convert';
import 'package:flutter_application_1/main.dart';
import '../services_api/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  Future<void> _login() async {
    _testStorage();
    if (_formKey.currentState!.validate()) {
      try {
        final response = await _authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вход выполнен успешно!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen(initialIndex: 0)),
        );
      } catch (e) {
        String errorMessage = 'Произошла ошибка при входе';
        if (e.toString().contains('Ошибка входа')) {
          try {
            final errorBody = json.decode(
                e.toString().replaceFirst('Exception: Ошибка входа: ', ''));
            if (errorBody is List && errorBody.isNotEmpty) {
              final firstError = errorBody[0];
              if (firstError['type'] == 'missing') {
                if (firstError['loc'].contains('email')) {
                  errorMessage = 'Поле email обязательно.';
                } else if (firstError['loc'].contains('password')) {
                  errorMessage = 'Поле пароль обязательно.';
                } else {
                  errorMessage =
                      'Отсутствует обязательное поле: ${firstError['loc'].last}';
                }
              } else if (firstError['msg'] != null) {
                switch (firstError['msg']) {
                  case 'String should have at least 5 characters':
                    errorMessage =
                        'Пароль должен содержать не менее 5 символов.';
                    break;
                  case 'Invalid email format':
                    errorMessage = 'Некорректный формат email.';
                    break;
                  case 'Invalid credentials':
                    errorMessage = 'Неверный email или пароль.';
                    break;
                  default:
                    errorMessage = firstError['msg'];
                }
              }
            } else if (errorBody is Map<String, dynamic>) {
              if (errorBody['detail'] == 'Неверные учетные данные') {
                errorMessage = 'Неверный email или пароль.';
              } else {
                errorMessage = errorBody['detail'] ?? 'Неизвестная ошибка';
              }
            }
          } catch (jsonError) {
            errorMessage = 'Ошибка соединения или неизвестная ошибка.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red, // Цвет фона для ошибок
          ),
        );
      }
    }
  }

  Future<void> _testStorage() async {
    try {
      await _authService.storage.write(key: 'test_key', value: 'test_value');
      final value = await _authService.storage.read(key: 'test_key');
      print('Storage test: Value read: $value');
    } catch (e) {
      print('Storage test: Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Вход')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueAccent, Colors.lightBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Введите email';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                      return 'Введите корректный email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.lock),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Введите пароль';
                    }
                    if (value.length < 5) {
                      return 'Пароль должен содержать не менее 5 символов';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _login,
                  child: Text('Войти'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  ),
                ),
                SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RegisterScreen()),
                    );
                  },
                  child: Text(
                    'Нет аккаунта? Зарегистрируйтесь',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
