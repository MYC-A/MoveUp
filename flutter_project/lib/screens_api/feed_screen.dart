import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens/RouteHistoryScreen.dart';
import 'package:flutter_application_1/screens_api/CreatePostWithoutRouteScreen.dart';
import 'package:flutter_application_1/screens_api/PostDetails_screen.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/screens_api/FullScreenMap.dart';
import '../services_api/post_service.dart';
import '../models_api/post.dart';
import '../services_api/web_socket_channel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:async';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/screens_api/profile_screen.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

// Единый CacheManager для всего приложения
final customCacheManager = CacheManager(
  Config(
    'customCacheKey',
    stalePeriod: Duration(days: 7),
    maxNrOfCacheObjects: 100,
  ),
);

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  static const double _loadMoreThreshold = 200;

  final PageStorageBucket _bucket = PageStorageBucket();
  final ScrollController _scrollController = ScrollController();
  final PostService _postService = PostService();
  final WebSocketService _webSocketService = WebSocketService();
  List<Post> _posts = [];
  int _skip = 0;
  final int _limit = 20;
  bool _isLoading = false;
  bool _hasMore = true;
  int? _latestPostId;
  bool _isRefreshing = false;
  final List<MapController> _mapControllers = [];
  int? _currentUserId;
  Timer? _debounceTimer;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _loadCurrentUserId();
    _loadPosts();
    _webSocketService.switchToFeed();
    _webSocketService.setUpdateCallback(_handleWebSocketUpdate);
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final userId = await _postService.getCurrentUserId();
      setState(() {
        _currentUserId = userId;
        print("_currentUserId: $_currentUserId");
      });
    } catch (e) {
      debugPrint('Ошибка загрузки ID текущего пользователя: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScroll);
    for (var controller in _mapControllers) {
      controller.dispose();
    }
    _scrollController.dispose();
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_posts.length > 20) {
        setState(() {
          _posts = _posts.sublist(0, 20);
          _mapControllers.removeRange(20, _mapControllers.length);
        });
        debugPrint("Приложение свернуто, кэш частично очищен.");
      }
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;

    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    if (distanceToBottom <= _loadMoreThreshold) {
      _loadPosts();
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading || (!_hasMore && !refresh)) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
      if (refresh) {
        _skip = 0;
        _posts.clear();
        _mapControllers.clear();
        _hasMore = true;
        _latestPostId = null;
      }
    });

    try {
      final newPosts = await _postService.getFeed(_skip, _limit);
      setState(() {
        _posts.addAll(newPosts);
        _skip += _limit;
        _hasMore = newPosts.length == _limit;
        _mapControllers
            .addAll(List.generate(newPosts.length, (_) => MapController()));
        if (newPosts.isNotEmpty) {
          _latestPostId =
              _posts.map((p) => p.id).reduce((a, b) => a > b ? a : b);
        }
      });
      debugPrint("Посты загружены: ${newPosts.length}");
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки постов: $e')),
      );
      debugPrint('Ошибка загрузки постов: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRefresh() {
    if (_latestPostId == null) {
      return _loadPosts(refresh: true);
    }
    return _refreshPosts();
  }

  Future<void> _refreshPosts() async {
    if (_isRefreshing || _latestPostId == null) return;

    setState(() {
      _isRefreshing = true;
    });

    await _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    try {
      final newPosts = await _postService.getFeed(0, _limit);
      final newPostsToAdd =
          newPosts.where((post) => post.id > _latestPostId!).toList();
      if (!mounted) return;

      var hasExistingUpdates = false;
      setState(() {
        if (newPostsToAdd.isNotEmpty) {
          _posts.insertAll(0, newPostsToAdd);
          _mapControllers.insertAll(
              0, List.generate(newPostsToAdd.length, (_) => MapController()));
          _latestPostId = _posts.first.id;
        }

        // Обновляем commentsCount/likesCount для существующих постов одним rebuild.
        for (var newPost in newPosts) {
          final index = _posts.indexWhere((p) => p.id == newPost.id);
          if (index != -1) {
            _posts[index].commentsCount = newPost.commentsCount;
            _posts[index].likesCount = newPost.likesCount;
            hasExistingUpdates = true;
          }
        }

        if (newPostsToAdd.isNotEmpty || hasExistingUpdates) {
          _posts = List.from(_posts);
        }
        _isRefreshing = false;
      });

      if (newPostsToAdd.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newPostsToAdd.length} новых постов')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
      debugPrint('Ошибка обновления: $e');
    }
  }

  void _handleWebSocketUpdate(Map<String, dynamic> update) {
    debugPrint('Получено WebSocket-обновление: $update');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 100), () {
      setState(() {
        final postId = update['post_id'];
        final postIndex = _posts.indexWhere((post) => post.id == postId);
        if (postIndex != -1) {
          final post = _posts[postIndex];
          switch (update['type']) {
            case 'like':
              post.likesCount = update['likes_count'];
              if (update['user_id'] == _currentUserId) {
                post.likedByCurrentUser = update['liked'];
              }
              _posts = List.from(_posts); // Принудительное обновление списка
              debugPrint(
                  'Обновлён лайк для поста $postId: likesCount=${post.likesCount}, likedByCurrentUser=${post.likedByCurrentUser}');
              break;
            case 'comment':
              post.commentsCount += 1;
              _posts = List.from(_posts); // Принудительное обновление списка
              debugPrint(
                  'Обновлён комментарий для поста $postId: commentsCount=${post.commentsCount}');
              break;
            case 'photo':
              break;
          }
        }
      });
    });
  }

  Future<void> _likePost(int postId) async {
    try {
      await _postService.likePost(postId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка лайка: $e')),
      );
      debugPrint('Ошибка лайка: $e');
    }
  }

  bool _isValidRoute(List<dynamic> routeData) {
    return routeData.isNotEmpty;
  }

  void _zoomToRoute(List<dynamic> routeData, MapController mapController) {
    if (!_isValidRoute(routeData)) return;
    if (routeData.length == 1) {
      final point = LatLng(routeData[0]['latitude'], routeData[0]['longitude']);
      mapController.move(point, 15.0);
      return;
    }
    final bounds = LatLngBounds.fromPoints(
      routeData
          .map((point) => LatLng(point['latitude'], point['longitude']))
          .toList(),
    );
    mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50)),
    );
  }

  void _showPostOptions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Создать пост"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.route),
                title: Text("Создать пост по маршруту"),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToRouteHistoryScreen();
                },
              ),
              ListTile(
                leading: Icon(Icons.create),
                title: Text("Создать пост без маршрута"),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToCreatePostWithoutRouteScreen();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToRouteHistoryScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => RouteHistoryScreen()),
    ).then((_) => _refreshPosts());
  }

  void _navigateToCreatePostWithoutRouteScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreatePostWithoutRouteScreen()),
    ).then((_) => _refreshPosts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активности'),
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
              tooltip: 'Обновить ленту',
              onPressed: _handleRefresh,
            ),
          AppIconButton(
            icon: Icons.add,
            tooltip: 'Создать пост',
            onPressed: _showPostOptions,
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.background,
        child: PageStorage(
          bucket: _bucket,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _handleRefresh,
            child: Stack(
              children: [
                _buildFeedContent(),
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
        ),
      ),
    );
  }

  Widget _buildFeedContent() {
    if (_posts.isEmpty) {
      if (_isLoading) {
        return _buildStateList(
          const AppLoading(label: 'Загружаем ленту'),
        );
      }

      if (_loadError != null) {
        return _buildStateList(
          AppErrorState(
            message: _loadError,
            onRetry: () => _loadPosts(refresh: true),
          ),
        );
      }

      return _buildStateList(
        AppEmptyState(
          icon: Icons.dynamic_feed_outlined,
          title: 'Пока нет публикаций',
          message: 'Создайте первый пост или обновите ленту.',
          action: ElevatedButton.icon(
            onPressed: _showPostOptions,
            icon: const Icon(Icons.add),
            label: const Text('Создать пост'),
          ),
        ),
      );
    }

    return ListView.separated(
      key: PageStorageKey('feed_list'),
      controller: _scrollController,
      physics: AlwaysScrollableScrollPhysics(),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppLoading(),
          );
        }
        final post = _posts[index];
        return PostItem(
          key: ValueKey(post.id),
          post: post,
          mapController: _mapControllers[index],
          onMapTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FullScreenMap(routeData: post.routeData),
              ),
            );
          },
          isValidRoute: _isValidRoute,
          zoomToRoute: _zoomToRoute,
          webSocketService: _webSocketService,
          loadPosts: _loadPosts,
          likePost: _likePost,
          currentUserId: _currentUserId,
        );
      },
    );
  }

  Widget _buildStateList(Widget child) {
    return ListView(
      key: const PageStorageKey('feed_state'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.58,
          child: child,
        ),
      ],
    );
  }
}

