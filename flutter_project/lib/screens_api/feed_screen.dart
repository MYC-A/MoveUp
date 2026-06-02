import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/RouteHistoryScreen.dart';
import 'package:flutter_application_1/screens_api/CreatePostWithoutRouteScreen.dart';
import 'package:flutter_application_1/screens_api/FullScreenMap.dart';
import '../services_api/post_service.dart';
import '../models_api/post.dart';
import '../services_api/web_socket_channel.dart';
import '../services_api/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

import 'package:flutter_application_1/widgets/feed/post_item.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  static const double _loadMoreThreshold = 200;

  final PageStorageBucket _bucket = PageStorageBucket();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
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
  Timer? _filterDebounceTimer;
  String? _loadError;
  bool _showFilters = false;
  String _routeFilter = 'any';
  String _photoFilter = 'any';

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
      });
    } catch (e) {
      debugPrint('Ошибка загрузки ID текущего пользователя: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filterDebounceTimer?.cancel();
    _searchController.dispose();
    _cityController.dispose();
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
          // Синхронизируем offset пагинации с реальным размером списка,
          // иначе следующая догрузка возьмёт неверный skip (пропуски/дубли).
          _skip = _posts.length;
          _hasMore = true;
        });
        debugPrint("Приложение свернуто, кэш частично очищен.");
      }
    }
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _cityController.text.trim().isNotEmpty ||
        _routeFilter != 'any' ||
        _photoFilter != 'any';
  }

  bool? get _hasRouteFilter {
    if (_routeFilter == 'route') return true;
    if (_routeFilter == 'plain') return false;
    return null;
  }

  bool? get _withPhotosFilter {
    if (_photoFilter == 'with') return true;
    if (_photoFilter == 'without') return false;
    return null;
  }

  void _scheduleFilterRefresh() {
    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadPosts(refresh: true);
    });
  }

  void _clearPostFilters() {
    _filterDebounceTimer?.cancel();
    _searchController.clear();
    _cityController.clear();
    setState(() {
      _routeFilter = 'any';
      _photoFilter = 'any';
    });
    _loadPosts(refresh: true);
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
      final fetched = await _postService.getFeed(
        _skip,
        _limit,
        query: _searchController.text,
        city: _cityController.text,
        hasRoute: _hasRouteFilter,
        withPhotos: _withPhotosFilter,
      );
      // Отсеиваем уже загруженные id — страховка от дублей в ленте.
      final existingIds = _posts.map((p) => p.id).toSet();
      final newPosts =
          fetched.where((p) => !existingIds.contains(p.id)).toList();
      setState(() {
        _posts.addAll(newPosts);
        _skip += _limit;
        // hasMore — по размеру ответа сервера, а не по числу уникальных.
        _hasMore = fetched.length == _limit;
        _mapControllers
            .addAll(List.generate(newPosts.length, (_) => MapController()));
        if (_posts.isNotEmpty) {
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
    if (_latestPostId == null || _hasActiveFilters) {
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
      final newPosts = await _postService.getFeed(
        0,
        _limit,
        query: _searchController.text,
        city: _cityController.text,
        hasRoute: _hasRouteFilter,
        withPhotos: _withPhotosFilter,
      );
      final newPostsToAdd =
          newPosts.where((post) => post.id > _latestPostId!).toList();
      if (!mounted) return;

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
          }
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
        // Удаление обрабатываем отдельно — пост мог быть удалён с другого устройства.
        if (update['type'] == 'post_deleted') {
          if (postIndex != -1) {
            _posts.removeAt(postIndex);
            if (postIndex < _mapControllers.length) {
              final removed = _mapControllers.removeAt(postIndex);
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => removed.dispose());
            }
            if (_skip > 0) _skip -= 1;
          }
          return;
        }
        if (postIndex != -1) {
          final post = _posts[postIndex];
          switch (update['type']) {
            case 'like':
              post.likesCount = update['likes_count'];
              if (update['user_id'] == _currentUserId) {
                post.likedByCurrentUser = update['liked'];
              }
              debugPrint(
                  'Обновлён лайк для поста $postId: likesCount=${post.likesCount}, likedByCurrentUser=${post.likedByCurrentUser}');
              break;
            case 'comment':
              final commentsCount = update['comments_count'];
              post.commentsCount = commentsCount is num
                  ? commentsCount.toInt()
                  : post.commentsCount + 1;
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
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final post = _posts[index];
    final prevLiked = post.likedByCurrentUser;
    final prevCount = post.likesCount;

    // Оптимистично обновляем сразу, чтобы счётчик менялся без перезагрузки.
    setState(() {
      post.likedByCurrentUser = !prevLiked;
      post.likesCount =
          (prevCount + (post.likedByCurrentUser ? 1 : -1)).clamp(0, 1 << 31);
    });

    try {
      final res = await _postService.likePost(postId);
      if (!mounted) return;
      // Сверяемся с авторитетным ответом сервера.
      setState(() {
        post.likesCount = res.likesCount;
        post.likedByCurrentUser = res.liked;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post.likedByCurrentUser = prevLiked;
        post.likesCount = prevCount;
      });
      showApiError(context, e);
    }
  }

  bool _isValidRoute(List<dynamic> routeData) {
    return routeData.isNotEmpty;
  }

  // Удаляет пост из локального списка вместе с его MapController.
  void _removePostById(int postId) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    setState(() {
      _posts.removeAt(index);
      if (index < _mapControllers.length) {
        final removed = _mapControllers.removeAt(index);
        // Диспозим после кадра — карта успеет демонтироваться.
        WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
      }
      // Держим offset пагинации в соответствии с реальным размером списка.
      if (_skip > 0) _skip -= 1;
    });
  }

  Future<void> _deletePost(Post post) async {
    try {
      await _postService.deletePost(post.id);
      if (!mounted) return;
      _removePostById(post.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост удалён')),
      );
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
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
      MaterialPageRoute(
        builder: (context) => RouteHistoryScreen(selectForPost: true),
      ),
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
          AppIconButton(
            icon: _showFilters
                ? Icons.filter_alt_rounded
                : Icons.filter_alt_outlined,
            tooltip: 'Фильтры постов',
            onPressed: () {
              setState(() => _showFilters = !_showFilters);
            },
          ),
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
        child: Column(
          children: [
            if (_showFilters) _buildFilterPanel(),
            Expanded(
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
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => _scheduleFilterRefresh(),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Текст, автор или город',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    onChanged: (_) => _scheduleFilterRefresh(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_city_outlined),
                      hintText: 'Город',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _routeFilter,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('Все')),
                      DropdownMenuItem(value: 'route', child: Text('Маршрут')),
                      DropdownMenuItem(
                          value: 'plain', child: Text('Без маршрута')),
                    ],
                    onChanged: (value) {
                      setState(() => _routeFilter = value ?? 'any');
                      _loadPosts(refresh: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _photoFilter,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.photo_library_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('Любые фото')),
                      DropdownMenuItem(value: 'with', child: Text('С фото')),
                      DropdownMenuItem(
                          value: 'without', child: Text('Без фото')),
                    ],
                    onChanged: (value) {
                      setState(() => _photoFilter = value ?? 'any');
                      _loadPosts(refresh: true);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _hasActiveFilters ? _clearPostFilters : null,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Сбросить'),
                ),
              ],
            ),
          ],
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
          title: _hasActiveFilters ? 'Посты не найдены' : 'Пока нет публикаций',
          message: _hasActiveFilters
              ? 'Попробуйте изменить фильтры.'
              : 'Создайте первый пост или обновите ленту.',
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
          webSocketService: _webSocketService,
          loadPosts: _loadPosts,
          likePost: _likePost,
          currentUserId: _currentUserId,
          onDeleted: _deletePost,
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
