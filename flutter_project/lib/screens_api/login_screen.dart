import 'package:flutter/material.dart';
import 'register_screen.dart';
import 'dart:convert';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/auth/auth_scaffold.dart';
import '../services_api/auth_service.dart';
import '../services_api/push_notification_service.dart';

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
        await _authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
        await PushNotificationService.registerCurrentDeviceToken();
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
            backgroundColor: AppColors.danger,
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
    return AuthScaffold(
      title: 'Вход',
      subtitle: 'Продолжайте маршруты, события и общение.',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _login(),
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
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login),
                label: const Text('Войти'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RegisterScreen()),
                );
              },
              child: const Text('Нет аккаунта? Зарегистрируйтесь'),
            ),
          ],
        ),
      ),
    );
  }
}