class PostItem extends StatefulWidget {
  final Post post;
  final MapController mapController;
  final VoidCallback onMapTap;
  final bool Function(List<dynamic>) isValidRoute;
  final void Function(List<dynamic>, MapController) zoomToRoute;
  final WebSocketService webSocketService;
  final Future<void> Function() loadPosts;
  final Future<void> Function(int) likePost;
  final int? currentUserId; // Новый параметр

  const PostItem({
    Key? key,
    required this.post,
    required this.mapController,
    required this.onMapTap,
    required this.isValidRoute,
    required this.zoomToRoute,
    required this.webSocketService,
    required this.loadPosts,
    required this.likePost,
    this.currentUserId, // Добавляем currentUserId
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

  String _formatStartTime(List<dynamic> routeData, String createdAt) {
    if (routeData.isNotEmpty && routeData[0]['timestamp'] != null) {
      try {
        final startTime = DateTime.parse(routeData[0]['timestamp']);
        return '${startTime.day.toString().padLeft(2, '0')}.${startTime.month.toString().padLeft(2, '0')}.${startTime.year} ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        debugPrint('Ошибка парсинга timestamp: $e');
      }
    }
    final createdTime = DateTime.parse(createdAt);
    return '${createdTime.day.toString().padLeft(2, '0')}.${createdTime.month.toString().padLeft(2, '0')}.${createdTime.year} ${createdTime.hour.toString().padLeft(2, '0')}:${createdTime.minute.toString().padLeft(2, '0')}';
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
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(post, avatarUrl, hasRoute),
          if (hasRoute) _buildRouteMap(post),
          if (hasRoute && (post.distance > 0 || post.duration > 0))
            _buildRouteStats(post),
          _buildContent(post),
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
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _navigateToUserProfile(post.userId),
            child: CircleAvatar(
              radius: 24,
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
                Text(
                  post.userFullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  Helper.formatDateTime(post.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: hasRoute ? 'Открыть маршрут' : 'Маршрут не прикреплён',
            icon: const Icon(Icons.map_outlined),
            color: hasRoute ? AppColors.route : AppColors.textMuted,
            onPressed: hasRoute ? widget.onMapTap : null,
            style: IconButton.styleFrom(
              backgroundColor:
                  hasRoute ? AppColors.routeSoft : AppColors.surfaceMuted,
              disabledBackgroundColor: AppColors.surfaceMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteMap(Post post) {
    return VisibilityDetector(
      key: Key('map_${post.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.zoomToRoute(post.routeData, widget.mapController);
          });
        }
      },
      child: Container(
        height: 210,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.routeSoft,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: FlutterMap(
            mapController: widget.mapController,
            options: MapOptions(
              interactionOptions:
                  InteractionOptions(flags: InteractiveFlag.none),
              initialCenter: LatLng(
                post.routeData[0]['latitude'],
                post.routeData[0]['longitude'],
              ),
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
              ),
              if (post.routeData.length == 1)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40.0,
                      height: 40.0,
                      point: LatLng(
                        post.routeData[0]['latitude'],
                        post.routeData[0]['longitude'],
                      ),
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.route,
                        size: 40,
                      ),
                    ),
                  ],
                )
              else
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: post.routeData
                          .map((point) =>
                              LatLng(point['latitude'], point['longitude']))
                          .toList(),
                      strokeWidth: 4.0,
                      color: AppColors.route,
                    ),
                  ],
                ),
              if (post.routeData.length > 1)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: LatLng(
                        post.routeData.first['latitude'],
                        post.routeData.first['longitude'],
                      ),
                      child: _RouteMarker(
                        icon: Icons.directions_run,
                        color: AppColors.success,
                      ),
                    ),
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: LatLng(
                        post.routeData.last['latitude'],
                        post.routeData.last['longitude'],
                      ),
                      child: _RouteMarker(
                        icon: Icons.flag,
                        color: AppColors.route,
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

  Widget _buildRouteStats(Post post) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.routeSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _InfoTile(
              icon: Icons.timer_outlined,
              label: 'Время',
              value: _formatDuration(post.duration),
            ),
          ),
          Expanded(
            child: _InfoTile(
              icon: Icons.directions_run,
              label: 'Дистанция',
              value: _formatDistance(post.distance),
            ),
          ),
          Expanded(
            child: _InfoTile(
              icon: Icons.calendar_today_outlined,
              label: 'Начало',
              value:
                  _formatStartTime(post.routeData, post.createdAt.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Post post) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.content,
            style: textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.35,
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

  Widget _buildPhotoGrid(Post post) {
    final photoUrls = post.photoUrls!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: AppSpacing.xxs,
          mainAxisSpacing: AppSpacing.xxs,
        ),
        itemCount: photoUrls.length,
        itemBuilder: (context, index) {
          final String imageUrl = photoUrls[index].replaceAll(
            'localhost:9000',
            AppConfig.mediaBaseUrlWithoutScheme,
          );
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
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: CachedNetworkImage(
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(Post post) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
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
              onTap: () {
                widget.webSocketService.disconnect();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetailsScreen(postId: post.id),
                  ),
                ).then((_) {
                  widget.webSocketService.switchToFeed();
                  widget.loadPosts();
                });
              },
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
          fontSize: 13,
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
            Icon(icon, color: iconColor, size: 21),
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.route),
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
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

  const _RouteMarker({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: Icon(icon, color: Colors.white, size: 14),
    );
  }
}
/*
class FullScreenMap extends StatefulWidget {
  final List<dynamic> routeData;

  const FullScreenMap({
    Key? key,
    required this.routeData,
  }) : super(key: key);

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

  void _zoomToRoute(List<dynamic> routeData) {
    if (routeData.length == 1) {
      // Если одна точка, просто центрируем карту на этой точке
      final point = LatLng(
        routeData[0]['latitude'],
        routeData[0]['longitude'],
      );
      _mapController.move(point, 15.0); // Устанавливаем зум на 15
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      routeData
          .map((point) => LatLng(point['latitude'], point['longitude']))
          .toList(),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startIcon = Icon(
      Icons.run_circle,
      color: Colors.green,
      size: 25,
    );

    final finishIcon = Icon(
      Icons.flag_circle,
      color: Colors.blue,
      size: 25,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Карта маршрута'),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(
            widget.routeData[0]['latitude'],
            widget.routeData[0]['longitude'],
          ),
          initialZoom: 13.0,
          onMapReady: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(Duration(milliseconds: 500), () {
                _zoomToRoute(widget.routeData);
              });
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          if (widget.routeData.length == 1) ...[
            MarkerLayer(
              markers: [
                Marker(
                  width: 40.0,
                  height: 40.0,
                  point: LatLng(
                    widget.routeData[0]['latitude'],
                    widget.routeData[0]['longitude'],
                  ),
                  child: Icon(Icons.location_pin, color: Colors.red, size: 40),
                ),
              ],
            ),
          ] else ...[
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.routeData
                      .map((point) =>
                          LatLng(point['latitude'], point['longitude']))
                      .toList(),
                  strokeWidth: 4.0,
                  color: Colors.orange,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  width: 30.0,
                  height: 30.0,
                  point: LatLng(
                    widget.routeData.first['latitude'],
                    widget.routeData.first['longitude'],
                  ),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.directions_run,
                        color: Colors.white, size: 16),
                  ),
                ),
                Marker(
                  width: 30.0,
                  height: 30.0,
                  point: LatLng(
                    widget.routeData.last['latitude'],
                    widget.routeData.last['longitude'],
                  ),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.flag, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

*/

/*
Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.comment, color: Colors.grey),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PostDetailsScreen(
                                          postId: post.id, // Передаем postId
                                        ),
                                      ),
                                    ).then((_) {
                                      _webSocketService
                                          .switchToFeed(); // Возвращаемся к ленте
                                    });
                                  },
                                ),
*/
