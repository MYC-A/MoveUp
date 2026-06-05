import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/models_api/post.dart';
import 'package:flutter_application_1/services_api/web_socket_channel.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/utils/calories.dart';
import 'package:flutter_application_1/utils/post_route_downloader.dart';
import 'package:flutter_application_1/screens_api/profile_screen.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/photo_viewer.dart';
import 'package:flutter_application_1/widgets/post_comments_sheet.dart';
import 'package:flutter_application_1/widgets/common/osm_tile_layer.dart';

// Единый CacheManager для всего приложения
final customCacheManager = CacheManager(
  Config(
    'customCacheKey',
    stalePeriod: Duration(days: 7),
    maxNrOfCacheObjects: 100,
  ),
);

class PostItem extends StatefulWidget {
  final Post post;
  final MapController mapController;
  final VoidCallback onMapTap;
  final bool Function(List<dynamic>) isValidRoute;
  final WebSocketService webSocketService;
  final Future<void> Function() loadPosts;
  final Future<void> Function(int) likePost;
  final int? currentUserId; // Новый параметр
  /// Колбэк удаления поста (доступен только владельцу). Если null — пункт скрыт.
  final Future<void> Function(Post)? onDeleted;

  const PostItem({
    Key? key,
    required this.post,
    required this.mapController,
    required this.onMapTap,
    required this.isValidRoute,
    required this.webSocketService,
    required this.loadPosts,
    required this.likePost,
    this.currentUserId, // Добавляем currentUserId
    this.onDeleted,
  }) : super(key: key);

  @override
  _PostItemState createState() => _PostItemState();
}

