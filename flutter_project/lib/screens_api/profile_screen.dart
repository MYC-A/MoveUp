import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/NotificationsScreen.dart';
import 'package:flutter_application_1/screens_api/OrganizerEvents_screen.dart';
import 'package:flutter_application_1/screens_api/followers_modal.dart';
import 'package:flutter_application_1/screens_api/following_modal.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
import 'package:flutter_application_1/widgets/profile/profile_hero.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services_api/api_exception.dart';

import '../services_api/lk_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const ProfileScreen({Key? key, this.onLogout}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LkService lkService = LkService();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;
  bool _isProfileVisible = true;
  DateTime _lastLoadAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Загрузка профиля. background=true — тихое обновление агрегатов без экрана
  // загрузки и без пересоздания списка постов (UserPosts остаётся смонтирован).
  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _lastLoadAt = DateTime.now();
    try {
      final data = await lkService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_profile == null) _error = e.toString();
      });
    }
  }

  // ЛК — вкладка в IndexedStack. При возврате тихо освежаем статистику и
  // запускаем периодическое обновление, пока экран виден.
  void _onVisibilityChanged(double visibleFraction) {
    final nowVisible = visibleFraction > 0.5;
    if (nowVisible && !_isProfileVisible) {
      if (DateTime.now().difference(_lastLoadAt) >
          const Duration(seconds: 2)) {
        _load(background: true);
      }
      _startAutoRefresh();
    } else if (!nowVisible && _isProfileVisible) {
      _stopAutoRefresh();
    }
    _isProfileVisible = nowVisible;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isProfileVisible) _load(background: true);
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _reloadProfile() => _load();

  Future<void> _handleRefresh() => _load(background: true);

  // Открывает полноэкранную форму редактирования профиля.
  Future<void> _openEditProfile(Map<String, dynamic> user) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(user: user),
      ),
    );
    if (changed == true && mounted) {
      _load(background: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлён')),
      );
    }
  }


  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        await lkService.updateProfile(avatarPath: image.path);
        if (!mounted) return;
        _reloadProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватарка обновлена')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при обновлении аватарки: $e')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Галерея'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Камера'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFollowers() {
    showDialog(
      context: context,
      builder: (context) => FollowersModal(),
    );
  }

  void _openFollowing() {
    showDialog(
      context: context,
      builder: (context) => FollowingModal(),
    );
  }

  void _openOrganizerEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizerEventsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          NotificationIcon(lkService: lkService),
          if (widget.onLogout != null)
            IconButton(
              tooltip: 'Выйти',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
            ),
        ],
      ),
      body: VisibilityDetector(
        key: const Key('profile_visibility'),
        onVisibilityChanged: (info) =>
            _onVisibilityChanged(info.visibleFraction),
        child: Builder(
        builder: (context) {
          if (_profile == null) {
            if (_loading) {
              return const AppLoading(label: 'Загружаем профиль');
            }
            if (_error != null) {
              return AppErrorState(message: _error, onRetry: _reloadProfile);
            }
            return const AppEmptyState(
              icon: Icons.person_outline,
              title: 'Профиль не найден',
              message: 'Попробуйте обновить экран позже.',
            );
          }

          final profile = _profile!;
          final user = profile['user'];
          final stats = profile['stats'];
          final avatarUrl =
              AppConfig.normalizeMediaUrl((user['avatar_url'] ?? '').toString());
          final userId = (user['id'] as num?)?.toInt();

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileHero(
                          fullName: (user['full_name'] ?? 'Нет имени').toString(),
                          avatarImage: avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(avatarUrl)
                              : null,
                          bio: user['bio']?.toString(),
                          city: user['city']?.toString(),
                          weight: user['weight'] is num
                              ? user['weight'] as num
                              : null,
                          height: user['height'] is num
                              ? user['height'] as num
                              : null,
                          postsCount:
                              ((stats['posts_count'] ?? 0) as num).toInt(),
                          followersCount:
                              ((user['total_subscribers'] ?? 0) as num).toInt(),
                          followingCount:
                              ((user['total_subscriptions'] ?? 0) as num)
                                  .toInt(),
                          onFollowersTap: _openFollowers,
                          onFollowingTap: _openFollowing,
                          badgeLabel: 'Ваш профиль',
                          badgeIcon: Icons.verified_user_outlined,
                          actions: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _openEditProfile(user),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      label: const Text('Редактировать'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  OutlinedButton(
                                    onPressed: _showImageSourceDialog,
                                    child: const Icon(
                                        Icons.photo_camera_outlined,
                                        size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _openOrganizerEvents,
                                  icon: const Icon(Icons.event_outlined,
                                      size: 18),
                                  label: const Text('Мои мероприятия'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Мои публикации',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (userId != null)
                  UserPosts(
                    userId: userId,
                    scrollController: _scrollController,
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              ],
            ),
          );
        },
        ),
      ),
    );
  }
}

