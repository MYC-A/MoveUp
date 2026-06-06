import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

/// Экран выбора пользователя для приглашения на мероприятие.
/// Без поискового запроса показываются подписчики организатора, при вводе —
/// поиск по всем пользователям. Каждый помечен текущим статусом участия.
class InviteToEventScreen extends StatefulWidget {
  final int eventId;
  final String eventTitle;

  const InviteToEventScreen({
    required this.eventId,
    required this.eventTitle,
    Key? key,
  }) : super(key: key);

  @override
  State<InviteToEventScreen> createState() => _InviteToEventScreenState();
}

class _InviteToEventScreenState extends State<InviteToEventScreen> {
  final LkService _lkService = LkService();
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _users = [];
  final Set<int> _invitingIds = {};
  String _query = '';
  bool _isLoading = true;
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data =
          await _lkService.fetchInvitableUsers(widget.eventId, _query, 0, 30);
      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(data['users'] ?? const []));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _invite(Map<String, dynamic> user) async {
    final userId = user['id'] as int?;
    if (userId == null || _invitingIds.contains(userId)) return;

    setState(() => _invitingIds.add(userId));
    try {
      await _lkService.inviteUserToEvent(widget.eventId, userId);
      if (!mounted) return;
      setState(() {
        user['status'] = 'INVITED';
        _invitingIds.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Приглашение отправлено: ${user['full_name']}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _invitingIds.remove(userId));
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пригласить на мероприятие')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск по имени (без поиска — подписчики)',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AppLoading(label: 'Загружаем пользователей');
    }
    if (_error != null) {
      return AppErrorState(message: _error.toString(), onRetry: _load);
    }
    if (_users.isEmpty) {
      return AppEmptyState(
        icon: Icons.group_outlined,
        title: _query.isEmpty ? 'Нет подписчиков' : 'Никого не найдено',
        message: _query.isEmpty
            ? 'Найдите пользователей через поиск по имени.'
            : 'Попробуйте изменить запрос.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _users.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) => _buildUserTile(_users[index]),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id'] as int?;
    final name = (user['full_name'] ?? 'Пользователь').toString();
    final rawAvatar = user['avatar_url'] as String?;
    final avatarUrl = (rawAvatar != null && rawAvatar.isNotEmpty)
        ? AppConfig.normalizeMediaUrl(rawAvatar)
        : null;
    final status = user['status'] as String?;
    final isInviting = userId != null && _invitingIds.contains(userId);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.surfaceMuted,
        backgroundImage:
            avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
        child: avatarUrl == null
            ? const Icon(Icons.person_outline, color: AppColors.textSecondary)
            : null,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: user['city'] != null && (user['city'] as String).isNotEmpty
          ? Text(user['city'].toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: _buildTrailing(user, status, isInviting),
    );
  }

  Widget _buildTrailing(
      Map<String, dynamic> user, String? status, bool isInviting) {
    if (isInviting) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (status) {
      case 'APPROVED':
        return _chip('Участник', AppColors.success);
      case 'AWAITS':
        return _chip('Заявка', AppColors.activity);
      case 'INVITED':
        return _chip('Приглашён', AppColors.primary);
      case 'DENIED':
        // Отклонённого можно пригласить заново.
        return _inviteButton(user);
      default:
        return _inviteButton(user);
    }
  }

  Widget _inviteButton(Map<String, dynamic> user) {
    return FilledButton.icon(
      onPressed: () => _invite(user),
      icon: const Icon(Icons.person_add_alt_1, size: 18),
      label: const Text('Пригласить'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
