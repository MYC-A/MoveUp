import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/RoutePoint.dart';
import 'package:flutter_application_1/models/RunningRoute.dart';
import 'package:flutter_application_1/services/StorageService.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models_api/post.dart';
import '../services_api/post_service.dart';
import '../services_api/web_socket_channel.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';

class PostDetailsScreen extends StatefulWidget {
  final int postId;

  const PostDetailsScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _PostDetailsScreenState createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final PostService _postService = PostService();
  final WebSocketService _webSocketService = WebSocketService();
  final LkUsersService _lkUsersService = LkUsersService();
  late Post _post;
  bool _isLoading = true;
  bool _isLoadingComments = false;
  List<Comment> _comments = [];
  bool _allCommentsLoaded = false;
  int _skipComments = 0;
  final int _limitComments = 20;
  int? _currentUserId;
  String? _currentUserAvatarUrl;
  String? _currentUserFullName;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final MapController _mapController;
  bool _isExpanded = false; // Состояние для раскрытия текста

  // Единый CacheManager для приложения
  final customCacheManager = CacheManager(
    Config(
      'customCacheKey',
      stalePeriod: Duration(days: 7),
      maxNrOfCacheObjects: 100,
    ),
  );

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadCurrentUserData();
    _loadPostDetails();
    _webSocketService.switchToPost(widget.postId);
    _webSocketService.setUpdateCallback(_handleWebSocketUpdate);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    _commentController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingComments &&
        !_allCommentsLoaded) {
      _loadComments();
    }
  }

  Future<void> _loadCurrentUserData() async {
    try {
      final userId = await _postService.getCurrentUserId();
      final profile = await _lkUsersService.fetchUserProfile(userId);
      setState(() {
        _currentUserId = userId;
        _currentUserAvatarUrl = profile['user']['avatar_url']
            ?.replaceAll('localhost:9000', '91.200.84.206/minio');
        _currentUserFullName = profile['user']['full_name'];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки данных пользователя: $e')),
      );
    }
  }

  Future<void> _loadPostDetails() async {
    try {
      final post = await _postService.getPostDetails(widget.postId);
      setState(() {
        _post = post;
        _isLoading = false;
        _comments.clear();
        _skipComments = 0;
        _allCommentsLoaded = false;
      });
      _loadComments();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки поста: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadComments() async {
    if (_isLoadingComments || _allCommentsLoaded) return;

    setState(() {
      _isLoadingComments = true;
    });

    try {
      final comments = await _postService.getComments(
          widget.postId, _skipComments, _limitComments);

      final newComments = <Comment>[];
      for (var comment in comments) {
        var updatedComment = comment;
        if (comment.userAvatarUrl == null || comment.userAvatarUrl!.isEmpty) {
          final avatarUrl = await _fetchUserAvatar(comment.userId);
          updatedComment = Comment(
            id: comment.id,
            userId: comment.userId,
            content: comment.content,
            createdAt: comment.createdAt,
            userFullName: comment.userFullName,
            userAvatarUrl: avatarUrl,
          );
        }
        if (!_comments.any((existing) => existing.id == comment.id)) {
          newComments.add(updatedComment);
        }
      }

      setState(() {
        _comments.addAll(newComments);
        _allCommentsLoaded = comments.length < _limitComments;
        _skipComments += _limitComments;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки комментариев: $e')),
      );
    } finally {
      setState(() {
        _isLoadingComments = false;
      });
    }
  }

  Future<String?> _fetchUserAvatar(int userId) async {
    try {
      final profile = await _lkUsersService.fetchUserProfile(userId);
      return profile['user']['avatar_url']
          ?.replaceAll('localhost:9000', '91.200.84.206/minio');
    } catch (e) {
      print('Ошибка загрузки аватарки пользователя $userId: $e');
      return null;
    }
  }

  void _handleWebSocketUpdate(Map<String, dynamic> update) async {
    if (update['post_id'] == widget.postId) {
      if (update['type'] == 'comment') {
        final commentJson = update['comment'];
        if (commentJson['user_id'] == _currentUserId) {
          commentJson['user'] = {
            'avatar_url': _currentUserAvatarUrl,
            'username': _currentUserFullName ?? 'Пользователь',
          };
        } else if (commentJson['user'] == null ||
            commentJson['user']['avatar_url'] == null ||
            commentJson['user']['avatar_url'].isEmpty) {
          final avatarUrl = await _fetchUserAvatar(commentJson['user_id']);
          commentJson['user'] = {
            'avatar_url': avatarUrl?.replaceAll(
                    'localhost:9000', '91.200.84.206/minio') ??
                '',
            'username': commentJson['user']?['username'] ?? 'Пользователь',
          };
        }
      }

      setState(() {
        switch (update['type']) {
          case 'like':
            _post.likesCount = update['likes_count'];
            if (update['user_id'] == _currentUserId) {
              _post.likedByCurrentUser = update['liked'];
            }
            break;
          case 'comment':
            final newComment = Comment.fromJson(update['comment']);
            if (!_comments.any((c) => c.id == newComment.id)) {
              _post.commentsCount += 1;
              _comments.add(newComment);
            }
            break;
        }
      });

      if (update['type'] == 'comment') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    }
  }

  Future<void> _likePost() async {
    try {
      await _postService.likePost(widget.postId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка лайка: $e')),
      );
    }
  }

  Future<void> _addComment() async {
    final content = _commentController.text.trim();
    if (content.isNotEmpty) {
      try {
        await _postService.addComment(widget.postId, content);
        _commentController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Комментарий добавлен')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _zoomToRoute(List<dynamic> routeData) {
    if (routeData.isEmpty) return;

    if (routeData.length == 1) {
      final point = LatLng(routeData[0]['latitude'], routeData[0]['longitude']);
      _mapController.move(point, 14.0);
    } else {
      final bounds = LatLngBounds.fromPoints(
        routeData
            .map((point) => LatLng(point['latitude'], point['longitude']))
            .toList(),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(40)),
      );
    }
  }

  Future<void> _saveRouteFromPost() async {
    StorageService _storageService = StorageService();

    if (_post.routeData == null || _post.routeData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Маршрут отсутствует в этом посте')),
      );
      return;
    }

    try {
      List<RoutePoint> points = (_post.routeData as List<dynamic>).map((point) {
        return RoutePoint(
          coordinates: LatLng(point['latitude'], point['longitude']),
          timestamp: DateTime.parse(point['timestamp']),
        );
      }).toList();

      RunningRoute route = RunningRoute(
        id: _post.id.toString(),
        name: _post.content.isNotEmpty ? _post.content : 'Маршрут ${_post.id}',
        points: points,
        distance: _post.distance ?? 0.0,
        date: DateTime.parse(_post.createdAt.toString()),
        duration: Duration(seconds: _post.duration ?? 0),
        description: _post.content,
        is_downloaded: 1,
      );

      await _storageService.downloadRoute(route);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Маршрут сохранен успешно')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при сохранении маршрута: $e')),
      );
    }
  }

  // Форматирование длительности (секунды -> часы:минуты:секунды)
  String _formatDuration(int seconds) {
    if (seconds == 0) return '0:00';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Форматирование расстояния (метры -> километры)
  String _formatDistance(double meters) {
    if (meters == 0) return '0.00 км';
    final kilometers = meters / 1000;
    return '${kilometers.toStringAsFixed(2)} км';
  }

  // Форматирование времени начала маршрута
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    final postAvatarUrl = (_post.userAvatarUrl ?? '')
        .replaceAll('localhost:9000', '91.200.84.206/minio');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Детали поста',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: Icon(Icons.download, color: Colors.blueAccent),
            onPressed: _saveRouteFromPost,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: postAvatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(
                                  postAvatarUrl,
                                  cacheManager: customCacheManager,
                                )
                              : null,
                          child: postAvatarUrl.isEmpty
                              ? Icon(Icons.person, size: 20)
                              : null,
                          radius: 20,
                        ),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _post.userFullName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            Text(
                              Helper.formatDateTime(_post.createdAt),
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_post.routeData != null && _post.routeData.isNotEmpty)
                    Container(
                      height: 300,
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: LatLng(
                              _post.routeData[0]['latitude'],
                              _post.routeData[0]['longitude'],
                            ),
                            initialZoom: 13.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                            onMapReady: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                Future.delayed(Duration(milliseconds: 500), () {
                                  _zoomToRoute(_post.routeData);
                                });
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: ['a', 'b', 'c'],
                            ),
                            if (_post.routeData.length == 1)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                        _post.routeData[0]['latitude'],
                                        _post.routeData[0]['longitude']),
                                    child: const Icon(
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
                                    points: _post.routeData
                                        .map((point) => LatLng(
                                            point['latitude'],
                                            point['longitude']))
                                        .toList(),
                                    strokeWidth: 4.0,
                                    color: Colors.orange,
                                  ),
                                ],
                              ),
                            if (_post.routeData.length > 1)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                        _post.routeData.first['latitude'],
                                        _post.routeData.first['longitude']),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.directions_run,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  Marker(
                                    point: LatLng(
                                        _post.routeData.last['latitude'],
                                        _post.routeData.last['longitude']),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
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
                  if (_post.routeData != null &&
                      _post.routeData.isNotEmpty &&
                      (_post.distance > 0 || _post.duration > 0))
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _InfoTile(
                            icon: Icons.timer,
                            label: 'Время',
                            value: _formatDuration(_post.duration),
                          ),
                          _InfoTile(
                            icon: Icons.directions_run,
                            label: 'Дистанция',
                            value: _formatDistance(_post.distance),
                          ),
                          _InfoTile(
                            icon: Icons.calendar_today,
                            label: 'Начало',
                            value: _formatStartTime(
                                _post.routeData, _post.createdAt.toString()),
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
                          _post.content,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontFamily: 'Roboto',
                          ),
                          maxLines: _isExpanded ? null : 3,
                          overflow: _isExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                        if (_post.content.length > 100)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isExpanded = !_isExpanded;
                              });
                            },
                            child: Text(
                              _isExpanded ? 'Свернуть' : 'Показать полностью',
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
                  if (_post.photoUrls != null && _post.photoUrls!.isNotEmpty)
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
                        itemCount: _post.photoUrls!.length,
                        itemBuilder: (context, index) {
                          final String imageUrl = _post.photoUrls![index]
                              .replaceAll(
                                  'localhost:9000', '91.200.84.206/minio');
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PhotoViewer(
                                    photoUrls: _post.photoUrls!
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
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) =>
                                    Icon(Icons.error, color: Colors.red),
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
                                _post.likedByCurrentUser
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _post.likedByCurrentUser
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              onPressed: _likePost,
                            ),
                            Text(
                              '${_post.likesCount} лайков',
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
                              icon: Icon(Icons.comment, color: Colors.grey),
                              onPressed: () {
                                _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                            Text(
                              '${_post.commentsCount} комментариев',
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
                  Divider(color: Colors.grey[300]),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Комментарии',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: _comments.length + (_isLoadingComments ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _comments.length) {
                        return Center(
                          child: CircularProgressIndicator(
                              color: Colors.blueAccent),
                        );
                      }
                      final comment = _comments[index];
                      final commentAvatarUrl = (comment.userAvatarUrl ?? '')
                          .replaceAll('localhost:9000', '91.200.84.206/minio');

                      return Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundImage: commentAvatarUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      commentAvatarUrl,
                                      cacheManager: customCacheManager,
                                    )
                                  : null,
                              child: commentAvatarUrl.isEmpty
                                  ? Icon(Icons.person, size: 20)
                                  : null,
                              radius: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    comment.userFullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                  Text(
                                    comment.content,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Введите комментарий...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: Colors.black, fontFamily: 'Roboto'),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Вспомогательный виджет для отображения информации о маршруте
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

class PhotoViewer extends StatelessWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoViewer({
    Key? key,
    required this.photoUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: PhotoViewGallery.builder(
        itemCount: photoUrls.length,
        builder: (context, index) {
          final imageUrl = photoUrls[index]
            ..replaceAll('localhost:9000', '91.200.84.206/minio');
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(
              imageUrl,
              cacheManager: CacheManager(
                Config(
                  'customCacheKey',
                  stalePeriod: Duration(days: 7),
                  maxNrOfCacheObjects: 100,
                ),
              ),
            ),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          );
        },
        scrollPhysics: BouncingScrollPhysics(),
        backgroundDecoration: BoxDecoration(
          color: Colors.white,
        ),
        pageController: PageController(initialPage: initialIndex),
        onPageChanged: (index) {},
      ),
    );
  }
}