class NotificationIcon extends StatefulWidget {
  final LkService lkService;

  const NotificationIcon({required this.lkService});

  @override
  _NotificationIconState createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  bool hasNewNotifications = false;
  Map<String, dynamic> _latestNotifications = {};
  bool _checking = false; // защита от наложения опросов
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkNotifications();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    // Реже опрашиваем — фоновая проверка не критична, а частые запросы при
    // плохой сети только плодят таймауты.
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkNotifications();
    });
  }

  Future<void> _checkNotifications() async {
    // Не запускаем новый опрос, пока не завершился предыдущий (иначе при
    // медленной сети запросы накладываются и сыплют таймаутами).
    if (_checking) return;
    _checking = true;
    try {
      final notifications = await widget.lkService.fetchNotifications();
      if (!mounted) return;
      bool notEmpty(String key) {
        final value = notifications[key];
        return value is List && value.isNotEmpty;
      }

      setState(() {
        _latestNotifications = notifications;
        hasNewNotifications = notEmpty('new_applications') ||
            notEmpty('user_applications_changes') ||
            notEmpty('event_updates');
      });
    } catch (e) {
      // Нет сети/таймаут — это норма для фоновой проверки, не шумим в логах.
      if (!(e is ApiException && e.isOffline)) {
        debugPrint('Ошибка при проверке уведомлений: $e');
      }
    } finally {
      _checking = false;
    }
  }

  bool _hasItems(String key) {
    final value = _latestNotifications[key];
    return value is List && value.isNotEmpty;
  }

  int? _eventsTabFromNotifications() {
    if (_hasItems('new_applications')) return 0;
    if (_hasItems('user_applications_changes')) return 1;
    return null;
  }

  Future<void> _markNotificationsForTab(int tabIndex) async {
    final key = tabIndex == 0 ? 'new_applications' : 'user_applications_changes';
    final type = tabIndex == 0 ? 'application' : 'change';
    final items = _latestNotifications[key];
    if (items is! List) return;

    for (final item in items) {
      if (item is! Map) continue;
      final rawEventId = item['event_id'];
      final eventId = rawEventId is int
          ? rawEventId
          : int.tryParse(rawEventId?.toString() ?? '');
      if (eventId == null) continue;
      await widget.lkService.markNotificationAsRead(eventId, type);
    }
  }

  void _openNotificationsTarget() {
    final tabIndex = _eventsTabFromNotifications();
    if (tabIndex == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NotificationsScreen(
            onNotificationsUpdated: _checkNotifications,
          ),
        ),
      ).then((_) {
        _checkNotifications();
      });
      return;
    }

    () async {
      try {
        await _markNotificationsForTab(tabIndex);
      } catch (e) {
        if (!(e is ApiException && e.isOffline)) {
          debugPrint('Ошибка при отметке уведомлений: $e');
        }
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrganizerEventsScreen(
            initialTabIndex: tabIndex,
          ),
        ),
      );
      _checkNotifications();
    }();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Уведомления',
      icon: Stack(
        children: [
          const Icon(Icons.notifications_outlined),
          if (hasNewNotifications)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      onPressed: _openNotificationsTarget,
    );
  }
}
