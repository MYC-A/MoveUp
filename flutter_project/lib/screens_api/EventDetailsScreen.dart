import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:flutter_application_1/screens_api/EventApplicationsScreen.dart';
import 'package:flutter_application_1/screens_api/InviteToEventScreen.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_application_1/services_api/EventTranslations.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/widgets/common/osm_tile_layer.dart';
import 'package:flutter_application_1/widgets/common/route_markers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

class EventDetailsScreen extends StatefulWidget {
  final int eventId;

  const EventDetailsScreen({required this.eventId, Key? key}) : super(key: key);

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final EventService _eventService = EventService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final MapController _mapController;

  Event? _event;
  Object? _loadError;
  int? _currentUserId;
  bool _isLoading = true;
  bool _isActionLoading = false;
  Timer? _autoRefreshTimer;
  static const Duration _autoRefreshInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadDetails(showLoading: true);
    // Пока карточка открыта — тихо обновляем статус заявки/места, чтобы изменения
    // организатора (одобрил/отклонил) появлялись без ручного обновления.
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted && !_isActionLoading && !_isLoading) {
        _loadDetails(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails({bool showLoading = false, bool silent = false}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final cachedUserId = await _storage.read(key: 'user_id');
      final event = await _eventService.getEventDetails(widget.eventId);
      if (!mounted) return;
      setState(() {
        _currentUserId = int.tryParse(cachedUserId ?? '');
        _event = event;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
      // silent — фоновый авто-опрос: не показываем ошибку, чтобы не спамить
      // снекбарами при моргании сети.
      if (!showLoading && !silent && _event != null) {
        showApiError(context, e, onRetry: () => _loadDetails());
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isOrganizer {
    final event = _event;
    return event != null &&
        _currentUserId != null &&
        event.organizerId == _currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Мероприятие'),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AppLoading(label: 'Загружаем мероприятие');
    }

    if (_loadError != null && _event == null) {
      return AppErrorState(
        title: 'Не удалось загрузить мероприятие',
        message: _loadError.toString(),
        onRetry: () => _loadDetails(showLoading: true),
      );
    }

    final event = _event;
    if (event == null) {
      return AppErrorState(
        title: 'Мероприятие не найдено',
        onRetry: () => _loadDetails(showLoading: true),
      );
    }

    final accent = _eventAccent(event);

    return RefreshIndicator(
      onRefresh: () => _loadDetails(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          _buildHeader(event, accent),
          const SizedBox(height: AppSpacing.md),
          _buildRouteSection(event, accent),
          const SizedBox(height: AppSpacing.md),
          _buildInfoSection(event, accent),
          const SizedBox(height: AppSpacing.md),
          _buildActionsSection(event),
        ],
      ),
    );
  }

  Widget _buildHeader(Event event, Color accent) {
    final type = EventTranslations.getEventTypeDisplayName(event.eventType);
    final difficulty =
        EventTranslations.getDifficultyDisplayName(event.difficulty);

    return _SurfaceSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityIcon(icon: _eventIcon(event), color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: TextStyle(
                        color: accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SeatsBadge(event: event),
            ],
          ),
          if (event.organizerName?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            _InfoPill(
              icon: Icons.person_pin_circle_outlined,
              label: _isOrganizer
                  ? 'Организатор: вы'
                  : 'Организатор: ${event.organizerName}',
              color: AppColors.primary,
            ),
          ],
          if (event.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              event.description!.trim(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                height: 1.42,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _InfoPill(icon: _eventIcon(event), label: type, color: accent),
              _InfoPill(
                icon: Icons.terrain_rounded,
                label: difficulty,
                color: AppColors.activity,
              ),
              _InfoPill(
                icon: Icons.groups_rounded,
                label: _seatsLabel(event),
                color: event.availableSeats > 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSection(Event event, Color accent) {
    final routePoints = event.routePoints;

    return _SurfaceSection(
      title: 'Маршрут',
      child: routePoints.isEmpty
          ? _EmptyRoute()
          : ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                height: 280,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    backgroundColor: AppColors.routeSoft,
                    initialCenter: routePoints.first,
                    initialZoom: 13,
                    onMapReady: () => _zoomToRoute(routePoints),
                  ),
                  children: [
                    osmTileLayer(),
                    if (routePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: downsampleRoute(
                              routePoints,
                              maxPoints: 180,
                            ),
                            color: accent,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _buildRouteMarkers(routePoints)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoSection(Event event, Color accent) {
    return _SurfaceSection(
      title: 'Детали',
      child: Column(
        children: [
          Row(
            children: [
              _DateTile(
                day: _formatDay(event.startTime),
                month: _formatMonth(event.startTime),
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  children: [
                    _MetaRow(
                      icon: Icons.access_time_rounded,
                      label: _formatTimeRange(event),
                      color: AppColors.activity,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _MetaRow(
                      icon: Icons.place_rounded,
                      label: event.city?.isNotEmpty == true
                          ? event.city!
                          : 'Маршрут на карте',
                      color: AppColors.route,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (event.goal?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetaRow(
              icon: Icons.flag_rounded,
              label: event.goal!.trim(),
              color: AppColors.primary,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _MetaRow(
            icon: event.isPublic ? Icons.public_rounded : Icons.lock_outline,
            label: event.isPublic ? 'Открытое мероприятие' : 'Закрытое мероприятие',
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(Event event) {
    final status = event.myStatus;
    final canOpenChat = event.groupChatId != null &&
        (_isOrganizer || status == 'APPROVED');

    if (_isOrganizer) {
      return _SurfaceSection(
        title: 'Управление',
        child: Column(
          children: [
            _StatusBanner(
              icon: Icons.verified_outlined,
              label: 'Вы организатор',
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            _PrimaryActionButton(
              icon: Icons.groups_rounded,
              label: 'Заявки и участники',
              onPressed: _isActionLoading ? null : _openApplications,
            ),
            if (!event.isExpired) ...[
              const SizedBox(height: AppSpacing.sm),
              _SecondaryActionButton(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Пригласить участников',
                onPressed: _isActionLoading ? null : _openInvite,
              ),
            ],
            if (event.groupChatId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _SecondaryActionButton(
                icon: Icons.forum_rounded,
                label: 'Чат события',
                onPressed: _isActionLoading ? null : _openChat,
              ),
            ],
          ],
        ),
      );
    }

    if (event.isExpired) {
      return _SurfaceSection(
        title: 'Участие',
        child: Column(
          children: [
            _StatusBanner(
              icon: Icons.event_busy_outlined,
              label: 'Мероприятие завершено',
              color: AppColors.textMuted,
            ),
            if (canOpenChat) ...[
              const SizedBox(height: AppSpacing.sm),
              _SecondaryActionButton(
                icon: Icons.forum_rounded,
                label: 'Чат события',
                onPressed: _isActionLoading ? null : _openChat,
              ),
            ],
          ],
        ),
      );
    }

    if (status == null) {
      return _SurfaceSection(
        title: 'Участие',
        child: _PrimaryActionButton(
          icon: event.availableSeats > 0
              ? Icons.send_rounded
              : Icons.block_rounded,
          label: event.availableSeats > 0 ? 'Подать заявку' : 'Нет свободных мест',
          onPressed: event.availableSeats > 0 && !_isActionLoading
              ? _participate
              : null,
        ),
      );
    }

    // Приглашение от организатора — отдельные действия: принять / отклонить.
    if (status == 'INVITED') {
      return _SurfaceSection(
        title: 'Приглашение',
        child: Column(
          children: [
            _StatusBanner(
              icon: _statusIcon(status),
              label: _statusLabel(status),
              color: _statusColor(status),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PrimaryActionButton(
              icon: Icons.check_rounded,
              label: event.availableSeats > 0
                  ? 'Принять приглашение'
                  : 'Нет свободных мест',
              onPressed: event.availableSeats > 0 && !_isActionLoading
                  ? _acceptInvitation
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SecondaryActionButton(
              icon: Icons.close_rounded,
              label: 'Отклонить',
              destructive: true,
              onPressed: _isActionLoading ? null : _declineInvitation,
            ),
          ],
        ),
      );
    }

    // Отказ финальный: показываем статус без действий — повторно подать нельзя.
    if (status == 'DENIED') {
      return _SurfaceSection(
        title: 'Участие',
        child: _StatusBanner(
          icon: _statusIcon(status),
          label: _statusLabel(status),
          color: _statusColor(status),
        ),
      );
    }

    return _SurfaceSection(
      title: 'Участие',
      child: Column(
        children: [
          _StatusBanner(
            icon: _statusIcon(status),
            label: _statusLabel(status),
            color: _statusColor(status),
          ),
          if (canOpenChat) ...[
            const SizedBox(height: AppSpacing.sm),
            _PrimaryActionButton(
              icon: Icons.forum_rounded,
              label: 'Чат события',
              onPressed: _isActionLoading ? null : _openChat,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _SecondaryActionButton(
            icon: Icons.logout_rounded,
            label: status == 'APPROVED' ? 'Отменить участие' : 'Отменить заявку',
            destructive: true,
            onPressed: _isActionLoading ? null : _cancelParticipation,
          ),
        ],
      ),
    );
  }

  List<Marker> _buildRouteMarkers(List<LatLng> routePoints) {
    if (routePoints.length == 1) {
      return [
        buildRouteMarker(
          routePoints.first,
          icon: Icons.place_rounded,
          color: AppColors.route,
          size: 38,
        ),
      ];
    }

    return [
      routeStartMarker(routePoints.first, size: 38),
      routeFinishMarker(routePoints.last, size: 40),
    ];
  }

  void _zoomToRoute(List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        if (routePoints.length == 1) {
          _mapController.move(routePoints.first, 15);
          return;
        }

        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(routePoints),
            padding: const EdgeInsets.all(42),
            maxZoom: 17,
          ),
        );
      });
    });
  }

  Future<void> _participate() async {
    final event = _event;
    if (event == null) return;

    setState(() => _isActionLoading = true);
    try {
      await _eventService.participateEvent(event.id);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена организатору')),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelParticipation() async {
    final event = _event;
    if (event == null) return;

    setState(() => _isActionLoading = true);
    try {
      await _eventService.cancelParticipation(event.id);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запись отменена')),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _acceptInvitation() async {
    final event = _event;
    if (event == null) return;

    setState(() => _isActionLoading = true);
    try {
      await _eventService.acceptInvitation(event.id);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы присоединились к мероприятию')),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _declineInvitation() async {
    final event = _event;
    if (event == null) return;

    setState(() => _isActionLoading = true);
    try {
      await _eventService.declineInvitation(event.id);
      await _loadDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Приглашение отклонено')),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _openApplications() {
    final event = _event;
    if (event == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventApplicationsScreen(eventId: event.id),
      ),
    ).then((_) => _loadDetails());
  }

  void _openInvite() {
    final event = _event;
    if (event == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InviteToEventScreen(
          eventId: event.id,
          eventTitle: event.title,
        ),
      ),
    ).then((_) => _loadDetails());
  }

  void _openChat() {
    final event = _event;
    final chatId = event?.groupChatId;
    if (event == null || chatId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatScreen(
          groupChatId: chatId,
          groupChatName: event.title,
        ),
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeRange(Event event) {
    if (event.startTime == null && event.endTime == null) {
      return 'Время не указано';
    }
    if (event.endTime == null) return _formatTime(event.startTime);
    return '${_formatTime(event.startTime)} - ${_formatTime(event.endTime)}';
  }

  String _formatDay(DateTime? dateTime) {
    if (dateTime == null) return '--';
    return dateTime.day.toString();
  }

  String _formatMonth(DateTime? dateTime) {
    if (dateTime == null) return 'дата';
    const months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'мая',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    return months[dateTime.month - 1];
  }

  Color _eventAccent(Event event) {
    final normalized =
        '${event.eventType} ${EventTranslations.getEventTypeDisplayName(event.eventType)}'
            .toLowerCase();

    if (normalized.contains('bike') ||
        normalized.contains('cycle') ||
        normalized.contains('вел')) {
      return AppColors.route;
    }

    if (normalized.contains('run') ||
        normalized.contains('бег') ||
        normalized.contains('поход') ||
        normalized.contains('hiking')) {
      return AppColors.primary;
    }

    return AppColors.activity;
  }

  IconData _eventIcon(Event event) {
    final normalized =
        '${event.eventType} ${EventTranslations.getEventTypeDisplayName(event.eventType)}'
            .toLowerCase();

    if (normalized.contains('bike') ||
        normalized.contains('cycle') ||
        normalized.contains('вел')) {
      return Icons.directions_bike_rounded;
    }

    if (normalized.contains('поход') || normalized.contains('hiking')) {
      return Icons.terrain_rounded;
    }

    return Icons.directions_run_rounded;
  }

  String _seatsLabel(Event event) {
    if (event.availableSeats <= 0) return 'Нет мест';
    if (event.availableSeats == 1) return 'Осталось 1 место';
    if (event.availableSeats <= 3) {
      return 'Осталось ${event.availableSeats} места';
    }
    return '${event.availableSeats} свободно';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'APPROVED':
        return 'Вы участвуете';
      case 'AWAITS':
        return 'Заявка на рассмотрении';
      case 'DENIED':
        return 'Заявка отклонена';
      case 'INVITED':
        return 'Вас пригласили на мероприятие';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return Icons.check_circle_outline;
      case 'AWAITS':
        return Icons.hourglass_top_outlined;
      case 'DENIED':
        return Icons.cancel_outlined;
      case 'INVITED':
        return Icons.mail_outline_rounded;
      default:
        return Icons.info_outline;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'AWAITS':
        return AppColors.activity;
      case 'DENIED':
        return AppColors.danger;
      case 'INVITED':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _SurfaceSection extends StatelessWidget {
  final String? title;
  final Widget child;

  const _SurfaceSection({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _ActivityIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: color, size: 27),
    );
  }
}

class _SeatsBadge extends StatelessWidget {
  final Event event;

  const _SeatsBadge({required this.event});

  @override
  Widget build(BuildContext context) {
    final hasSeats = event.availableSeats > 0;
    final color = hasSeats ? AppColors.success : AppColors.danger;

    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_rounded, color: color, size: 19),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hasSeats ? '${event.availableSeats}/${event.maxParticipants}' : 'Нет',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'мест',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String day;
  final String month;
  final Color color;

  const _DateTile({
    required this.day,
    required this.month,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 76,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            month,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusBanner({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textMuted,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.primary;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
    );
  }
}

class _EmptyRoute extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.map_outlined, color: AppColors.textMuted),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Маршрут не указан',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
