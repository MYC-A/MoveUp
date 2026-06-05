import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/EventApplicationsScreen.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_application_1/services_api/EventTranslations.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class OrganizerEventsScreen extends StatefulWidget {
  const OrganizerEventsScreen({Key? key}) : super(key: key);

  @override
  _OrganizerEventsScreenState createState() => _OrganizerEventsScreenState();
}

class _OrganizerEventsScreenState extends State<OrganizerEventsScreen> {
  final LkService lkService = LkService();
  final EventService _eventService = EventService();

  final List<dynamic> events = [];
  int skipEvents = 0;
  final int limitEvents = 10;
  bool isLoadingEvents = false;
  bool hasMoreEvents = true;
  String? eventsError;
  final ScrollController _eventScrollController = ScrollController();

  final List<dynamic> userApplications = [];
  int skipApplications = 0;
  final int limitApplications = 10;
  bool isLoadingApplications = false;
  bool hasMoreApplications = true;
  String? applicationsError;
  final ScrollController _applicationsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _loadUserApplications();
    _markNotificationsAsRead();

    _eventScrollController.addListener(_onEventScroll);
    _applicationsScrollController.addListener(_onApplicationsScroll);
  }

  void _onEventScroll() {
    if (!_eventScrollController.hasClients) return;
    final distanceToBottom = _eventScrollController.position.maxScrollExtent -
        _eventScrollController.position.pixels;
    if (distanceToBottom <= 220) {
      _loadEvents();
    }
  }

  void _onApplicationsScroll() {
    if (!_applicationsScrollController.hasClients) return;
    final distanceToBottom =
        _applicationsScrollController.position.maxScrollExtent -
            _applicationsScrollController.position.pixels;
    if (distanceToBottom <= 220) {
      _loadUserApplications();
    }
  }

  Future<void> _loadEvents({bool refresh = false}) async {
    if (isLoadingEvents || (!hasMoreEvents && !refresh)) return;

    setState(() {
      isLoadingEvents = true;
      eventsError = null;
      if (refresh) {
        events.clear();
        skipEvents = 0;
        hasMoreEvents = true;
      }
    });

    try {
      final data = await lkService.fetchEvents(skipEvents, limitEvents);
      final loadedEvents = List<dynamic>.from(data['events'] ?? const []);

      if (!mounted) return;
      setState(() {
        events.addAll(loadedEvents);
        skipEvents += loadedEvents.length;
        hasMoreEvents = loadedEvents.length == limitEvents;
        isLoadingEvents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        eventsError = e.toString();
        isLoadingEvents = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки мероприятий: $e')),
      );
    }
  }

  Future<void> _loadUserApplications({bool refresh = false}) async {
    if (isLoadingApplications || (!hasMoreApplications && !refresh)) return;

    setState(() {
      isLoadingApplications = true;
      applicationsError = null;
      if (refresh) {
        userApplications.clear();
        skipApplications = 0;
        hasMoreApplications = true;
      }
    });

    try {
      final data = await lkService.fetchUserApplications(
        skipApplications,
        limitApplications,
      );
      final loadedApplications =
          List<dynamic>.from(data['applications'] ?? const []);

      if (!mounted) return;
      setState(() {
        userApplications.addAll(loadedApplications);
        skipApplications += loadedApplications.length;
        final hasMore = data['has_more'];
        hasMoreApplications = hasMore is bool
            ? hasMore
            : loadedApplications.length == limitApplications;
        isLoadingApplications = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        applicationsError = e.toString();
        isLoadingApplications = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки заявок: $e')),
      );
    }
  }

  Future<void> _refreshEvents() => _loadEvents(refresh: true);

  Future<void> _refreshApplications() => _loadUserApplications(refresh: true);

  Future<void> _markNotificationsAsRead() async {
    try {
      await lkService.markNotificationsAsRead();
    } catch (e) {
      debugPrint('Ошибка при сбросе уведомлений: $e');
    }
  }

  Future<void> _confirmDeleteEvent(Map<String, dynamic> event) async {
    final eventId = event['id'];
    if (eventId is! int) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить мероприятие?'),
        content: const Text(
          'Мероприятие, его групповой чат и список участников будут удалены. '
          'Все участники получат уведомление об отмене.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _eventService.deleteEvent(eventId);
      if (!mounted) return;
      setState(() {
        events.removeWhere((e) => (e as Map)['id'] == eventId);
        if (skipEvents > 0) skipEvents -= 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Мероприятие удалено, участники оповещены')),
      );
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Мои мероприятия'),
          centerTitle: false,
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.event_available_outlined),
                text: 'Мои мероприятия',
              ),
              Tab(
                icon: Icon(Icons.assignment_turned_in_outlined),
                text: 'Мои заявки',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildEventsSection(),
            _buildApplicationsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsSection() {
    return RefreshIndicator(
      onRefresh: _refreshEvents,
      child: _buildPagedList(
        controller: _eventScrollController,
        itemCount: events.length,
        hasMore: hasMoreEvents,
        isLoading: isLoadingEvents,
        error: eventsError,
        emptyState: const AppEmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Активных мероприятий нет',
          message: 'Прошедшие мероприятия здесь не показываются.',
        ),
        onRetry: _refreshEvents,
        itemBuilder: (context, index) => _buildEventCard(events[index]),
      ),
    );
  }

  Widget _buildApplicationsSection() {
    return RefreshIndicator(
      onRefresh: _refreshApplications,
      child: _buildPagedList(
        controller: _applicationsScrollController,
        itemCount: userApplications.length,
        hasMore: hasMoreApplications,
        isLoading: isLoadingApplications,
        error: applicationsError,
        emptyState: const AppEmptyState(
          icon: Icons.assignment_outlined,
          title: 'Активных заявок нет',
          message: 'Заявки на прошедшие мероприятия скрываются.',
        ),
        onRetry: _refreshApplications,
        itemBuilder: (context, index) =>
            _buildApplicationCard(userApplications[index]),
      ),
    );
  }

  Widget _buildPagedList({
    required ScrollController controller,
    required int itemCount,
    required bool hasMore,
    required bool isLoading,
    required String? error,
    required Widget emptyState,
    required Future<void> Function() onRetry,
    required Widget Function(BuildContext context, int index) itemBuilder,
  }) {
    if (isLoading && itemCount == 0) {
      return const AppLoading(label: 'Загружаем данные');
    }

    if (error != null && itemCount == 0) {
      return AppErrorState(
        message: error,
        onRetry: () => onRetry(),
      );
    }

    if (itemCount == 0) {
      return ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: emptyState,
          ),
        ],
      );
    }

    return ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      itemCount: itemCount + (hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        if (index >= itemCount) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        return itemBuilder(context, index);
      },
    );
  }

  Widget _buildEventCard(dynamic rawEvent) {
    final event = Map<String, dynamic>.from(rawEvent as Map);
    final title = _stringValue(event['title'], 'Без названия');
    final city = _stringValue(event['city'], 'Город не указан');
    final seatsText = _formatSeats(event);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: Icons.event_available_outlined,
                color: AppColors.activity,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _MetaLine(
                      icon: Icons.place_outlined,
                      label: city,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(
                label: 'Активно',
                icon: Icons.bolt_outlined,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoStrip(
            children: [
              _InfoPill(
                icon: Icons.schedule,
                label: 'Время',
                value: _formatDateRange(event['start_time'], event['end_time']),
              ),
              if (seatsText.isNotEmpty)
                _InfoPill(
                  icon: Icons.groups_outlined,
                  label: 'Места',
                  value: seatsText,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteEvent(event),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EventApplicationsScreen(
                          eventId: event['id'],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Заявки'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(dynamic rawApplication) {
    final application = Map<String, dynamic>.from(rawApplication as Map);
    final status = _stringValue(application['status'], 'AWAITS');
    final title = _stringValue(application['event_title'], 'Без названия');
    final city = _stringValue(application['event_city'], 'Город не указан');
    final statusColor = _statusColor(status);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: _statusIcon(status),
                color: statusColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _MetaLine(
                      icon: Icons.place_outlined,
                      label: city,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(
                label: EventTranslations.getStatusDisplayName(status),
                icon: _statusIcon(status),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoStrip(
            children: [
              _InfoPill(
                icon: Icons.schedule,
                label: 'Время',
                value: _formatDateRange(
                  application['event_start_time'],
                  application['event_end_time'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateRange(dynamic start, dynamic end) {
    return Helper.formatDateRange(start, end);
  }

  String _formatSeats(Map<String, dynamic> event) {
    final availableSeats = event['available_seats'];
    final maxParticipants = event['max_participants'];
    if (availableSeats == null || maxParticipants == null) return '';
    return '$availableSeats/$maxParticipants';
  }

  String _stringValue(dynamic value, String fallback) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'DENIED':
        return AppColors.danger;
      default:
        return AppColors.activity;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return Icons.check_circle_outline;
      case 'DENIED':
        return Icons.cancel_outlined;
      default:
        return Icons.hourglass_top_outlined;
    }
  }

  @override
  void dispose() {
    _eventScrollController.dispose();
    _applicationsScrollController.dispose();
    super.dispose();
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final List<Widget> children;

  const _InfoStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    // Пиллы располагаются столбиком на всю ширину — так длинное значение
    // (например, диапазон дат) переносится и не обрезается на узких экранах.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          children[i],
        ],
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '$label: ',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            // Значение занимает остаток ширины и при необходимости переносится.
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
