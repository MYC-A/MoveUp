import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/RunningRoute.dart';
import '../services/StorageService.dart';
import 'CreatePostScreen.dart';
import 'RouteDetailsScreen.dart';
import 'RouteViewScreen.dart';

class RouteHistoryScreen extends StatefulWidget {
  /// Режим выбора маршрута для создания поста: тап по маршруту сразу открывает
  /// экран создания поста (без промежуточного экрана деталей), и показываются
  /// только свои (нескачанные) маршруты.
  final bool selectForPost;

  const RouteHistoryScreen({super.key, this.selectForPost = false});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  late TabController _tabController;

  List<RunningRoute> myRoutes = [];
  List<RunningRoute> downloadedRoutes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRoutes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final routes = await _storageService.loadRoutes();
      if (!mounted) return;
      setState(() {
        myRoutes = routes.where((route) => route.is_downloaded == 0).toList();
        downloadedRoutes =
            routes.where((route) => route.is_downloaded == 1).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
      _showErrorSnackbar('Ошибка загрузки маршрутов');
    }
  }

  Future<void> _deleteRoute(RunningRoute route) async {
    final shouldDelete = await _showDeleteConfirmationDialog(route.name);
    if (!shouldDelete) return;

    try {
      await _storageService.deleteRoute(route.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Маршрут "${route.name}" удален'),
            action: SnackBarAction(
              label: 'Отменить',
              onPressed: () => _restoreRoute(route),
            ),
          ),
        );
      }
      await _loadRoutes();
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Ошибка при удалении маршрута');
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog(String routeName) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить маршрут?'),
            content: Text('Маршрут "$routeName" будет удален из сохраненных.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreRoute(RunningRoute route) async {
    try {
      await _storageService.saveRoute(route);
      await _loadRoutes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Маршрут восстановлен')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Ошибка восстановления маршрута');
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _navigateToRouteDetails(RunningRoute route) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteDetailsScreen(route: route),
      ),
    );
    if (mounted) {
      _loadRoutes();
    }
  }

  void _openRouteView(RunningRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteViewScreen(route: route),
      ),
    );
  }

  // Режим выбора для поста: открываем создание поста сразу и, если пост создан,
  // закрываем экран выбора, чтобы вернуть пользователя в ленту.
  Future<void> _selectRouteForPost(RunningRoute route) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePostScreen(route: route),
      ),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectForPost) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Выберите маршрут')),
        body: _isLoading
            ? const AppLoading(label: 'Загружаем маршруты')
            : _error != null
                ? AppErrorState(message: _error, onRetry: _loadRoutes)
                : _buildRouteList(
                    myRoutes,
                    emptyTitle: 'Сохраненных маршрутов нет',
                    emptyMessage:
                        'Сначала запишите пробежку — затем сможете создать пост по маршруту.',
                  ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Маршруты'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.route_outlined), text: 'Сохраненные'),
            Tab(icon: Icon(Icons.download_done_outlined), text: 'Загруженные'),
          ],
        ),
      ),
      body: _isLoading
          ? const AppLoading(label: 'Загружаем маршруты')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _loadRoutes)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRouteList(
                      myRoutes,
                      emptyTitle: 'Сохраненных маршрутов нет',
                      emptyMessage:
                          'После пробежки маршруты появятся здесь, чтобы к ним можно было вернуться.',
                    ),
                    _buildRouteList(
                      downloadedRoutes,
                      emptyTitle: 'Загруженных маршрутов нет',
                      emptyMessage:
                          'Скачанные маршруты из постов появятся здесь для повторной пробежки.',
                    ),
                  ],
                ),
    );
  }

  Widget _buildRouteList(
    List<RunningRoute> routes, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (routes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRoutes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: AppEmptyState(
                icon: Icons.route_outlined,
                title: emptyTitle,
                message: emptyMessage,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        itemCount: routes.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final route = routes[index];
          return _RouteCard(
            route: route,
            onOpen: () => widget.selectForPost
                ? _selectRouteForPost(route)
                : _navigateToRouteDetails(route),
            onRun: () => _openRouteView(route),
            onDelete: () => _deleteRoute(route),
          );
        },
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RunningRoute route;
  final VoidCallback onOpen;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  const _RouteCard({
    required this.route,
    required this.onOpen,
    required this.onRun,
    required this.onDelete,
  });

  bool get _isDownloaded => route.is_downloaded == 1;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RouteMiniMap(route: route),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            _RouteBadge(
                              icon: _isDownloaded
                                  ? Icons.download_done_outlined
                                  : Icons.bookmark_added_outlined,
                              label: _isDownloaded ? 'Загружен' : 'Сохранен',
                              color: _isDownloaded
                                  ? AppColors.route
                                  : AppColors.primary,
                            ),
                            const _RouteBadge(
                              icon: Icons.directions_run,
                              label: 'Для пробежки',
                              color: AppColors.success,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.danger,
                  ),
                ],
              ),
              if (route.description.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  route.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(
                      icon: Icons.route_outlined,
                      label: _formatDistance(route.distance),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _MetricChip(
                      icon: Icons.timer_outlined,
                      label: _formatDuration(route.duration),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _MetricChip(
                      icon: Icons.calendar_today_outlined,
                      label: route.formattedDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Подробнее'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onRun,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Пробежать'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    return '${(meters / 1000).toStringAsFixed(2)} км';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}ч ${minutes}м';
    if (minutes > 0) return '${minutes}м';
    return '${duration.inSeconds.remainder(60)}с';
  }
}

class _RouteMiniMap extends StatefulWidget {
  final RunningRoute route;

  const _RouteMiniMap({required this.route});

  @override
  State<_RouteMiniMap> createState() => _RouteMiniMapState();
}

class _RouteMiniMapState extends State<_RouteMiniMap> {
  final MapController _mapController = MapController();

  List<LatLng> get _points => widget.route.points
      .map((point) => point.coordinates)
      .where(_isValidPoint)
      .toList();

  bool _isValidPoint(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  void _fitRoute() {
    final points = _points;
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14);
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;

    if (points.isEmpty) {
      return Container(
        height: 132,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.route_outlined, color: AppColors.textMuted),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 132,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 13,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
            onMapReady: _fitRoute,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.moveup.app',
            ),
            if (points.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 4,
                    color: AppColors.route,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                _routeMarker(points.first, 'Старт', AppColors.success),
                if (points.length > 1)
                  _routeMarker(points.last, 'Финиш', AppColors.danger),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Marker _routeMarker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 58,
      height: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_pin, color: color, size: 26),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RouteBadge({
    required this.icon,
    required this.label,
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
            Icon(icon, size: 15, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
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

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
