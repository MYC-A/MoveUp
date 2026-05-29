import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class ChatListScreen extends StatefulWidget {
  final bool initiallyActive;
  final ValueChanged<int>? onUnreadTotalChanged;

  const ChatListScreen({
    Key? key,
    this.initiallyActive = false,
    this.onUnreadTotalChanged,
  }) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();

  // Публичный метод для перезагрузки данных чата
  void reloadChatData() {
    state?._refreshChatOverview(showLoading: false);
  }

  void setPollingActive(bool isActive) {
    state?._setPollingActive(isActive);
  }

  static void setActivePolling(bool isActive) {
    state?._setPollingActive(isActive);
  }

  static _ChatListScreenState? state; // Публичное статическое поле
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const Duration _pollingInterval = Duration(seconds: 15);

  final ChatService _chatService = ChatService();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _groupChats = [];
  final LkUsersService lkService = LkUsersService();
  bool _isLoading = true;
  int? currentUserId;
  Map<int, int> _unreadPersonalMessagesCount = {}; // Для личных чатов
  Map<int, int> _unreadGroupMessagesCount = {}; // Для групповых чатов
  Timer? _timer; // Таймер для polling
  bool _isPollingActive = false;
  bool _isRefreshingOverview = false;

  @override
  void initState() {
    super.initState();
    ChatListScreen.state = this; // Устанавливаем ссылку на состояние
    _isPollingActive = widget.initiallyActive;
    if (_isPollingActive) {
      _startPolling();
      _refreshChatOverview(showLoading: true);
    }
  }

  @override
  void dispose() {
    _stopPolling();
    if (ChatListScreen.state == this) {
      ChatListScreen.state = null; // Очищаем ссылку при уничтожении
    }
    super.dispose();
  }

  void _setPollingActive(bool isActive) {
    if (_isPollingActive == isActive) {
      if (isActive) {
        _refreshChatOverview(
            showLoading: _users.isEmpty && _groupChats.isEmpty);
      }
      return;
    }

    _isPollingActive = isActive;
    if (isActive) {
      _startPolling();
      _refreshChatOverview(showLoading: _users.isEmpty && _groupChats.isEmpty);
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollingInterval, (_) {
      _refreshChatOverview(showLoading: false);
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refreshChatOverview({bool showLoading = false}) async {
    if (_isRefreshingOverview) return;
    _isRefreshingOverview = true;

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _chatService.getChatData(),
        _chatService.getUnreadMessagesCount(),
      ]);
      if (!mounted) return;

      final data = results[0] as Map<String, dynamic>;
      final count = results[1] as Map<String, Map<int, int>>;
      final personalCount = count['personal'] ?? {};
      final groupCount = count['group'] ?? {};
      setState(() {
        currentUserId = data['user']['id'];
        _users = List<Map<String, dynamic>>.from(data['users_with_messages']);
        _groupChats = List<Map<String, dynamic>>.from(data['group_chats']);
        _unreadPersonalMessagesCount = personalCount;
        _unreadGroupMessagesCount = groupCount;
        _isLoading = false;
      });
      _notifyUnreadTotal(personalCount, groupCount);
    } catch (e) {
      debugPrint('Ошибка загрузки данных чата: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshingOverview = false;
    }
  }

  Future<void> _loadUnreadMessagesCount() async {
    try {
      final count = await _chatService.getUnreadMessagesCount();
      if (!mounted) return;
      final personalCount = count['personal'] ?? {};
      final groupCount = count['group'] ?? {};
      setState(() {
        _unreadPersonalMessagesCount = personalCount;
        _unreadGroupMessagesCount = groupCount;
      });
      _notifyUnreadTotal(personalCount, groupCount);
    } catch (e) {
      debugPrint('Ошибка загрузки количества непрочитанных сообщений: $e');
    }
  }

  // Публичный метод-обертка
  Future<void> refreshUnreadMessagesCount() async {
    await _loadUnreadMessagesCount();
  }

  String _initialForName(String? name) {
    final value = (name ?? '').trim();
    if (value.isEmpty) return '?';
    return value[0].toUpperCase();
  }

  String? _avatarUrl(dynamic value) {
    final rawUrl = (value ?? '').toString().trim();
    if (rawUrl.isEmpty) return null;
    return AppConfig.normalizeMediaUrl(rawUrl);
  }

  void _notifyUnreadTotal(
    Map<int, int> personalCount,
    Map<int, int> groupCount,
  ) {
    final totalPersonal =
        personalCount.values.where((value) => value > 0).length;
    final totalGroup = groupCount.values.where((value) => value > 0).length;
    widget.onUnreadTotalChanged?.call(totalPersonal + totalGroup);
  }

  void _showCreateGroupChatDialog() {
    TextEditingController _chatNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Создать групповой чат'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _chatNameController,
                decoration: InputDecoration(
                  labelText: 'Название чата',
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (currentUserId == null) return;

                  try {
                    await lkService.fetchUserFollowers(currentUserId!, 0, 100);

                    showDialog(
                      context: context,
                      builder: (context) {
                        return UserSelectionModal(
                          userId: currentUserId!,
                          onUserSelected: (int userId) async {
                            final chatName = _chatNameController.text.trim();
                            if (chatName.isNotEmpty) {
                              try {
                                await _chatService
                                    .createGroupChat(chatName, [userId]);
                                Navigator.pop(context);
                                Navigator.pop(context);
                                _refreshChatOverview(showLoading: false);
                              } catch (e) {
                                debugPrint('Ошибка создания чата: $e');
                              }
                            }
                          },
                        );
                      },
                    );
                  } catch (e) {
                    debugPrint('Ошибка загрузки подписчиков: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Ошибка при загрузке подписчиков')),
                    );
                  }
                },
                child: Text('Выбрать подписчика'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          AppIconButton(
            icon: Icons.add,
            tooltip: 'Создать групповой чат',
            onPressed: _showCreateGroupChatDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const AppLoading(label: 'Загружаем чаты')
          : _buildChatList(),
    );
  }

  Widget _buildChatList() {
    final itemCount = _users.length + _groupChats.length;
    if (itemCount == 0) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Пока нет чатов',
        message: 'Когда появятся переписки, они будут здесь.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index < _users.length) {
          return _buildPersonalChatTile(_users[index]);
        }
        return _buildGroupChatTile(_groupChats[index - _users.length]);
      },
    );
  }

  Widget _buildPersonalChatTile(Map<String, dynamic> user) {
    final userId = user['id'] as int;
    final fullName = user['full_name']?.toString() ?? 'Пользователь';
    final avatarUrl = _avatarUrl(user['avatar_url']);
    final unreadCount = _unreadPersonalMessagesCount[userId] ?? 0;

    return _ChatOverviewTile(
      title: fullName,
      subtitle: unreadCount > 0 ? '$unreadCount непрочитанных' : 'Личный чат',
      icon: Icons.person_rounded,
      initial: _initialForName(fullName),
      avatarUrl: avatarUrl,
      accent: AppColors.primary,
      unreadCount: unreadCount,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ChatScreen(recipientId: userId, recipientName: fullName),
          ),
        ).then((_) {
          _loadUnreadMessagesCount();
        });
      },
    );
  }

  Widget _buildGroupChatTile(Map<String, dynamic> groupChat) {
    final groupChatId = groupChat['id'] as int;
    final groupChatName = groupChat['name']?.toString() ?? 'Групповой чат';
    final unreadCount = _unreadGroupMessagesCount[groupChatId] ?? 0;

    return _ChatOverviewTile(
      title: groupChatName,
      subtitle:
          unreadCount > 0 ? '$unreadCount непрочитанных' : 'Групповой чат',
      icon: Icons.groups_rounded,
      accent: AppColors.route,
      unreadCount: unreadCount,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(
              groupChatId: groupChatId,
              groupChatName: groupChatName,
            ),
          ),
        ).then((_) {
          _loadUnreadMessagesCount();
        });
      },
    );
  }
}

