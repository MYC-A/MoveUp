import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading || (!_hasMore && !refresh)) return;
    setState(() {
      _isLoading = true;
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
      if (newPostsToAdd.isNotEmpty) {
        setState(() {
          _posts.insertAll(0, newPostsToAdd);
          _mapControllers.insertAll(
              0, List.generate(newPostsToAdd.length, (_) => MapController()));
          _latestPostId = _posts.first.id;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newPostsToAdd.length} новых постов')),
        );
      }
      // Обновляем commentsCount для существующих постов
      for (var newPost in newPosts) {
        final index = _posts.indexWhere((p) => p.id == newPost.id);
        if (index != -1) {
          setState(() {
            _posts[index].commentsCount = newPost.commentsCount;
            _posts[index].likesCount = newPost.likesCount;
            _posts = List.from(_posts);
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления: $e')),
      );
      debugPrint('Ошибка обновления: $e');
    } finally {
      setState(() {
        _isRefreshing = false;
      });
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Активности',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
            fontSize: 24,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh, color: Colors.black),
            onPressed: _refreshPosts,
          ),
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: _showPostOptions,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: PageStorage(
          bucket: _bucket,
          child: RefreshIndicator(
            onRefresh: _refreshPosts,
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (scrollInfo.metrics.pixels ==
                        scrollInfo.metrics.maxScrollExtent &&
                    _hasMore &&
                    !_isLoading) {
                  _loadPosts();
                }
                return true;
              },
              child: Stack(
                children: [
                  ListView.separated(
                    key: PageStorageKey('feed_list'),
                    controller: _scrollController,
                    itemCount: _posts.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey[300]),
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        return Center(child: CircularProgressIndicator());
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
                              builder: (context) =>
                                  FullScreenMap(routeData: post.routeData),
                            ),
                          );
                        },
                        isValidRoute: _isValidRoute,
                        zoomToRoute: _zoomToRoute,
                        webSocketService: _webSocketService,
                        loadPosts: _loadPosts,
                        likePost: _likePost,
                        currentUserId:
                            _currentUserId, // Передаем _currentUserId
                      );
                    },
                  ),
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
                            color: Colors.white,
                            shape: BoxShape.circle,
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
      ),
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
            .replaceAll('localhost:9000', '91.200.84.206/minio');

    return Container(
      margin: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: () => _navigateToUserProfile(post.userId),
              child: CircleAvatar(
                backgroundImage: CachedNetworkImageProvider(
                  avatarUrl,
                  cacheManager: customCacheManager,
                ),
                onBackgroundImageError: (exception, stackTrace) {
                  debugPrint('Ошибка загрузки аватарки: $exception');
                },
              ),
            ),
            title: Text(
              post.userFullName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              Helper.formatDateTime(post.createdAt),
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.map, color: Colors.blueAccent),
              onPressed: widget.onMapTap,
            ),
          ),
          if (widget.isValidRoute(post.routeData))
            VisibilityDetector(
              key: Key('map_${post.id}'),
              onVisibilityChanged: (info) {
                if (info.visibleFraction > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.zoomToRoute(post.routeData, widget.mapController);
                  });
                }
              },
              child: Container(
                height: 200,
                margin: EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
                              child: Icon(Icons.location_pin,
                                  color: Colors.red, size: 40),
                            ),
                          ],
                        )
                      else
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: post.routeData
                                  .map((point) => LatLng(
                                      point['latitude'], point['longitude']))
                                  .toList(),
                              strokeWidth: 4.0,
                              color: Colors.orange,
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
                                post.routeData.last['latitude'],
                                post.routeData.last['longitude'],
                              ),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.flag,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.isValidRoute(post.routeData) &&
              (post.distance > 0 || post.duration > 0))
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InfoTile(
                    icon: Icons.timer,
                    label: 'Время',
                    value: _formatDuration(post.duration),
                  ),
                  _InfoTile(
                    icon: Icons.directions_run,
                    label: 'Дистанция',
                    value: _formatDistance(post.distance),
                  ),
                  _InfoTile(
                    icon: Icons.calendar_today,
                    label: 'Начало',
                    value: _formatStartTime(
                        post.routeData, post.createdAt.toString()),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content,
                  style: TextStyle(fontSize: 16, fontFamily: 'Roboto'),
                  maxLines: post.isExpanded ? null : 3,
                  overflow: post.isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                if (post.content.length > 100)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        post.isExpanded = !post.isExpanded;
                      });
                    },
                    child: Text(
                      post.isExpanded ? 'Свернуть' : 'Показать полностью',
                      style: TextStyle(
                        color: Colors.blue,
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (post.photoUrls != null && post.photoUrls!.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(8),
              child: GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: post.photoUrls!.length,
                itemBuilder: (context, index) {
                  final String imageUrl = post.photoUrls![index]
                      .replaceAll('localhost:9000', '91.200.84.206/minio');
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PhotoViewer(
                            photoUrls: post.photoUrls!
                                .map((url) => url.replaceAll(
                                    'localhost:9000', '91.200.84.206/minio'))
                                .toList(),
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: customCacheManager,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) =>
                            Icon(Icons.error, color: Colors.red),
                        // Оптимизация загрузки фото
                        fadeInDuration: Duration(milliseconds: 300),
                        width: 100,
                        height: 100,
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        post.likedByCurrentUser
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color:
                            post.likedByCurrentUser ? Colors.red : Colors.grey,
                      ),
                      onPressed: () => widget.likePost(post.id),
                    ),
                    Text(
                      '${post.likesCount} лайков',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.comment, color: Colors.grey),
                      onPressed: () {
                        widget.webSocketService.disconnect();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                PostDetailsScreen(postId: post.id),
                          ),
                        ).then((_) {
                          widget.webSocketService.switchToFeed();
                          widget.loadPosts();
                        });
                      },
                    ),
                    Text(
                      '${post.commentsCount} комментариев',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blueAccent),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Roboto',
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
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
