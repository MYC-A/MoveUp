import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserFollowersModal.dart';
import 'package:flutter_application_1/screens_api/UserFollowingModal.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
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
    _profileFuture = lkUsersService.fetchUserProfile(widget.userId);
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
        builder: (context) => ChatScreen(recipientId: widget.userId),
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
                      _ProfileHeroCard(
                        user: user,
                        stats: stats,
                        avatarUrl: avatarUrl,
                        cacheManager: customCacheManager,
                        isFollowing: isFollowing,
                        isLoadingFollowStatus: isLoadingFollowStatus,
                        socialStatsFuture: _socialStatsFuture,
                        onFollowTap: _toggleFollow,
                        onMessageTap: _openChat,
                        onFollowersTap: _openFollowers,
                        onFollowingTap: _openFollowing,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ActivitySummaryCard(stats: stats),
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

class _ProfileHeroCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> stats;
  final String avatarUrl;
  final CacheManager cacheManager;
  final bool isFollowing;
  final bool isLoadingFollowStatus;
  final Future<_UserSocialStats> socialStatsFuture;
  final VoidCallback onFollowTap;
  final VoidCallback onMessageTap;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  const _ProfileHeroCard({
    required this.user,
    required this.stats,
    required this.avatarUrl,
    required this.cacheManager,
    required this.isFollowing,
    required this.isLoadingFollowStatus,
    required this.socialStatsFuture,
    required this.onFollowTap,
    required this.onMessageTap,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fullName = user['full_name'] ?? 'Нет имени';
    final bio = user['bio'] ?? 'Нет биографии';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 86,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _ProfileChip(
                  icon: Icons.person,
                  label: 'Профиль',
                  foreground: AppColors.primary,
                  background: AppColors.surface.withValues(alpha: 0.82),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -42),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                0,
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: AppColors.surface,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.surfaceMuted,
                      backgroundImage: avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(
                              avatarUrl,
                              cacheManager: cacheManager,
                            )
                          : null,
                      child: avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 46,
                              color: AppColors.textMuted,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    fullName,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _ProfileChip(
                        icon: Icons.dynamic_feed_outlined,
                        label: '${stats['posts_count'] ?? 0} постов',
                        foreground: AppColors.primary,
                        background: AppColors.primarySoft,
                      ),
                      _ProfileChip(
                        icon: Icons.favorite_border,
                        label: '${stats['likes_count'] ?? 0} лайков',
                        foreground: AppColors.danger,
                        background: const Color(0xFFFFECEA),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FutureBuilder<_UserSocialStats>(
                    future: socialStatsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 82,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final stats = snapshot.data ??
                          const _UserSocialStats(followers: 0, following: 0);

                      return Row(
                        children: [
                          Expanded(
                            child: _ProfileStat(
                              icon: Icons.groups_outlined,
                              value: '${stats.followers}',
                              label: 'Подписчики',
                              color: AppColors.primary,
                              onTap: onFollowersTap,
                            ),
                          ),
                          const _ProfileStatsDivider(),
                          Expanded(
                            child: _ProfileStat(
                              icon: Icons.person_add_alt_1_outlined,
                              value: '${stats.following}',
                              label: 'Подписки',
                              color: AppColors.route,
                              onTap: onFollowingTap,
                            ),
                          ),
                          const _ProfileStatsDivider(),
                          Expanded(
                            child: _ProfileStat(
                              icon: Icons.mode_comment_outlined,
                              value: '${this.stats['comments_count'] ?? 0}',
                              label: 'Комментарии',
                              color: AppColors.activity,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onMessageTap,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Диалог'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: isLoadingFollowStatus
                            ? const SizedBox(
                                height: 44,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: onFollowTap,
                                icon: Icon(
                                  isFollowing
                                      ? Icons.check
                                      : Icons.person_add_alt_1,
                                ),
                                label: Text(
                                  isFollowing ? 'Вы подписаны' : 'Подписаться',
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _ActivitySummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Активность',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ActivityMetric(
                  icon: Icons.dynamic_feed_outlined,
                  value: '${stats['posts_count'] ?? 0}',
                  label: 'Посты',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActivityMetric(
                  icon: Icons.mode_comment_outlined,
                  value: '${stats['comments_count'] ?? 0}',
                  label: 'Комментарии',
                  color: AppColors.activity,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActivityMetric(
                  icon: Icons.favorite_border,
                  value: '${stats['likes_count'] ?? 0}',
                  label: 'Лайки',
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _ActivityMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: content,
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _ProfileChip({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: 17),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatsDivider extends StatelessWidget {
  const _ProfileStatsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 66,
      color: AppColors.border,
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
