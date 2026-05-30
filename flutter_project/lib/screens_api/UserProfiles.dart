import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserFollowersModal.dart';
import 'package:flutter_application_1/screens_api/UserFollowingModal.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
import 'package:flutter_application_1/widgets/profile/profile_hero.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class UserProfiles extends StatefulWidget {
  final int userId;

  const UserProfiles({super.key, required this.userId});

  @override
  _UserProfilesState createState() => _UserProfilesState();
}

class _UserProfilesState extends State<UserProfiles> {
  final LkUsersService lkUsersService = LkUsersService();
  final ScrollController _scrollController = ScrollController();

  late Future<Map<String, dynamic>> _profileFuture;
  late Future<_UserSocialStats> _socialStatsFuture;

  bool isFollowing = false;
  bool isLoadingFollowStatus = true;
  String? _userFullName;

  final customCacheManager = CacheManager(
    Config(
      'customCacheKey',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 100,
    ),
  );

  @override
  void initState() {
    super.initState();
    _profileFuture = lkUsersService.fetchUserProfile(widget.userId)
      ..then((p) {
        final name = p['user']?['full_name']?.toString();
        if (mounted && name != null && name.isNotEmpty) {
          _userFullName = name;
        }
      });
    _socialStatsFuture = _fetchSocialStats();
    _checkFollowStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<_UserSocialStats> _fetchSocialStats() async {
    final results = await Future.wait([
      lkUsersService.fetchUserFollowers(widget.userId, 0, 1),
      lkUsersService.fetchUserFollowing(widget.userId, 0, 1),
    ]);

    return _UserSocialStats(
      followers: results[0]['total_followers'] ?? 0,
      following: results[1]['total_following'] ?? 0,
    );
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = lkUsersService.fetchUserProfile(widget.userId);
      _socialStatsFuture = _fetchSocialStats();
      isLoadingFollowStatus = true;
    });
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    try {
      final response = await lkUsersService.isFollowing(widget.userId);
      if (!mounted) return;
      setState(() {
        isFollowing = response['is_following'] ?? false;
        isLoadingFollowStatus = false;
      });
    } catch (e) {
      debugPrint('Ошибка при проверке статуса подписки: $e');
      if (!mounted) return;
      setState(() {
        isLoadingFollowStatus = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    try {
      if (isFollowing) {
        await lkUsersService.unfollowUser(widget.userId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы отписались от пользователя')),
        );
      } else {
        await lkUsersService.followUser(widget.userId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы подписались на пользователя')),
        );
      }
      if (!mounted) return;
      setState(() {
        isFollowing = !isFollowing;
        _socialStatsFuture = _fetchSocialStats();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          recipientId: widget.userId,
          recipientName: _userFullName,
        ),
      ),
    );
  }

  void _openFollowers() {
    showDialog(
      context: context,
      builder: (context) => UserFollowersModal(userId: widget.userId),
    );
  }

  void _openFollowing() {
    showDialog(
      context: context,
      builder: (context) => UserFollowingModal(userId: widget.userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Загружаем профиль');
          } else if (snapshot.hasError) {
            return AppErrorState(
              message: '${snapshot.error}',
              onRetry: _reloadProfile,
            );
          } else if (!snapshot.hasData) {
            return const AppEmptyState(
              icon: Icons.person_outline,
              title: 'Профиль не найден',
              message: 'Попробуйте открыть профиль позже.',
            );
          }

          final profile = snapshot.data!;
          final user = profile['user'];
          final stats = profile['stats'];
          final avatarUrl = (user['avatar_url'] ?? '').replaceAll(
              'localhost:9000', AppConfig.mediaBaseUrlWithoutScheme);

          return CustomScrollView(
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
                      FutureBuilder<_UserSocialStats>(
                        future: _socialStatsFuture,
                        builder: (context, snap) {
                          final social = snap.data;
                          return ProfileHero(
                            fullName:
                                (user['full_name'] ?? 'Нет имени').toString(),
                            avatarImage: avatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    avatarUrl,
                                    cacheManager: customCacheManager,
                                  )
                                : null,
                            bio: user['bio']?.toString(),
                            city: user['city']?.toString(),
                            postsCount:
                                ((stats['posts_count'] ?? 0) as num).toInt(),
                            followersCount: social?.followers ?? 0,
                            followingCount: social?.following ?? 0,
                            onFollowersTap: _openFollowers,
                            onFollowingTap: _openFollowing,
                            actions: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isLoadingFollowStatus
                                        ? null
                                        : _toggleFollow,
                                    icon: Icon(
                                      isFollowing
                                          ? Icons.person_remove_alt_1_outlined
                                          : Icons.person_add_alt_1_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                        isFollowing ? 'Отписаться' : 'Подписаться'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _openChat,
                                    icon: const Icon(
                                        Icons.chat_bubble_outline,
                                        size: 18),
                                    label: const Text('Сообщение'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionHeader(
                        title: 'Публикации',
                        subtitle: '${stats['posts_count'] ?? 0} постов',
                      ),
                    ],
                  ),
                ),
              ),
              UserPosts(
                userId: widget.userId,
                scrollController: _scrollController,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserSocialStats {
  final int followers;
  final int following;

  const _UserSocialStats({
    required this.followers,
    required this.following,
  });
}
