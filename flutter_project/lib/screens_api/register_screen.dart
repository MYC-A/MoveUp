import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/auth/auth_scaffold.dart';
import '../services_api/auth_service.dart';
import '../screens/LiveTrackerScreen.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordCheckController = TextEditingController();
  final AuthService _authService = AuthService();

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      if (_passwordController.text != _passwordCheckController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Пароли не совпадают'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      try {
        await _authService.register(
          email: _emailController.text,
          fullName: _fullNameController.text,
          password: _passwordController.text,
          passwordCheck: _passwordController.text,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Регистрация выполнена успешно!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LiveTrackerScreen()),
        );
      } catch (e) {
        String errorMessage = 'Произошла ошибка при регистрации';
        if (e.toString().contains('Ошибка регистрации')) {
          try {
            final errorBody = json.decode(e
                .toString()
                .replaceFirst('Exception: Ошибка регистрации: ', ''));
            if (errorBody is List && errorBody.isNotEmpty) {
              final firstError = errorBody[0];
              if (firstError['type'] == 'missing') {
                if (firstError['loc'].contains('email')) {
                  errorMessage = 'Поле email обязательно.';
                } else if (firstError['loc'].contains('full_name')) {
                  errorMessage = 'Поле имя обязательно.';
                } else if (firstError['loc'].contains('password')) {
                  errorMessage = 'Поле пароль обязательно.';
                } else if (firstError['loc'].contains('password_check')) {
                  errorMessage = 'Поле повтор пароля обязательно.';
                } else {
                  errorMessage =
                      'Отсутствует обязательное поле: ${firstError['loc'].last}';
                }
              } else if (firstError['msg'] != null) {
                switch (firstError['msg']) {
                  case 'String should have at least 5 characters':
                    errorMessage = firstError['loc'][1] == 'password'
                        ? 'Пароль должен содержать не менее 5 символов.'
                        : 'Имя должно содержать не менее 5 символов.';
                    break;
                  case 'value is not a valid email address':
                    errorMessage = 'Некорректный формат email.';
                    break;
                  case 'Email already registered':
                    errorMessage = 'Этот email уже зарегистрирован.';
                    break;
                  default:
                    errorMessage = firstError['msg'];
                }
              }
            } else if (errorBody is Map<String, dynamic>) {
              if (errorBody['detail'] != null) {
                errorMessage = errorBody['detail'];
              } else if (errorBody['email'] != null) {
                errorMessage = 'Email: ${errorBody['email'][0]}';
              } else if (errorBody['password'] != null) {
                errorMessage = 'Пароль: ${errorBody['password'][0]}';
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Создать аккаунт',
      subtitle: 'Соберите профиль для маршрутов, событий и общения.',
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
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите имя';
                }
                if (value.length < 5) {
                  return 'Имя должно содержать не менее 5 символов';
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
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _passwordCheckController,
              decoration: const InputDecoration(
                labelText: 'Повторите пароль',
                prefixIcon: Icon(Icons.lock_reset),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _register(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Повторите пароль';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _register,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Уже есть аккаунт? Войдите'),
            ),
          ],
        ),
      ),
    );
  }
}
