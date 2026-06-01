import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  static const int _pageSize = 20;

  final LkUsersService _usersService = LkUsersService();
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _users = [];
  Timer? _debounce;
  bool _isLoading = false;
  bool _isFirstLoad = true;
  bool _hasMore = true;
  int _skip = 0;
  String? _loadError;
  String _avatarFilter = 'any';
  String _followingFilter = 'any';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadUsers(refresh: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _cityController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      _loadUsers();
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _loadUsers(refresh: true);
    });
  }

  bool? get _hasAvatarParam {
    if (_avatarFilter == 'with') return true;
    if (_avatarFilter == 'without') return false;
    return null;
  }

  bool? get _followingParam {
    if (_followingFilter == 'following') return true;
    if (_followingFilter == 'not_following') return false;
    return null;
  }

  Future<void> _loadUsers({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _skip = 0;
      _hasMore = true;
      _loadError = null;
    }
    if (!_hasMore) return;

    setState(() {
      _isLoading = true;
      if (refresh) _isFirstLoad = true;
    });

    try {
      final data = await _usersService.searchUsers(
        query: _queryController.text,
        city: _cityController.text,
        hasAvatar: _hasAvatarParam,
        following: _followingParam,
        skip: _skip,
        limit: _pageSize,
      );
      if (!mounted) return;

      final loadedUsers = List<Map<String, dynamic>>.from(
        data['users'] as List? ?? const [],
      );
      setState(() {
        if (refresh) _users.clear();
        _users.addAll(loadedUsers);
        _skip += loadedUsers.length;
        _hasMore = data['has_more'] == true;
        _isFirstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_users.isEmpty) {
        setState(() {
          _loadError = e.toString();
          _isFirstLoad = false;
        });
      } else {
        showApiError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearFilters() {
    _queryController.clear();
    _cityController.clear();
    setState(() {
      _avatarFilter = 'any';
      _followingFilter = 'any';
    });
    _loadUsers(refresh: true);
  }

  void _openProfile(int userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfiles(userId: userId)),
    );
  }

  String? _avatarUrl(dynamic value) {
    final rawUrl = (value ?? '').toString().trim();
    if (rawUrl.isEmpty) return null;
    return AppConfig.normalizeMediaUrl(rawUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Поиск людей'),
        actions: [
          IconButton(
            tooltip: 'Сбросить фильтры',
            icon: const Icon(Icons.filter_alt_off_outlined),
            onPressed: _clearFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
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
              controller: _queryController,
              onChanged: (_) => _scheduleRefresh(),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Имя, username, город или био',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    onChanged: (_) => _scheduleRefresh(),
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
                    value: _followingFilter,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.people_alt_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('Все')),
                      DropdownMenuItem(
                        value: 'following',
                        child: Text('Подписки'),
                      ),
                      DropdownMenuItem(
                        value: 'not_following',
                        child: Text('Новые'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _followingFilter = value ?? 'any');
                      _loadUsers(refresh: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              value: _avatarFilter,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.photo_camera_front_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'any', child: Text('Любое фото')),
                DropdownMenuItem(value: 'with', child: Text('С фото')),
                DropdownMenuItem(value: 'without', child: Text('Без фото')),
              ],
              onChanged: (value) {
                setState(() => _avatarFilter = value ?? 'any');
                _loadUsers(refresh: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isFirstLoad && _isLoading) {
      return const AppLoading(label: 'Ищем людей');
    }
    if (_loadError != null && _users.isEmpty) {
      return AppErrorState(
        message: _loadError,
        onRetry: () => _loadUsers(refresh: true),
      );
    }
    if (_users.isEmpty) {
      return const AppEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Никого не нашли',
        message: 'Попробуйте изменить фильтры.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadUsers(refresh: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _users.length + (_hasMore || _isLoading ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _users.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: AppLoading(),
            );
          }
          return _UserSearchTile(
            user: _users[index],
            avatarUrl: _avatarUrl(_users[index]['avatar_url']),
            onTap: () => _openProfile(_users[index]['id'] as int),
          );
        },
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final String? avatarUrl;
  final VoidCallback onTap;

  const _UserSearchTile({
    required this.user,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fullName = user['full_name']?.toString() ?? 'Пользователь';
    final city = user['city']?.toString();
    final bio = user['bio']?.toString();
    final isFollowing = user['is_following'] == true;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _UserSearchAvatar(avatarUrl: avatarUrl, name: fullName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isFollowing)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 18,
                          ),
                      ],
                    ),
                    if (city != null && city.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserSearchAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;

  const _UserSearchAvatar({required this.avatarUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final url = avatarUrl?.trim();

    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }
}
