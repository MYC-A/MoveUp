import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/screens_api/PostDetails_screen.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/screens_api/event_screen.dart';
import 'package:flutter_application_1/screens_api/profile_screen.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services_api/post_service.dart';
import '../models_api/post.dart';
import '../services_api/web_socket_channel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/screens_api/PostDetails_screen.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/screens_api/event_screen.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services_api/post_service.dart';
import '../models_api/post.dart';
import '../services_api/web_socket_channel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _selectedIndex = 0;
  final PostService _postService = PostService();
  final WebSocketService _webSocketService = WebSocketService();
  List<Post> _posts = [];
  bool _isLoading = false;
  final List<MapController> _mapControllers = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _webSocketService.switchToFeed();
    _webSocketService.setUpdateCallback(_handleWebSocketUpdate);
  }

  @override
  void dispose() {
    for (var controller in _mapControllers) {
      controller.dispose();
    }
    _webSocketService.disconnect();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final posts = await _postService.getFeed(0, 20);
      setState(() {
        _posts = posts;
        _mapControllers.clear();
        _mapControllers
            .addAll(List.generate(posts.length, (index) => MapController()));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки постов: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleWebSocketUpdate(Map<String, dynamic> update) {
    setState(() {
      final postId = update['post_id'];
      final postIndex = _posts.indexWhere((post) => post.id == postId);
      if (postIndex != -1) {
        final post = _posts[postIndex];
        switch (update['type']) {
          case 'like':
            post.likesCount = update['likes_count'];
            post.likedByCurrentUser = update['liked'];
            break;
          case 'comment':
            post.commentsCount += 1;
            break;
          case 'photo':
            break;
        }
        _posts[postIndex] = post;
      }
    });
  }

  Future<void> _likePost(int postId) async {
    try {
      await _postService.likePost(postId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка лайка: $e')),
      );
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => EventScreen()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfileScreen()),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatListScreen()),
      );
    }
  }

  bool _isValidRoute(List<dynamic> routeData) {
    if (routeData.isEmpty) return false;

    for (var point in routeData) {
      final lat = point['latitude'];
      final lng = point['longitude'];
      if (lat == 0.0 && lng == 0.0) return false;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    }

    return routeData.length >= 2;
  }

  void _zoomToRoute(List<dynamic> routeData, MapController mapController) {
    if (!_isValidRoute(routeData)) return;

    final bounds = LatLngBounds.fromPoints(
      routeData
          .map((point) => LatLng(point['latitude'], point['longitude']))
          .toList(),
    );

    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
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
            fontSize: 24,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.orange))
            : ListView.builder(
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return PostItem(
                    post: post,
                    mapController: _mapControllers[index],
                    onMapTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullScreenMap(
                            routeData: post.routeData,
                            mapController: _mapControllers[
                                index], // Передаем MapController
                          ),
                        ),
                      );
                    },
                    isValidRoute: _isValidRoute,
                    zoomToRoute: _zoomToRoute,
                    webSocketService: _webSocketService,
                    loadPosts: _loadPosts,
                    likePost: _likePost,
                  );
                },
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_run),
            label: 'Активности',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Мероприятия',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Чат',
          ),
        ],
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
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
  }) : super(key: key);

  @override
  _PostItemState createState() => _PostItemState();
}

class _PostItemState extends State<PostItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = widget.post;
    return Container(
      margin: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: CachedNetworkImageProvider(
                post.userAvatarUrl ?? 'https://via.placeholder.com/150',
              ),
            ),
            title: Text(
              post.userFullName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              post.createdAt.toString(),
              style: TextStyle(color: Colors.grey),
            ),
          ),
          if (post.routeData.isNotEmpty && widget.isValidRoute(post.routeData))
            VisibilityDetector(
              key: Key('map_${post.id}'),
              onVisibilityChanged: (info) {
                if (info.visibleFraction == 0) {
                  // Карта не видна
                } else {
                  // Карта видна
                }
              },
              child: GestureDetector(
                onTap: widget.onMapTap, // Обработчик нажатия на карту
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
                        interactionOptions: InteractionOptions(
                          flags:
                              InteractiveFlag.none, // Отключаем взаимодействие
                        ),
                        initialCenter: LatLng(
                          post.routeData[0]['latitude'],
                          post.routeData[0]['longitude'],
                        ),
                        initialZoom: 13.0,
                        onMapReady: () {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            widget.zoomToRoute(
                                post.routeData, widget.mapController);
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: ['a', 'b', 'c'],
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: post.routeData
                                  .map((point) => LatLng(
                                        point['latitude'],
                                        point['longitude'],
                                      ))
                                  .toList(),
                              strokeWidth: 4.0,
                              color: Colors.orange,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
                      .replaceAll('localhost:9000', '10.0.2.2:9000');

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PhotoViewer(
                            photoUrls: post.photoUrls!
                                .map((url) => url.replaceAll(
                                    'localhost:9000', '10.0.2.2:9000'))
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
                            CircularProgressIndicator(),
                        errorWidget: (context, url, error) => Icon(Icons.error),
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content,
                  style: TextStyle(fontSize: 16),
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
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
                      style: TextStyle(color: Colors.grey),
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
                            builder: (context) => PostDetailsScreen(
                              postId: post.id,
                            ),
                          ),
                        ).then((_) {
                          widget.webSocketService.switchToFeed();
                          widget.loadPosts();
                        });
                      },
                    ),
                    Text(
                      '${post.commentsCount} комментариев',
                      style: TextStyle(color: Colors.grey),
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

class FullScreenMap extends StatelessWidget {
  final List<dynamic> routeData;
  final MapController mapController;

  const FullScreenMap({
    Key? key,
    required this.routeData,
    required this.mapController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Карта маршрута'),
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: LatLng(
            routeData[0]['latitude'],
            routeData[0]['longitude'],
          ),
          initialZoom: 13.0,
          onMapReady: () {
            final bounds = LatLngBounds.fromPoints(
              routeData
                  .map((point) => LatLng(point['latitude'], point['longitude']))
                  .toList(),
            );

            mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: EdgeInsets.all(50),
              ),
            );
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: routeData
                    .map((point) => LatLng(
                          point['latitude'],
                          point['longitude'],
                        ))
                    .toList(),
                strokeWidth: 4.0,
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
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
