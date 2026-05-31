import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/auth/auth_scaffold.dart';
import '../services_api/auth_service.dart';
import '../services_api/EventService.dart';
import 'verify_email_screen.dart';

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
  final _cityController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final AuthService _authService = AuthService();
  final EventService _eventService = EventService();

  List<String> _cities = EventService.fallbackCities;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _passwordCheckController.dispose();
    _cityController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await _eventService.getEventCities();
      if (!mounted || cities.isEmpty) return;
      setState(() => _cities = cities);
    } catch (_) {/* остаётся fallback-список */}
  }

  String _normalizeCity(String v) =>
      v.trim().toLowerCase().replaceAll('ё', 'е');

  bool _isKnownCity(String v) =>
      _cities.any((c) => _normalizeCity(c) == _normalizeCity(v));

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _passwordCheckController.text) {
      _snack('Пароли не совпадают', AppColors.danger);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.register(
        email: _emailController.text,
        fullName: _fullNameController.text,
        password: _passwordController.text,
        passwordCheck: _passwordController.text,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        weight: double.tryParse(_weightController.text.replaceAll(',', '.')),
        height: double.tryParse(_heightController.text.replaceAll(',', '.')),
      );
      if (!mounted) return;
      // Подтверждение email — уводим на экран ввода кода.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              VerifyEmailScreen(email: _emailController.text.trim()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(_humanizeRegisterError(e), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _humanizeRegisterError(Object e) {
    final raw = e.toString();
    if (!raw.contains('Ошибка регистрации')) {
      return raw.replaceFirst('Exception: ', '');
    }
    try {
      final body =
          json.decode(raw.replaceFirst('Exception: Ошибка регистрации: ', ''));
      if (body is List && body.isNotEmpty && body[0]['msg'] != null) {
        return body[0]['msg'].toString();
      }
      if (body is Map && body['detail'] != null) return body['detail'].toString();
    } catch (_) {/* ниже вернём как есть */}
    return raw.replaceFirst('Exception: Ошибка регистрации: ', '');
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
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
                if (value == null || value.isEmpty) return 'Введите email';
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
                if (value == null || value.isEmpty) return 'Введите имя';
                if (value.trim().length < 3) {
                  return 'Имя должно содержать не менее 3 символов';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // Город — выбор из списка (как в событиях). Необязательно.
            Autocomplete<String>(
              optionsBuilder: (value) {
                final q = _normalizeCity(value.text);
                if (q.isEmpty) return _cities.take(8);
                return _cities
                    .where((c) => _normalizeCity(c).contains(q))
                    .take(12);
              },
              onSelected: (city) => _cityController.text = city,
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Город (необязательно)',
                    prefixIcon: Icon(Icons.location_city_outlined),
                    helperText: 'Выберите из списка',
                  ),
                  onChanged: (value) => _cityController.text = value,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    if (!_isKnownCity(value)) return 'Выберите город из списка';
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Вес, кг',
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final w = double.tryParse(value.replaceAll(',', '.'));
                      if (w == null) return 'Число';
                      if (w < 30 || w > 250) return '30–250';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _heightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Рост, см',
                      prefixIcon: Icon(Icons.height),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final h = double.tryParse(value.replaceAll(',', '.'));
                      if (h == null) return 'Число';
                      if (h < 100 || h > 250) return '100–250';
                      return null;
                    },
                  ),
                ),
              ],
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
                if (value == null || value.isEmpty) return 'Введите пароль';
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
                if (value == null || value.isEmpty) return 'Повторите пароль';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _register,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: Text(_isSubmitting ? 'Регистрируем…' : 'Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Уже есть аккаунт? Войдите'),
            ),
          ],
        ),
      ),
    );
  }
}
