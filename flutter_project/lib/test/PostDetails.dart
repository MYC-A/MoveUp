import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models_api/post.dart';
import '../services_api/post_service.dart';
import '../services_api/web_socket_channel.dart';

class PostDetailsScreen extends StatefulWidget {
  final int postId; // Обязательный параметр

  const PostDetailsScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _PostDetailsScreenState createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final PostService _postService = PostService();
  final WebSocketService _webSocketService = WebSocketService();
  late Post _post;
  bool _isLoading = true; // Для загрузки данных поста
  bool _isLoadingComments = false; // Для загрузки комментариев
  List<Comment> _comments = [];
  bool _allCommentsLoaded = false;
  int _skipComments = 0; // Для пагинации комментариев
  final int _limitComments = 20; // Лимит комментариев за один запрос
  int? _currentUserId; // ID текущего пользователя
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId(); // Загружаем ID текущего пользователя
    _loadPostDetails();
    _loadComments();
    _webSocketService
        .switchToPost(widget.postId); // Подключаемся к WebSocket для поста
    _webSocketService.setUpdateCallback(_handleWebSocketUpdate);
  }

  @override
  void dispose() {
    _webSocketService.disconnect(); // Закрываем соединение
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Загрузка ID текущего пользователя
  Future<void> _loadCurrentUserId() async {
    try {
      final userId = await _postService.getCurrentUserId();
      setState(() {
        _currentUserId = userId;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки ID пользователя: $e')),
      );
    }
  }

  // Загрузка данных поста
  Future<void> _loadPostDetails() async {
    try {
      final post = await _postService.getPostDetails(widget.postId);
      setState(() {
        _post = post;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки поста: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Загрузка комментариев
  Future<void> _loadComments() async {
    if (_isLoadingComments || _allCommentsLoaded) return;

    setState(() {
      _isLoadingComments = true;
    });

    try {
      final comments = await _postService.getComments(
          widget.postId, _skipComments, _limitComments);
      setState(() {
        _comments.addAll(comments);
        _allCommentsLoaded = comments.isEmpty;
        _skipComments +=
            _limitComments; // Увеличиваем skip для следующего запроса
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

  // Обработка обновлений от WebSocket
  void _handleWebSocketUpdate(Map<String, dynamic> update) {
    if (update['post_id'] == widget.postId) {
      setState(() {
        switch (update['type']) {
          case 'like':
            _post.likesCount = update['likes_count'];
            // Обновляем состояние лайка только для текущего пользователя
            if (update['user_id'] == _currentUserId) {
              _post.likedByCurrentUser = update['liked'];
            }
            break;
          case 'comment':
            _post.commentsCount += 1;
            _comments
                .add(Comment.fromJson(update['comment'])); // Добавляем в конец
            break;
        }
      });

      // Прокручиваем страницу вниз, если добавлен новый комментарий
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

  // Лайк поста
  Future<void> _likePost() async {
    try {
      await _postService.likePost(widget.postId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка лайка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Загрузка...'),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Детали поста'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(_post.userAvatarUrl ??
                          'https://via.placeholder.com/150'),
                    ),
                    title: Text(
                      _post.userFullName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _post.createdAt.toString(),
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  if (_post.routeData.isNotEmpty)
                    Container(
                      height: 250,
                      margin: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              _post.routeData[0]['latitude'],
                              _post.routeData[0]['longitude'],
                            ),
                            initialZoom: 13.0,
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
                                  points: _post.routeData
                                      .map((point) => LatLng(
                                            point['latitude'],
                                            point['longitude'],
                                          ))
                                      .toList(),
                                  strokeWidth: 4.0,
                                  color: Colors.blue,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_post.photoUrls != null && _post.photoUrls!.isNotEmpty)
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _post.photoUrls!.length,
                        itemBuilder: (context, index) {
                          final String imageUrl = _post.photoUrls![index]
                              .replaceAll('localhost', '100.80.24.222');
                          return Padding(
                            padding: EdgeInsets.all(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      _post.content,
                      style: TextStyle(fontSize: 16),
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
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.comment, color: Colors.grey),
                              onPressed: () {
                                // Прокручиваем вниз при нажатии на иконку комментария
                                _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                            Text(
                              '${_post.commentsCount} комментариев',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Комментарии',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (!_isLoadingComments &&
                          !_allCommentsLoaded &&
                          scrollInfo.metrics.pixels ==
                              scrollInfo.metrics.maxScrollExtent) {
                        _loadComments(); // Загружаем новые комментарии
                      }
                      return true;
                    },
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount:
                          _comments.length + (_isLoadingComments ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _comments.length) {
                          return Center(child: CircularProgressIndicator());
                        }
                        final comment = _comments[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage(comment.userFullName),
                          ),
                          title: Text(comment.userFullName),
                          subtitle: Text(comment.content),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Поле ввода и кнопка для комментария
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Введите комментарий',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blue),
                  onPressed: () async {
                    final content = _commentController.text.trim();
                    if (content.isNotEmpty) {
                      try {
                        await _postService.addComment(widget.postId, content);
                        _commentController.clear(); // Очищаем поле ввода
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Комментарий добавлен')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
