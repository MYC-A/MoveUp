import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_exception.dart';
import 'push_notification_service.dart';

bool _redirectingToLogin = false;

/// Единый показ ошибки API пользователю.
///
/// - формирует понятный текст (через [ApiException]);
/// - при 401 (сессия истекла) чистит токен и уводит на экран логина;
/// - опционально добавляет кнопку «Повторить».
void showApiError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  final e = ApiException.fromError(error);

  if (e.isUnauthorized) {
    _handleUnauthorized();
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(e.message),
      behavior: SnackBarBehavior.floating,
      action: onRetry != null
          ? SnackBarAction(label: 'Повторить', onPressed: onRetry)
          : null,
    ),
  );
}

Future<void> _handleUnauthorized() async {
  if (_redirectingToLogin) return;
  _redirectingToLogin = true;
  try {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'access_token');
    await storage.delete(key: 'user_id');
    final navigator = PushNotificationService.navigatorKey.currentState;
    navigator?.pushNamedAndRemoveUntil('/login', (route) => false);
  } catch (_) {
    // навигация не критична — токен уже очищен, при перезапуске будет логин
  } finally {
    _redirectingToLogin = false;
  }
}
