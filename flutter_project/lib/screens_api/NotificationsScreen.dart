import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/screens_api/OrganizerEvents_screen.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsUpdated;

  NotificationsScreen({this.onNotificationsUpdated});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final LkService lkService = LkService();
  Map<String, dynamic> notifications = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await lkService.fetchNotifications();
      if (!mounted) return;
      setState(() {
        notifications = data;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
      showApiError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markNotificationAsRead(int eventId, String type) async {
    try {
      await lkService.markNotificationAsRead(eventId, type);
      await _loadNotifications();
      if (widget.onNotificationsUpdated != null) {
        widget.onNotificationsUpdated!();
      }
    } catch (e) {
      showApiError(context, e);
    }
  }

  Future<void> _markEventUpdateRead(int notificationId) async {
    try {
      await lkService.markEventUpdateRead(notificationId);
      await _loadNotifications();
      if (widget.onNotificationsUpdated != null) {
        widget.onNotificationsUpdated!();
      }
    } catch (e) {
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Уведомления'),
          bottom: TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Мои мероприятия'),
              Tab(text: 'Мои заявки'),
              Tab(text: 'Обновления'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildNotificationSection(
              notifications: notifications['new_applications'] ?? [],
              type: 'application',
            ),
            _buildNotificationSection(
              notifications: notifications['user_applications_changes'] ?? [],
              type: 'change',
            ),
            _buildEventUpdatesSection(
              notifications: notifications['event_updates'] ?? [],
            ),
          ],
        ),
      ),
    );
  }

  // Раздел персистентных уведомлений (например, отмена мероприятия).
  // Переход никуда не ведёт — события уже нет; тап помечает прочитанным.
  Widget _buildEventUpdatesSection({required List<dynamic> notifications}) {
    if (_isLoading) {
      return const AppLoading(label: 'Загружаем уведомления');
    }
    if (_errorMessage != null) {
      return AppErrorState(message: _errorMessage, onRetry: _loadNotifications);
    }
    if (notifications.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none,
        title: 'Нет обновлений',
        message: 'Здесь появятся уведомления об отмене и изменениях событий.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: notifications.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final n = notifications[index];
        final isNew = n['is_new'] == true;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: const Icon(Icons.event_busy_outlined,
              color: AppColors.danger),
          title: Text(
            n['title']?.toString() ?? 'Мероприятие',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            n['body']?.toString() ?? 'Мероприятие отменено организатором',
          ),
          trailing: isNew
              ? const Icon(Icons.circle, color: AppColors.danger, size: 12)
              : null,
          onTap: isNew
              ? () => _markEventUpdateRead(n['notification_id'] as int)
              : null,
        );
      },
    );
  }

  Widget _buildNotificationSection({
    required List<dynamic> notifications,
    required String type,
  }) {
    if (_isLoading) {
      return const AppLoading(label: 'Загружаем уведомления');
    }

    if (_errorMessage != null) {
      return AppErrorState(
        message: _errorMessage,
        onRetry: _loadNotifications,
      );
    }

    if (notifications.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none,
        title: 'Нет уведомлений',
        message: 'Здесь появятся новые заявки и изменения по событиям.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: notifications.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          title: Text(
            notification['event_title'],
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            type == 'application'
                ? 'Новых заявок: ${notification['count']}'
                : 'Статус изменился: ${notification['count']}',
          ),
          trailing: notification['is_new']
              ? const Icon(Icons.circle, color: AppColors.danger, size: 12)
              : const Icon(Icons.arrow_forward, color: AppColors.textMuted),
          onTap: () async {
            final rawEventId = notification['event_id'];
            final eventId = rawEventId is int
                ? rawEventId
                : int.tryParse(rawEventId?.toString() ?? '');
            if (eventId == null) return;

            await _markNotificationAsRead(eventId, type);
            if (!mounted) return;

            final tabIndex = type == 'application' ? 0 : 1;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OrganizerEventsScreen(
                  initialTabIndex: tabIndex,
                ),
              ),
            ).then((_) => _loadNotifications());
          },
        );
      },
    );
  }
}