class _ChatOverviewTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? initial;
  final String? avatarUrl;
  final Color accent;
  final int unreadCount;
  final VoidCallback onTap;

  const _ChatOverviewTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.initial,
    this.avatarUrl,
    required this.accent,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.72)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _ChatAvatar(
                avatarUrl: avatarUrl,
                icon: icon,
                initial: initial,
                accent: accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unreadCount > 0
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight:
                            unreadCount > 0 ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (unreadCount > 0)
                _ChatUnreadBadge(count: unreadCount)
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String? avatarUrl;
  final IconData icon;
  final String? initial;
  final Color accent;

  const _ChatAvatar({
    required this.avatarUrl,
    required this.icon,
    required this.initial,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim();

    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: imageUrl == null || imageUrl.isEmpty
          ? _ChatAvatarFallback(icon: icon, initial: initial, accent: accent)
          : CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => _ChatAvatarFallback(
                icon: icon,
                initial: initial,
                accent: accent,
              ),
              errorWidget: (_, __, ___) => _ChatAvatarFallback(
                icon: icon,
                initial: initial,
                accent: accent,
              ),
            ),
    );
  }
}

class _ChatAvatarFallback extends StatelessWidget {
  final IconData icon;
  final String? initial;
  final Color accent;

  const _ChatAvatarFallback({
    required this.icon,
    required this.initial,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (initial == null) {
      return Icon(icon, color: accent, size: 26);
    }

    return Center(
      child: Text(
        initial!,
        style: TextStyle(
          color: accent,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ChatUnreadBadge extends StatelessWidget {
  final int count;

  const _ChatUnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: AppColors.surface,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
