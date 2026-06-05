import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/screens_api/UserSearchScreen.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/chat_overview_controller.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:provider/provider.dart';

class ChatListScreen extends StatefulWidget {
  final bool initiallyActive;

  const ChatListScreen({
    Key? key,
    this.initiallyActive = false,
  }) : super(key: key);

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final LkUsersService lkService = LkUsersService();
  ChatOverviewController? _chatOverviewController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatOverviewController>();
    if (_chatOverviewController == controller) return;

    _chatOverviewController = controller;
    if (widget.initiallyActive) {
      controller.setOverviewActive(true);
    }
  }

  @override
  void dispose() {
    _chatOverviewController?.setOverviewActive(false);
    super.dispose();
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
                  final currentUserId =
                      _chatOverviewController?.currentUserId;
                  if (currentUserId == null) return;

                  try {
                    await lkService.fetchUserFollowers(currentUserId, 0, 100);

                    showDialog(
                      context: context,
                      builder: (context) {
                        return UserSelectionModal(
                          userId: currentUserId,
                          onUserSelected: (int userId) async {
                            final chatName = _chatNameController.text.trim();
                            if (chatName.isNotEmpty) {
                              try {
                                await _chatService
                                    .createGroupChat(chatName, [userId]);
                                Navigator.pop(context);
                                Navigator.pop(context);
                                _chatOverviewController?.refreshOverview(
                                  showLoading: false,
                                );
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
            icon: Icons.search_rounded,
            tooltip: 'Поиск людей',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserSearchScreen(),
                ),
              );
            },
          ),
          AppIconButton(
            icon: Icons.add,
            tooltip: 'Создать групповой чат',
            onPressed: _showCreateGroupChatDialog,
          ),
        ],
      ),
      body: Consumer<ChatOverviewController>(
        builder: (context, controller, _) {
          if (controller.isLoadingOverview) {
            return const AppLoading(label: 'Загружаем чаты');
          }
          return _buildChatList(controller);
        },
      ),
    );
  }

  Widget _buildChatList(ChatOverviewController controller) {
    final users = controller.users;
    final groupChats = controller.groupChats;
    final itemCount = users.length + groupChats.length;
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
        if (index < users.length) {
          return _buildPersonalChatTile(users[index], controller);
        }
        return _buildGroupChatTile(groupChats[index - users.length], controller);
      },
    );
  }

  Widget _buildPersonalChatTile(
    Map<String, dynamic> user,
    ChatOverviewController controller,
  ) {
    final userId = user['id'] as int;
    final fullName = user['full_name']?.toString() ?? 'Пользователь';
    final avatarUrl = _avatarUrl(user['avatar_url']);
    final unreadCount = controller.unreadPersonalMessagesCount[userId] ?? 0;

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
          controller.refreshAfterConversationChanged();
        });
      },
    );
  }

  Widget _buildGroupChatTile(
    Map<String, dynamic> groupChat,
    ChatOverviewController controller,
  ) {
    final groupChatId = groupChat['id'] as int;
    final groupChatName = groupChat['name']?.toString() ?? 'Групповой чат';
    final unreadCount = controller.unreadGroupMessagesCount[groupChatId] ?? 0;

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
          controller.refreshAfterConversationChanged();
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
