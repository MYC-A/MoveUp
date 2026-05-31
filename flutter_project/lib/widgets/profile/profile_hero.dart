import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';

/// Единая «шапка» профиля для своего ЛК и профилей других пользователей —
/// одинаковый стиль везде. Колбэки/кнопки действий передаются снаружи.
class ProfileHero extends StatelessWidget {
  final String fullName;
  final ImageProvider? avatarImage;
  final String? bio;
  final String? city;
  final num? weight;
  final num? height;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final VoidCallback? onPostsTap;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  /// Кнопки действий (свой профиль: редактировать/фото; чужой: подписка/сообщение).
  final Widget actions;

  /// Подпись-чип в правом верхнем углу.
  final String badgeLabel;
  final IconData badgeIcon;

  const ProfileHero({
    super.key,
    required this.fullName,
    required this.avatarImage,
    required this.actions,
    this.bio,
    this.city,
    this.weight,
    this.height,
    this.postsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.onPostsTap,
    this.onFollowersTap,
    this.onFollowingTap,
    this.badgeLabel = 'Профиль',
    this.badgeIcon = Icons.person_outline,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final trimmedBio = (bio ?? '').trim();

    final chips = <Widget>[
      if ((city ?? '').trim().isNotEmpty)
        _HeroChip(icon: Icons.location_on_outlined, label: city!.trim()),
      if (weight is num) _HeroChip(icon: Icons.monitor_weight_outlined, label: '$weight кг'),
      if (height is num) _HeroChip(icon: Icons.height, label: '$height см'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Мягкая шапка-градиент с бейджем.
          Container(
            height: 84,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primarySoft],
              ),
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: _HeroChip(
                  icon: badgeIcon,
                  label: badgeLabel,
                  background: AppColors.surface,
                  foreground: AppColors.primary,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -40),
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
                    radius: 48,
                    backgroundColor: AppColors.surface,
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.surfaceMuted,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person,
                              size: 44, color: AppColors.textMuted)
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    fullName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: chips,
                    ),
                  ],
                  if (trimmedBio.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _ExpandableBio(text: trimmedBio),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  // Единая строка статистики.
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HeroStat(
                            value: postsCount,
                            label: 'Посты',
                            onTap: onPostsTap,
                          ),
                        ),
                        const _HeroStatDivider(),
                        Expanded(
                          child: _HeroStat(
                            value: followersCount,
                            label: 'Подписчики',
                            onTap: onFollowersTap,
                          ),
                        ),
                        const _HeroStatDivider(),
                        Expanded(
                          child: _HeroStat(
                            value: followingCount,
                            label: 'Подписки',
                            onTap: onFollowingTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  actions,
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? background;
  final Color? foreground;

  const _HeroChip({
    required this.icon,
    required this.label,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;

  const _HeroStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: content,
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  const _HeroStatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.border);
  }
}

/// Био с возможностью развернуть/свернуть — как в обычных соцсетях.
class _ExpandableBio extends StatefulWidget {
  final String text;

  const _ExpandableBio({required this.text});

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Длинное описание сворачиваем по умолчанию.
    final isLong = widget.text.length > 160 || '\n'.allMatches(widget.text).length >= 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.text,
          textAlign: TextAlign.center,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                _expanded ? 'Свернуть' : 'Показать полностью',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
