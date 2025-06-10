import 'package:flutter/material.dart';
import 'dart:convert';
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
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final response = await _authService.register(
          email: _emailController.text,
          fullName: _fullNameController.text,
          password: _passwordController.text,
          passwordCheck: _passwordController.text,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Регистрация выполнена успешно!'),
            backgroundColor: Colors.green, // Цвет для успешного сообщения
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Регистрация')),
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
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: 'Имя',
                    prefixIcon: Icon(Icons.person),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
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
                SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCheckController,
                  decoration: InputDecoration(
                    labelText: 'Повторите пароль',
                    prefixIcon: Icon(Icons.lock),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Повторите пароль';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _register,
                  child: Text('Зарегистрироваться'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  ),
                ),
                SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Уже есть аккаунт? Войдите',
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
