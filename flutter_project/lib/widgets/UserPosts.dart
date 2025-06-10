import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/PostDetails_screen.dart';
import 'package:flutter_application_1/services_api/post_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import '../services_api/web_socket_channel.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/models_api/post.dart';
import 'package:flutter_application_1/screens_api/FullScreenMap.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'dart:async';

class UserPosts extends StatefulWidget {
  final int userId;
  final ScrollController scrollController;

  UserPosts({required this.userId, required this.scrollController});

  @override
  _UserPostsState createState() => _UserPostsState();
}

class _UserPostsState extends State<UserPosts> {
  final LkUsersService lkService = LkUsersService();
  final PostService postService = PostService();
  final WebSocketService webSocketService = WebSocketService();
  List<Post> posts = [];
  List<MapController> mapControllers = [];
  int skip = 0;
  int limit = 5;
  bool isLoading = false;
  bool hasMore = true;
  int? currentUserId;
  Timer? debounceTimer;
  Timer? pollTimer;

  // Единый CacheManager для приложения
  final customCacheManager = CacheManager(
    Config(
      'customCacheKey',
      stalePeriod: Duration(days: 14),
      maxNrOfCacheObjects: 200,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _loadPosts();
    widget.scrollController.addListener(_onScroll);
    webSocketService.connectToFeed();
    webSocketService.setUpdateCallback(_handleWebSocketUpdate);
    // Периодический опрос каждые 30 секунд
    pollTimer = Timer.periodic(Duration(seconds: 30), (_) => _pollPosts());
  }

  @override
  void dispose() {
    debounceTimer?.cancel();
    pollTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    webSocketService.disconnect();
    for (var controller in mapControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final userId = await postService.getCurrentUserId();
      setState(() {
        currentUserId = userId;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки ID текущего пользователя: $e');
    }
  }

  Future<void> _loadPosts() async {
    if (isLoading || !hasMore) return;

    setState(() {
      isLoading = true;
    });

    try {
      final newPosts =
          await lkService.fetchUserPosts(widget.userId, skip, limit);
      final newPostObjects =
          newPosts.map((json) => Post.fromJson(json)).toList();
      setState(() {
        posts.addAll(newPostObjects);
        mapControllers.addAll(
            List.generate(newPostObjects.length, (_) => MapController()));
        skip += newPostObjects.length;
        hasMore = newPosts.length == limit;
      });
      // Предзагрузка изображений для новых постов
      for (var post in newPostObjects) {
        // Используем Post вместо Map
        if (post.photoUrls != null && post.photoUrls!.isNotEmpty) {
          for (var url in post.photoUrls!) {
            precacheImage(
              CachedNetworkImageProvider(
                url.replaceAll('localhost:9000', '91.200.84.206/minio'),
                cacheManager: customCacheManager,
              ),
              context,
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке постов: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _pollPosts() async {
    try {
      final newPosts =
          await lkService.fetchUserPosts(widget.userId, 0, posts.length);
      setState(() {
        for (var newPost in newPosts) {
          final index = posts.indexWhere((p) => p.id == newPost['id']);
          if (index != -1) {
            posts[index].commentsCount = newPost['comments_count'] ?? 0;
            posts[index].likesCount = newPost['likes_count'] ?? 0;
            posts = List.from(posts);
          }
        }
      });
    } catch (e) {
      debugPrint('Ошибка опроса постов: $e');
    }
  }

  void _onScroll() {
    if (widget.scrollController.position.pixels >=
            widget.scrollController.position.maxScrollExtent - 100 &&
        !isLoading &&
        hasMore) {
      _loadPosts();
    }
  }

  void _handleWebSocketUpdate(Map<String, dynamic> update) {
    debugPrint('Получено WebSocket-обновление: $update');
    debounceTimer?.cancel();
    debounceTimer = Timer(Duration(milliseconds: 100), () {
      setState(() {
        final postId = update['post_id'];
        final postIndex = posts.indexWhere((post) => post.id == postId);
        if (postIndex != -1) {
          final post = posts[postIndex];
          switch (update['type']) {
            case 'like':
              post.likesCount = update['likes_count'] ?? post.likesCount;
              if (update['user_id'] == currentUserId) {
                post.likedByCurrentUser = update['liked'] ?? false;
              }
              posts = List.from(posts);
              debugPrint(
                  'Обновлён лайк для поста $postId: likesCount=${post.likesCount}, likedByCurrentUser=${post.likedByCurrentUser}');
              break;
            case 'comment':
              post.commentsCount += 1;
              posts = List.from(posts);
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
      await postService.likePost(postId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка лайка: $e')),
      );
    }
  }

  bool _isValidRoute(List<dynamic> routeData) {
    return routeData.isNotEmpty;
  }

  void _zoomToRoute(List<dynamic> routeData, MapController mapController) {
    if (!_isValidRoute(routeData)) return;
    // Упрощение маршрута для больших данных
    final simplifiedRoute = routeData.length > 100
        ? (routeData
            .asMap()
            .entries
            .where((e) => e.key % 5 == 0)
            .map((e) => e.value)
            .toList()
          ..add(routeData.last))
        : routeData;
    if (simplifiedRoute.length == 1) {
      final point = LatLng(simplifiedRoute[0]['latitude'] as double,
          simplifiedRoute[0]['longitude'] as double);
      mapController.move(point, 15.0);
    } else {
      final bounds = LatLngBounds.fromPoints(
        simplifiedRoute
            .map((point) => LatLng(
                point['latitude'] as double, point['longitude'] as double))
            .toList(),
      );
      mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50)),
      );
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < posts.length) {
            final post = posts[index];
            final String avatarUrl =
                (post.userAvatarUrl ?? 'https://via.placeholder.com/150')
                    .replaceAll('localhost:9000', '91.200.84.206/minio');

            return Card(
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: CachedNetworkImageProvider(
                          avatarUrl,
                          cacheManager: customCacheManager,
                        ),
                        onBackgroundImageError: (exception, stackTrace) {
                          debugPrint('Ошибка загрузки аватарки: $exception');
                        },
                        radius: 20,
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
                          color: Colors.grey,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.map, color: Colors.blueAccent),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  FullScreenMap(routeData: post.routeData),
                            ),
                          );
                        },
                      ),
                    ),
                    if (post.routeData.isNotEmpty &&
                        _isValidRoute(post.routeData))
                      VisibilityDetector(
                        key: Key('map_${post.id}'),
                        onVisibilityChanged: (info) {
                          if (info.visibleFraction > 0) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _zoomToRoute(
                                  post.routeData, mapControllers[index]);
                            });
                          }
                        },
                        child: Container(
                          height: 200,
                          margin:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                              mapController: mapControllers[index],
                              options: MapOptions(
                                initialCenter: LatLng(
                                  post.routeData[0]['latitude'] as double,
                                  post.routeData[0]['longitude'] as double,
                                ),
                                initialZoom: 13.0,
                                interactionOptions: InteractionOptions(
                                    flags: InteractiveFlag.none),
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
                                        point: LatLng(
                                          post.routeData[0]['latitude']
                                              as double,
                                          post.routeData[0]['longitude']
                                              as double,
                                        ),
                                        child: Icon(
                                          Icons.location_pin,
                                          color: Colors.red,
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
                                            .map<LatLng>((point) => LatLng(
                                                  point['latitude'] as double,
                                                  point['longitude'] as double,
                                                ))
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
                                        point: LatLng(
                                          post.routeData.first['latitude']
                                              as double,
                                          post.routeData.first['longitude']
                                              as double,
                                        ),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.directions_run,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                      Marker(
                                        point: LatLng(
                                          post.routeData.last['latitude']
                                              as double,
                                          post.routeData.last['longitude']
                                              as double,
                                        ),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.flag,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (post.routeData.isNotEmpty &&
                        _isValidRoute(post.routeData) &&
                        (post.distance > 0 || post.duration > 0))
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            style:
                                TextStyle(fontSize: 16, fontFamily: 'Roboto'),
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
                                post.isExpanded
                                    ? 'Свернуть'
                                    : 'Показать полностью',
                                style: TextStyle(
                                  color: Colors.blueAccent,
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: post.photoUrls!.length,
                          itemBuilder: (context, index) {
                            final String imageUrl = post.photoUrls![index]
                                .replaceAll(
                                    'localhost:9000', '91.200.84.206/minio');

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PhotoViewer(
                                      photoUrls: post.photoUrls!
                                          .map((url) => url.replaceAll(
                                              'localhost:9000',
                                              '91.200.84.206/minio'))
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
                                  placeholder: (context, url) => Center(
                                      child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) =>
                                      Icon(Icons.error, color: Colors.red),
                                  memCacheWidth: 300,
                                  memCacheHeight: 300,
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
                                  color: post.likedByCurrentUser
                                      ? Colors.red
                                      : Colors.grey,
                                  size: 24,
                                ),
                                onPressed: () => _likePost(post.id),
                              ),
                              Text(
                                '${post.likesCount}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'лайков',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.comment,
                                    color: Colors.blueAccent, size: 24),
                                onPressed: () {
                                  webSocketService.disconnect();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PostDetailsScreen(postId: post.id!),
                                    ),
                                  ).then((_) {
                                    webSocketService.connectToFeed();
                                    _loadPosts();
                                  });
                                },
                              ),
                              Text(
                                '${post.commentsCount}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'комментариев',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (hasMore) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            );
          } else {
            return SizedBox.shrink();
          }
        },
        childCount: posts.length + (hasMore ? 1 : 0),
        addAutomaticKeepAlives: true,
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
        SizedBox(height: 8),
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