class _PostItemState extends State<PostItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _formatDuration(int seconds) {
    if (seconds == 0) return '0:00';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double meters) {
    if (meters == 0) return '0.00 км';
    final kilometers = meters / 1000;
    return '${kilometers.toStringAsFixed(2)} км';
  }

  void _navigateToUserProfile(int userId) {
    print("currentUserId: ${widget.currentUserId} and userId: $userId");

    // Если userId совпадает с текущим пользователем, переходим на ProfileScreen
    if (widget.currentUserId != null && userId == widget.currentUserId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfileScreen()),
      );
    } else {
      // Иначе переходим на UserProfiles
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => UserProfiles(userId: userId)),
      );
    }
  }

  void _applyCommentsCount(Post post, int? count) {
    // Разрешаем и увеличение, и уменьшение (например, при удалении коммента).
    if (count == null || count == post.commentsCount || !mounted) return;

    setState(() {
      post.commentsCount = count;
    });
  }

  Future<void> _openComments(Post post) async {
    final updatedCount = await showPostCommentsSheet(
      context: context,
      postId: post.id,
      initialCommentsCount: post.commentsCount,
      onCommentsCountChanged: (count) => _applyCommentsCount(post, count),
    );
    _applyCommentsCount(post, updatedCount);
  }

  void _showPostMenu(Post post, bool hasRoute) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Открыть профиль'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _navigateToUserProfile(post.userId);
                  },
                ),
                if (hasRoute) ...[
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('Открыть маршрут'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      widget.onMapTap();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Скачать маршрут'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await saveRouteFromPost(context, post);
                    },
                  ),
                ],
                if (_canDelete(post)) ...[
                  const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    leading: const Icon(Icons.delete_outline,
                        color: AppColors.danger),
                    title: const Text('Удалить пост',
                        style: TextStyle(color: AppColors.danger)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmDelete(post);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Удалять можно только свой пост и только если задан колбэк удаления.
  bool _canDelete(Post post) {
    return widget.onDeleted != null &&
        widget.currentUserId != null &&
        post.userId == widget.currentUserId;
  }

  Future<void> _confirmDelete(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить пост?'),
        content: const Text(
          'Пост и все его комментарии будут удалены без возможности восстановления.',
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

    if (confirmed == true) {
      await widget.onDeleted?.call(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = widget.post;
    final String avatarUrl =
        (post.userAvatarUrl ?? 'https://via.placeholder.com/150')
            .replaceAll('localhost:9000', AppConfig.mediaBaseUrlWithoutScheme);
    final hasRoute = widget.isValidRoute(post.routeData);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(post, avatarUrl, hasRoute),
          if (hasRoute) _buildRouteMap(post),
          if (hasRoute && (post.distance > 0 || post.duration > 0))
            _buildRouteStats(post),
          _buildContent(post),
          _buildPostChips(post, hasRoute),
          if (post.photoUrls != null && post.photoUrls!.isNotEmpty)
            _buildPhotoGrid(post),
          const Divider(height: 1, color: AppColors.border),
          _buildActions(post),
        ],
      ),
    );
  }

  Widget _buildHeader(Post post, String avatarUrl, bool hasRoute) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _navigateToUserProfile(post.userId),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.surfaceMuted,
              backgroundImage: CachedNetworkImageProvider(
                avatarUrl,
                cacheManager: customCacheManager,
              ),
              onBackgroundImageError: (exception, stackTrace) {
                debugPrint('Ошибка загрузки аватарки: $exception');
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.userFullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (hasRoute) ...[
                      const SizedBox(width: AppSpacing.xs),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.routeSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.directions_run,
                            color: AppColors.route,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    if (post.city != null && post.city!.isNotEmpty) ...[
                      const Icon(Icons.place_outlined,
                          size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(
                        (post.city != null && post.city!.isNotEmpty)
                            ? '${post.city} · ${Helper.formatDateTime(post.createdAt)}'
                            : Helper.formatDateTime(post.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Действия',
            icon: const Icon(Icons.more_vert),
            color: AppColors.textSecondary,
            onPressed: () => _showPostMenu(post, hasRoute),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteMap(Post post) {
    return _PostRouteMap(
      post: post,
      mapController: widget.mapController,
      onMapTap: widget.onMapTap,
    );
  }

  Widget _buildRouteStats(Post post) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _InfoTile(
              icon: Icons.timer_outlined,
              label: 'Время',
              value: _formatDuration(post.duration),
              color: AppColors.success,
            ),
          ),
          const _StatsDivider(),
          Expanded(
            child: _InfoTile(
              icon: Icons.route_outlined,
              label: 'Дистанция',
              value: _formatDistance(post.distance),
              color: AppColors.route,
            ),
          ),
          const _StatsDivider(),
          Expanded(
            child: _InfoTile(
              icon: Icons.local_fire_department_outlined,
              label: 'Калории',
              value: '${estimateCalories(post.distance)} ккал',
              color: AppColors.activity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Post post) {
    final textTheme = Theme.of(context).textTheme;

    // Без описания не рисуем блок вообще — иначе остаётся пустой отступ.
    if (post.content.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.content,
            style: textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              height: 1.38,
              fontWeight: FontWeight.w500,
            ),
            maxLines: post.isExpanded ? null : 3,
            overflow:
                post.isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (post.content.length > 100) ...[
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              onTap: () {
                setState(() {
                  post.isExpanded = !post.isExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Text(
                  post.isExpanded ? 'Свернуть' : 'Показать полностью',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostChips(Post post, bool hasRoute) {
    final chips = <Widget>[];

    if (hasRoute) {
      chips.add(
        _PostChip(
          icon: Icons.directions_run,
          label: 'Активность',
          foreground: AppColors.success,
          background: const Color(0xFFE8F7ED),
        ),
      );
    }
    // Дистанцию намеренно не дублируем чипом — она уже есть в строке статистики.
    if (post.photoUrls != null && post.photoUrls!.isNotEmpty) {
      chips.add(
        _PostChip(
          icon: Icons.photo_library_outlined,
          label: '${post.photoUrls!.length} фото',
          foreground: AppColors.activity,
          background: AppColors.activitySoft,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: chips,
      ),
    );
  }

  Widget _buildPhotoGrid(Post post) {
    final photoUrls = post.photoUrls!;
    final visibleCount = photoUrls.length > 4 ? 4 : photoUrls.length;
    final crossAxisCount = visibleCount == 1 ? 1 : 2;
    final childAspectRatio = visibleCount == 1 ? 1.75 : 1.28;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: visibleCount,
        itemBuilder: (context, index) {
          final String imageUrl = photoUrls[index].replaceAll(
            'localhost:9000',
            AppConfig.mediaBaseUrlWithoutScheme,
          );
          final remainingCount = photoUrls.length - visibleCount;
          final showRemainingOverlay =
              remainingCount > 0 && index == visibleCount - 1;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PhotoViewer(
                    photoUrls: photoUrls
                        .map((url) => url.replaceAll(
                              'localhost:9000',
                              AppConfig.mediaBaseUrlWithoutScheme,
                            ))
                        .toList(),
                    initialIndex: index,
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    cacheManager: customCacheManager,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.danger,
                    ),
                    fadeInDuration: const Duration(milliseconds: 300),
                    width: 100,
                    height: 100,
                  ),
                  if (showRemainingOverlay)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.42),
                      child: Center(
                        child: Text(
                          '+$remainingCount',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(Post post) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _PostActionButton(
              icon: post.likedByCurrentUser
                  ? Icons.favorite
                  : Icons.favorite_border,
              iconColor: post.likedByCurrentUser
                  ? AppColors.danger
                  : AppColors.textSecondary,
              label: '${post.likesCount} лайков',
              onTap: () => widget.likePost(post.id),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _PostActionButton(
              icon: Icons.mode_comment_outlined,
              iconColor: AppColors.textSecondary,
              label: '${post.commentsCount} комментариев',
              alignEnd: true,
              onTap: () => _openComments(post),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool alignEnd;

  const _PostActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        );

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _PostChip({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
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
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostRouteMap extends StatefulWidget {
  final Post post;
  final MapController mapController;
  final VoidCallback onMapTap;

  const _PostRouteMap({
    required this.post,
    required this.mapController,
    required this.onMapTap,
  });

  @override
  State<_PostRouteMap> createState() => _PostRouteMapState();
}

class _PostRouteMapState extends State<_PostRouteMap> {
  static const int _previewRouteMaxPoints = 150;

  late List<LatLng> _points;
  late List<LatLng> _previewPoints;
  late LatLng _initialCenter;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _cacheRoutePoints();
  }

  @override
  void didUpdateWidget(covariant _PostRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        !identical(oldWidget.post.routeData, widget.post.routeData)) {
      _cacheRoutePoints();
    }
  }

  void _cacheRoutePoints() {
    _points = widget.post.routeData
        .map(_latLngFromRoutePoint)
        .whereType<LatLng>()
        .toList(growable: false);
    _previewPoints = _downsample(_points);
    _initialCenter = _points.isNotEmpty ? _points.first : LatLng(0, 0);
    _isZoomed = false;
  }

  // Прореживаем точки для лёгкой отрисовки превью (концы сохраняем).
  List<LatLng> _downsample(List<LatLng> points) {
    if (points.length <= _previewRouteMaxPoints) return points;
    final step = (points.length - 1) / (_previewRouteMaxPoints - 1);
    return List.generate(_previewRouteMaxPoints, (index) {
      final sourceIndex =
          (index * step).round().clamp(0, points.length - 1);
      return points[sourceIndex];
    });
  }

  LatLng? _latLngFromRoutePoint(dynamic point) {
    if (point is! Map) return null;

    final latitude = _toDouble(point['latitude']);
    final longitude = _toDouble(point['longitude']);
    if (latitude == null || longitude == null) return null;
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;

    return LatLng(latitude, longitude);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_isZoomed || _points.isEmpty || info.visibleFraction < 0.3) return;
    _isZoomed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _zoomToRoute();
    });
  }

  void _zoomToRoute() {
    if (_points.length == 1) {
      widget.mapController.move(_points.first, 15.0);
      return;
    }

    final bounds = LatLngBounds.fromPoints(_points);
    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
        maxZoom: 17.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isEmpty) return const SizedBox.shrink();

    return VisibilityDetector(
      key: Key('map_${widget.post.id}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Container(
        height: 240,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.routeSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: FlutterMap(
                    mapController: widget.mapController,
                    options: MapOptions(
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                      initialCenter: _initialCenter,
                      initialZoom: 13.0,
                    ),
                    children: [
                      osmTileLayer(),
                      if (_points.length == 1)
                        MarkerLayer(
                          markers: [
                            Marker(
                              width: 40.0,
                              height: 40.0,
                              point: _points.first,
                              child: const Icon(
                                Icons.location_pin,
                                color: AppColors.route,
                                size: 40,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _previewPoints,
                              strokeWidth: 5.0,
                              color: AppColors.route,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              width: 34.0,
                              height: 34.0,
                              point: _points.first,
                              child: const _RouteMarker(
                                icon: Icons.directions_run,
                                color: AppColors.success,
                              ),
                            ),
                            Marker(
                              width: 40.0,
                              height: 40.0,
                              point: _points.last,
                              child: const _RouteMarker(
                                icon: Icons.flag,
                                color: AppColors.route,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: _MapOverlayButton(
                  icon: Icons.fullscreen,
                  tooltip: 'Открыть карту',
                  onTap: widget.onMapTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MapBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapOverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(icon, color: AppColors.textSecondary, size: 24),
          ),
        ),
      ),
    );
  }
}

class _StatsDivider extends StatelessWidget {
  const _StatsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 64,
      color: AppColors.border,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: color),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.labelLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _RouteMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _RouteMarker({
    required this.icon,
    required this.color,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    );
  }
}
