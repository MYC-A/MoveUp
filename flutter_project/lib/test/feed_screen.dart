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

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _webSocketService.switchToFeed();
    _webSocketService.setUpdateCallback(_handleWebSocketUpdate);
  }

  @override
  void dispose() {
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
                        // Заголовок поста
                        ListTile(
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage(post.userAvatarUrl ??
                                'https://via.placeholder.com/150'),
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

                        // Маршрут на карте
                        if (post.routeData.isNotEmpty)
                          Container(
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
                                options: MapOptions(
                                  initialCenter:
                                      _calculateCenter(post.routeData),
                                  initialZoom: _calculateZoom(post.routeData),
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

                        // Фотографии поста
                        if (post.photoUrls != null &&
                            post.photoUrls!.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.all(8),
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
                                        'localhost:9000', '192.168.63.1:9000');

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PhotoViewer(
                                          photoUrls: post.photoUrls!
                                              .map((url) => url.replaceAll(
                                                  'localhost:9000',
                                                  '192.168.63.1:9000'))
                                              .toList(),
                                          initialIndex: index,
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Контент поста
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
                                    post.isExpanded
                                        ? 'Свернуть'
                                        : 'Показать полностью',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Лайки и комментарии
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
                                    ),
                                    onPressed: () => _likePost(post.id),
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
                                    icon:
                                        Icon(Icons.comment, color: Colors.grey),
                                    onPressed: () {
                                      _webSocketService.disconnect();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PostDetailsScreen(
                                            postId: post.id,
                                          ),
                                        ),
                                      ).then((_) {
                                        _webSocketService.switchToFeed();
                                        _loadPosts();
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

  LatLng _calculateCenter(List<dynamic> routeData) {
    double minLat = routeData[0]['latitude'];
    double maxLat = routeData[0]['latitude'];
    double minLng = routeData[0]['longitude'];
    double maxLng = routeData[0]['longitude'];

    for (var point in routeData) {
      if (point['latitude'] < minLat) minLat = point['latitude'];
      if (point['latitude'] > maxLat) maxLat = point['latitude'];
      if (point['longitude'] < minLng) minLng = point['longitude'];
      if (point['longitude'] > maxLng) maxLng = point['longitude'];
    }

    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  double _calculateZoom(List<dynamic> routeData) {
    double minLat = routeData[0]['latitude'];
    double maxLat = routeData[0]['latitude'];
    double minLng = routeData[0]['longitude'];
    double maxLng = routeData[0]['longitude'];

    for (var point in routeData) {
      if (point['latitude'] < minLat) minLat = point['latitude'];
      if (point['latitude'] > maxLat) maxLat = point['latitude'];
      if (point['longitude'] < minLng) minLng = point['longitude'];
      if (point['longitude'] > maxLng) maxLng = point['longitude'];
    }

    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;

    double zoomLevel = 13.0;

    if (latDiff > 0.1 || lngDiff > 0.1) {
      zoomLevel = 10.0;
    } else if (latDiff > 0.05 || lngDiff > 0.05) {
      zoomLevel = 12.0;
    }

    return zoomLevel;
  }
}

// Виджет для просмотра фотографий
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: PhotoViewGallery.builder(
        itemCount: photoUrls.length,
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(photoUrls[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          );
        },
        scrollPhysics: BouncingScrollPhysics(),
        backgroundDecoration: BoxDecoration(
          color: Colors.black,
        ),
        pageController: PageController(initialPage: initialIndex),
        onPageChanged: (index) {
          // Обработка изменения страницы
        },
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
