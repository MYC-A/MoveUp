import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/services_api/post_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import '../services_api/web_socket_channel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/models_api/post.dart';
import 'package:flutter_application_1/screens_api/FullScreenMap.dart';
import 'package:flutter_application_1/screens_api/feed_screen.dart';
import 'dart:async';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/theme/app_colors.dart';

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
  String? _loadError;

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
      _loadError = null;
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
                url.replaceAll(
                    'localhost:9000', AppConfig.mediaBaseUrlWithoutScheme),
                cacheManager: customCacheManager,
              ),
              context,
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Первая загрузка с пустым списком — показываем состояние ошибки;
      // ошибка при догрузке — ненавязчивый тост.
      if (posts.isEmpty) {
        setState(() => _loadError = e.toString());
      } else {
        showApiError(context, e);
      }
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
              final commentsCount = update['comments_count'];
              post.commentsCount = commentsCount is num
                  ? commentsCount.toInt()
                  : post.commentsCount + 1;
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
    final index = posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final post = posts[index];
    final prevLiked = post.likedByCurrentUser;
    final prevCount = post.likesCount;

    setState(() {
      post.likedByCurrentUser = !prevLiked;
      post.likesCount =
          (prevCount + (post.likedByCurrentUser ? 1 : -1)).clamp(0, 1 << 31);
      posts = List.from(posts);
    });

    try {
      final res = await postService.likePost(postId);
      if (!mounted) return;
      setState(() {
        post.likesCount = res.likesCount;
        post.likedByCurrentUser = res.liked;
        posts = List.from(posts);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post.likedByCurrentUser = prevLiked;
        post.likesCount = prevCount;
        posts = List.from(posts);
      });
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      if (isLoading) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: AppLoading(label: 'Загружаем публикации'),
          ),
        );
      }
      if (_loadError != null) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: AppErrorState(
              message: _loadError,
              onRetry: _loadPosts,
            ),
          ),
        );
      }
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: AppEmptyState(
            icon: Icons.article_outlined,
            title: 'Публикаций пока нет',
            message: 'Здесь появятся посты пользователя.',
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < posts.length) {
            final post = posts[index];
            return PostItem(
              post: post,
              mapController: index < mapControllers.length
                  ? mapControllers[index]
                  : MapController(),
              onMapTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FullScreenMap(routeData: post.routeData),
                  ),
                );
              },
              isValidRoute: (routeData) => routeData.isNotEmpty,
              webSocketService: webSocketService,
              loadPosts: _loadPosts,
              likePost: _likePost,
              currentUserId: currentUserId,
            );
          } else if (hasMore) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(color: AppColors.primary),
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

