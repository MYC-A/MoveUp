import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/NotificationsScreen.dart';
import 'package:flutter_application_1/screens_api/OrganizerEvents_screen.dart';
import 'package:flutter_application_1/screens_api/followers_modal.dart';
import 'package:flutter_application_1/screens_api/following_modal.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
import 'package:image_picker/image_picker.dart';

import '../services_api/lk_service.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const ProfileScreen({Key? key, this.onLogout}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LkService lkService = LkService();
  final TextEditingController _bioController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  late Future<Map<String, dynamic>> _profileFuture;
  bool _isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = lkService.fetchProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = lkService.fetchProfile();
    });
  }

  Future<void> _handleRefresh() async {
    final future = lkService.fetchProfile();
    setState(() {
      _profileFuture = future;
    });
    await future;
  }

  void _showEditBioDialog(String? currentBio) {
    _bioController.text = currentBio ?? '';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Редактировать биографию',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: _bioController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Введите биографию'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await lkService.updateProfile(bio: _bioController.text);
                if (!mounted) return;
                Navigator.pop(dialogContext);
                _reloadProfile();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Биография обновлена')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка при обновлении профиля: $e')),
                );
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
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
              message: 'Попробуйте обновить экран позже.',
            );
          }

          final profile = snapshot.data!;
          final user = profile['user'];
          final stats = profile['stats'];
          final avatarUrl = (user['avatar_url'] ?? '').toString().replaceAll(
                'localhost:9000',
                AppConfig.mediaBaseUrlWithoutScheme,
              );
          final bio = (user['bio'] ?? 'Нет биографии').toString();
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
                        _OwnProfileHeroCard(
                          user: user,
                          stats: stats,
                          avatarUrl: avatarUrl,
                          bio: bio,
                          isBioExpanded: _isBioExpanded,
                          onBioToggle: () {
                            setState(() {
                              _isBioExpanded = !_isBioExpanded;
                            });
                          },
                          onFollowersTap: _openFollowers,
                          onFollowingTap: _openFollowing,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ActivitySummaryCard(stats: stats),
                        const SizedBox(height: AppSpacing.lg),
                        _ProfileActionCard(
                          onEventsTap: _openOrganizerEvents,
                          onEditBioTap: () => _showEditBioDialog(user['bio']),
                          onAvatarTap: _showImageSourceDialog,
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
    );
  }
}

class _OwnProfileHeroCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> stats;
  final String avatarUrl;
  final String bio;
  final bool isBioExpanded;
  final VoidCallback onBioToggle;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  const _OwnProfileHeroCard({
    required this.user,
    required this.stats,
    required this.avatarUrl,
    required this.bio,
    required this.isBioExpanded,
    required this.onBioToggle,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fullName = (user['full_name'] ?? 'Нет имени').toString();
    final hasLongBio = bio.length > 150;
    final shownBio =
        !isBioExpanded && hasLongBio ? '${bio.substring(0, 150)}...' : bio;

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
            height: 92,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _ProfileChip(
                  icon: Icons.verified_user_outlined,
                  label: 'Ваш профиль',
                  foreground: AppColors.primary,
                  background: AppColors.surface.withValues(alpha: 0.84),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -44),
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
                    radius: 56,
                    backgroundColor: AppColors.surface,
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.surfaceMuted,
                      backgroundImage:
                          avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 48,
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
                    shownBio,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (hasLongBio)
                        TextButton(
                          onPressed: onBioToggle,
                          child:
                              Text(isBioExpanded ? 'Свернуть' : 'Развернуть'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileStat(
                          icon: Icons.groups_outlined,
                          value: '${user['total_subscribers'] ?? 0}',
                          label: 'Подписчики',
                          color: AppColors.primary,
                          onTap: onFollowersTap,
                        ),
                      ),
                      const _ProfileStatsDivider(),
                      Expanded(
                        child: _ProfileStat(
                          icon: Icons.person_add_alt_1_outlined,
                          value: '${user['total_subscriptions'] ?? 0}',
                          label: 'Подписки',
                          color: AppColors.route,
                          onTap: onFollowingTap,
                        ),
                      ),
                      const _ProfileStatsDivider(),
                      Expanded(
                        child: _ProfileStat(
                          icon: Icons.article_outlined,
                          value: '${stats['posts_count'] ?? 0}',
                          label: 'Посты',
                          color: AppColors.activity,
                          onTap: null,
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

class _ProfileActionCard extends StatelessWidget {
  final VoidCallback onEventsTap;
  final VoidCallback onEditBioTap;
  final VoidCallback onAvatarTap;

  const _ProfileActionCard({
    required this.onEventsTap,
    required this.onEditBioTap,
    required this.onAvatarTap,
  });

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
            'Управление',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileActionTile(
            icon: Icons.event_available_outlined,
            title: 'Мои мероприятия',
            subtitle: 'Заявки, участники и события',
            color: AppColors.activity,
            onTap: onEventsTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProfileActionTile(
            icon: Icons.edit_note,
            title: 'Редактировать биографию',
            subtitle: 'Описание профиля',
            color: AppColors.primary,
            onTap: onEditBioTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProfileActionTile(
            icon: Icons.add_a_photo_outlined,
            title: 'Сменить аватарку',
            subtitle: 'Галерея или камера',
            color: AppColors.route,
            onTap: onAvatarTap,
          ),
        ],
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(icon, color: color, size: 22),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
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

class NotificationIcon extends StatefulWidget {
  final LkService lkService;

  const NotificationIcon({required this.lkService});

  @override
  _NotificationIconState createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  bool hasNewNotifications = false;
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
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkNotifications();
    });
  }

  Future<void> _checkNotifications() async {
    try {
      final notifications = await widget.lkService.fetchNotifications();
      if (!mounted) return;
      setState(() {
        hasNewNotifications = notifications['new_applications'].isNotEmpty ||
            notifications['user_applications_changes'].isNotEmpty;
      });
    } catch (e) {
      debugPrint('Ошибка при проверке уведомлений: $e');
    }
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
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotificationsScreen(),
          ),
        ).then((_) {
          _checkNotifications();
        });
      },
    );
  }
}
