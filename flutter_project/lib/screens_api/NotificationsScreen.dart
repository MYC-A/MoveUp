import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/screens_api/EventApplicationsScreen.dart';
import 'package:flutter_application_1/screens_api/EventDetailsScreen.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsUpdated;

  const NotificationsScreen({this.onNotificationsUpdated, Key? key})
      : super(key: key);

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
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await lkService.fetchNotifications();
      if (!mounted) return;
      setState(() => notifications = data);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _parseEventId(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? -1;
  }

  void _notifyUpdated() => widget.onNotificationsUpdated?.call();

  // Новая заявка организатору → экран заявок и участников события.
  Future<void> _openApplications(int eventId) async {
    try {
      await lkService.markNotificationAsRead(eventId, 'application');
    } catch (_) {}
    _notifyUpdated();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventApplicationsScreen(eventId: eventId),
      ),
    );
    _loadNotifications();
  }

  // Изменение статуса моей заявки / приглашение → карточка события.
  Future<void> _openEventDetails(int eventId, String markType) async {
    try {
      await lkService.markNotificationAsRead(eventId, markType);
    } catch (_) {}
    _notifyUpdated();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailsScreen(eventId: eventId),
      ),
    );
    _loadNotifications();
  }

  Future<void> _markEventUpdateRead(int notificationId) async {
    try {
      await lkService.markEventUpdateRead(notificationId);
      await _loadNotifications();
      _notifyUpdated();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Уведомления'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Заявки на события'),
              Tab(text: 'Мои заявки'),
              Tab(text: 'Приглашения'),
              Tab(text: 'Обновления'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildApplicationsSection(),
            _buildChangesSection(),
            _buildInvitationsSection(),
            _buildEventUpdatesSection(),
          ],
        ),
      ),
    );
  }

  Widget? _guard() {
    if (_isLoading) return const AppLoading(label: 'Загружаем уведомления');
    if (_errorMessage != null) {
      return AppErrorState(message: _errorMessage, onRetry: _loadNotifications);
    }
    return null;
  }

  // Организатор: новые заявки на его мероприятия.
  Widget _buildApplicationsSection() {
    final guard = _guard();
    if (guard != null) return guard;

    final items = (notifications['new_applications'] as List?) ?? const [];
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none,
        title: 'Нет новых заявок',
        message: 'Здесь появятся заявки на ваши мероприятия.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final n = items[index];
        return ListTile(
          leading: const Icon(Icons.group_add_outlined,
              color: AppColors.primary),
          title: Text(n['event_title']?.toString() ?? 'Мероприятие'),
          subtitle: Text('Новых заявок: ${n['count']}'),
          trailing: n['is_new'] == true
              ? const Icon(Icons.circle, color: AppColors.danger, size: 12)
              : const Icon(Icons.arrow_forward, color: AppColors.textMuted),
          onTap: () {
            final eventId = _parseEventId(n['event_id']);
            if (eventId > 0) _openApplications(eventId);
          },
        );
      },
    );
  }

  // Участник: изменения статуса моих заявок (одобрено / отклонено).
  Widget _buildChangesSection() {
    final guard = _guard();
    if (guard != null) return guard;

    final items =
        (notifications['user_applications_changes'] as List?) ?? const [];
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none,
        title: 'Нет изменений',
        message: 'Здесь появятся ответы организаторов на ваши заявки.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final n = items[index];
        return ListTile(
          leading: const Icon(Icons.event_available_outlined,
              color: AppColors.activity),
          title: Text(n['event_title']?.toString() ?? 'Мероприятие'),
          subtitle: const Text('Статус заявки изменился'),
          trailing: n['is_new'] == true
              ? const Icon(Icons.circle, color: AppColors.danger, size: 12)
              : const Icon(Icons.arrow_forward, color: AppColors.textMuted),
          onTap: () {
            final eventId = _parseEventId(n['event_id']);
            if (eventId > 0) _openEventDetails(eventId, 'change');
          },
        );
      },
    );
  }

  // Участник: приглашения от организаторов (принять / отклонить в карточке).
  Widget _buildInvitationsSection() {
    final guard = _guard();
    if (guard != null) return guard;

    final items = (notifications['invitations'] as List?) ?? const [];
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.mail_outline_rounded,
        title: 'Нет приглашений',
        message: 'Здесь появятся приглашения на мероприятия.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final n = items[index];
        return ListTile(
          leading:
              const Icon(Icons.mail_outline_rounded, color: AppColors.primary),
          title: Text(n['event_title']?.toString() ?? 'Мероприятие'),
          subtitle: const Text('Вас пригласили — нажмите, чтобы ответить'),
          trailing: n['is_new'] == true
              ? const Icon(Icons.circle, color: AppColors.danger, size: 12)
              : const Icon(Icons.arrow_forward, color: AppColors.textMuted),
          onTap: () {
            final eventId = _parseEventId(n['event_id']);
            if (eventId > 0) _openEventDetails(eventId, 'invitation');
          },
        );
      },
    );
  }

  // Персистентные уведомления (например, отмена мероприятия).
  Widget _buildEventUpdatesSection() {
    final guard = _guard();
    if (guard != null) return guard;

    final items = (notifications['event_updates'] as List?) ?? const [];
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.notifications_none,
        title: 'Нет обновлений',
        message: 'Здесь появятся уведомления об отмене и изменениях событий.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final n = items[index];
        final isNew = n['is_new'] == true;
        return ListTile(
          leading:
              const Icon(Icons.event_busy_outlined, color: AppColors.danger),
          title: Text(n['title']?.toString() ?? 'Мероприятие'),
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
}
