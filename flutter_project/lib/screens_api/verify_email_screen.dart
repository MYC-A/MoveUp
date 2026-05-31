import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/auth/auth_scaffold.dart';
import '../services_api/auth_service.dart';
import '../services_api/push_notification_service.dart';

/// Экран подтверждения email кодом из письма (после регистрации или при
/// попытке входа в неподтверждённый аккаунт).
class VerifyEmailScreen extends StatefulWidget {
  final String email;

  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 4) {
      _snack('Введите код из письма', AppColors.danger);
      return;
    }
    setState(() => _isVerifying = true);
    try {
      await _authService.verifyEmail(email: widget.email, code: code);
      await PushNotificationService.registerCurrentDeviceToken();
      if (!mounted) return;
      _snack('Email подтверждён!', AppColors.success);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => MainScreen(initialIndex: 0)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await _authService.resendCode(widget.email);
      if (!mounted) return;
      _snack('Новый код отправлен на ${widget.email}', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Подтверждение email',
      subtitle: 'Мы отправили код подтверждения на ${widget.email}. '
          'Введите его, чтобы завершить регистрацию.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: 'Код из письма',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verify,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(_isVerifying ? 'Проверяем…' : 'Подтвердить'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isResending ? null : _resend,
            child: Text(_isResending ? 'Отправляем…' : 'Отправить код повторно'),
          ),
        ],
      ),
    );
  }
}
