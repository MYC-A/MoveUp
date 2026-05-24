import 'package:flutter/material.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:flutter_application_1/screens_api/CreateEventScreen.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_application_1/services_api/EventTranslations.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class EventScreen extends StatefulWidget {
  @override
  _EventScreenState createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  static const double _loadMoreThreshold = 200;

  final EventService _eventService = EventService();
  final List<Event> _events = [];
  int _skip = 0;
  final int _limit = 10;
  bool _isLoading = false;
  bool _hasMore = true;
  final List<MapController> _mapControllers = [];
  final ScrollController _scrollController = ScrollController();
  final Set<int> _fittedMapEventIds = {};
  int? _latestEventId;
  bool _isRefreshing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadEvents();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    for (var controller in _mapControllers) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;

    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    if (distanceToBottom <= _loadMoreThreshold) {
      _loadEvents();
    }
  }

  Future<void> _loadEvents({bool refresh = false}) async {
    if (_isLoading || (!_hasMore && !refresh)) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
      if (refresh) {
        _skip = 0;
        _events.clear();
        _mapControllers.clear();
        _fittedMapEventIds.clear();
        _hasMore = true;
        _latestEventId = null;
      }
    });

    try {
      final newEvents = await _eventService.getEvents(
        skip: _skip,
        limit: _limit,
        sortBy: 'id',
        sortOrder: 'desc',
      );
      setState(() {
        _events.addAll(newEvents);
        _skip += _limit;
        _hasMore = newEvents.length == _limit;
        _mapControllers.addAll(
            List.generate(newEvents.length, (index) => MapController()));
        if (newEvents.isNotEmpty) {
          _latestEventId =
              _events.map((e) => e.id).reduce((a, b) => a > b ? a : b);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки мероприятий: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRefresh() {
    if (_latestEventId == null) {
      return _loadEvents(refresh: true);
    }
    return _refreshEvents();
  }

  Future<void> _refreshEvents() async {
    if (_isRefreshing || _latestEventId == null) return;

    setState(() {
      _isRefreshing = true;
    });

    // Анимация прокрутки к началу
    await _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    try {
      final newEvents = await _eventService.getEvents(
        skip: 0,
        limit: _limit,
        sortBy: 'id',
        sortOrder: 'desc',
      );

      final newEventsToAdd =
          newEvents.where((event) => event.id > _latestEventId!).toList();
      if (newEventsToAdd.isNotEmpty) {
        setState(() {
          _events.insertAll(0, newEventsToAdd);
          _mapControllers.insertAll(0,
              List.generate(newEventsToAdd.length, (index) => MapController()));
          _latestEventId = _events.first.id;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newEventsToAdd.length} новых мероприятий')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления: $e')),
      );
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  void _zoomToRoute(List<LatLng> routePoints, MapController mapController) {
    if (routePoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(routePoints);
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
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

    if (event.endTime == null) {
      return _formatTime(event.startTime);
    }

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

  String _eventPlaceLabel(Event event) {
    return event.routeData.isEmpty ? 'Маршрут не указан' : 'Маршрут на карте';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('События'),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            AppIconButton(
              icon: Icons.refresh,
              tooltip: 'Обновить события',
              onPressed: _handleRefresh,
            ),
          AppIconButton(
            icon: Icons.add,
            tooltip: 'Создать событие',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateEventScreen()),
              );
              if (result == true) {
                _handleRefresh();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _handleRefresh,
        child: Stack(
          children: [
            _buildEventsContent(),
            if (_isRefreshing)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    margin: EdgeInsets.all(8),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsContent() {
    if (_events.isEmpty) {
      if (_isLoading) {
        return _buildStateList(
          const AppLoading(label: 'Загружаем события'),
        );
      }

      if (_loadError != null) {
        return _buildStateList(
          AppErrorState(
            message: _loadError,
            onRetry: () => _loadEvents(refresh: true),
          ),
        );
      }

      return _buildStateList(
        AppEmptyState(
          icon: Icons.event_available_outlined,
          title: 'Пока нет событий',
          message: 'Создайте событие или обновите список.',
          action: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateEventScreen()),
              );
              if (result == true) {
                _handleRefresh();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Создать событие'),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.sm,
        0,
        AppSpacing.xl,
      ),
      itemCount: _events.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _events.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppLoading(),
          );
        }
        final event = _events[index];
        return _buildEventCard(event, index);
      },
    );
  }

  Widget _buildStateList(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.58,
          child: child,
        ),
      ],
    );
  }

  Widget _buildEventCard(Event event, int index) {
    final accent = _eventAccent(event);
    final type = EventTranslations.getEventTypeDisplayName(event.eventType);
    final difficulty =
        EventTranslations.getDifficultyDisplayName(event.difficulty);
    final summary = event.description?.trim().isNotEmpty == true
        ? event.description!.trim()
        : event.goal?.trim();
    final hasSeats = event.availableSeats > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.74)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EventActivityIcon(
                  icon: _eventIcon(event),
                  color: accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _EventSeatsBadge(
                  availableSeats: event.availableSeats,
                  maxParticipants: event.maxParticipants,
                  hasSeats: hasSeats,
                ),
              ],
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  summary,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    height: 1.35,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(22),
                border:
                    Border.all(color: AppColors.border.withValues(alpha: 0.7)),
              ),
              child: Row(
                children: [
                  _EventDateTile(
                    day: _formatDay(event.startTime),
                    month: _formatMonth(event.startTime),
                    color: accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      children: [
                        _EventInfoRow(
                          icon: Icons.access_time_rounded,
                          label: _formatTimeRange(event),
                          color: AppColors.activity,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _EventInfoRow(
                          icon: Icons.place_rounded,
                          label: _eventPlaceLabel(event),
                          color: AppColors.route,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _EventPill(
                  icon: _eventIcon(event),
                  label: type,
                  color: accent,
                ),
                _EventPill(
                  icon: Icons.terrain_rounded,
                  label: difficulty,
                  color: AppColors.activity,
                ),
                _EventPill(
                  icon: Icons.group_rounded,
                  label: hasSeats
                      ? '${event.availableSeats} свободно'
                      : 'Мест нет',
                  color: hasSeats ? AppColors.success : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildMap(event, index, accent),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: hasSeats ? () => _participateEvent(event.id) : null,
                icon: Icon(
                  hasSeats ? Icons.send_rounded : Icons.block_rounded,
                  size: 20,
                ),
                label: Text(hasSeats ? 'Записаться' : 'Мест нет'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.surface,
                  disabledBackgroundColor: AppColors.surfaceMuted,
                  disabledForegroundColor: AppColors.textMuted,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(Event event, int index, Color accent) {
    if (event.routeData.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(22),
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

    final routePoints = event.routePoints;

    return VisibilityDetector(
      key: Key('map_${event.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.28 &&
            !_fittedMapEventIds.contains(event.id)) {
          _fittedMapEventIds.add(event.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _zoomToRoute(routePoints, _mapControllers[index]);
          });
        }
      },
      child: Container(
        height: 214,
        decoration: BoxDecoration(
          color: AppColors.routeSoft,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.route.withValues(alpha: 0.13),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapControllers[index],
                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  initialCenter: routePoints.isNotEmpty
                      ? routePoints.first
                      : const LatLng(55.7558, 37.6176),
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: accent,
                        strokeWidth: 5.0,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      if (routePoints.isNotEmpty)
                        Marker(
                          width: 42.0,
                          height: 42.0,
                          point: routePoints.first,
                          child: _EventRouteMarker(
                            icon: Icons.play_arrow_rounded,
                            color: AppColors.success,
                          ),
                        ),
                      if (routePoints.isNotEmpty)
                        Marker(
                          width: 46.0,
                          height: 46.0,
                          point: routePoints.last,
                          child: _EventRouteMarker(
                            icon: Icons.flag_rounded,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: AppSpacing.sm,
                top: AppSpacing.sm,
                child: _EventMapBadge(
                  icon: _eventIcon(event),
                  label: EventTranslations.getEventTypeDisplayName(
                    event.eventType,
                  ),
                  color: accent,
                ),
              ),
              Positioned(
                right: AppSpacing.sm,
                top: AppSpacing.sm,
                child: _EventMapButton(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenMap(
                          routePoints: event.routePoints,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _participateEvent(int eventId) async {
    try {
      await _eventService.participateEvent(eventId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Вы успешно записаны на мероприятие!')),
      );
    } catch (e) {
      String errorMessage = 'Ошибка записи';
      if (e.toString().contains("Организатор не может")) {
        errorMessage = "Организатор не может записаться на свое мероприятие";
      } else if (e.toString().contains("Нет свободных мест")) {
        errorMessage = "Все места заняты";
      } else if (e.toString().contains("уже является участником")) {
        errorMessage = "Вы уже записаны на это мероприятие";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }
}

class _EventActivityIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _EventActivityIcon({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(
        icon,
        color: color,
        size: 28,
      ),
    );
  }
}

class _EventSeatsBadge extends StatelessWidget {
  final int availableSeats;
  final int maxParticipants;
  final bool hasSeats;

  const _EventSeatsBadge({
    required this.availableSeats,
    required this.maxParticipants,
    required this.hasSeats,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasSeats ? AppColors.success : AppColors.danger;

    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$availableSeats/$maxParticipants',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const Text(
            'мест',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDateTile extends StatelessWidget {
  final String day;
  final String month;
  final Color color;

  const _EventDateTile({
    required this.day,
    required this.month,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 74,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day,
            style: TextStyle(
              color: color,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            month,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EventInfoRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 17,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EventPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EventPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: color.withValues(alpha: 0.13)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 17,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
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

class _EventMapBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EventMapBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: AppColors.surface,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.surface,
                  fontSize: 14,
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

class _EventMapButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EventMapButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: const Icon(
            Icons.fullscreen_rounded,
            color: AppColors.textSecondary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _EventRouteMarker extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _EventRouteMarker({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: AppColors.surface,
          size: 19,
        ),
      ),
    );
  }
}

class FullScreenMap extends StatefulWidget {
  final List<LatLng> routePoints;

  const FullScreenMap({Key? key, required this.routePoints}) : super(key: key);

  @override
  _FullScreenMapState createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<FullScreenMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomToRoute(List<LatLng> routePoints) {
    final bounds = LatLngBounds.fromPoints(routePoints);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта маршрута'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.routePoints.isNotEmpty
                  ? widget.routePoints.first
                  : LatLng(55.7558, 37.6176),
              initialZoom: 13.0,
              onMapReady: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Future.delayed(Duration(milliseconds: 500), () {
                    _zoomToRoute(widget.routePoints);
                  });
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routePoints,
                    color: AppColors.route,
                    strokeWidth: 5.0,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (widget.routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: widget.routePoints.first,
                      child: const _EventRouteMarker(
                        icon: Icons.play_arrow_rounded,
                        color: AppColors.success,
                      ),
                    ),
                  if (widget.routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: widget.routePoints.last,
                      child: const _EventRouteMarker(
                        icon: Icons.flag_rounded,
                        color: AppColors.route,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_in_${widget.hashCode}',
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_out_${widget.hashCode}',
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  },
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
