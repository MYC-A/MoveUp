import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_icon_button.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:intl/intl.dart';

class _GroupChatTimelineItem {
  final Map<String, dynamic>? message;
  final String? dateLabel;

  const _GroupChatTimelineItem.message(this.message) : dateLabel = null;
  const _GroupChatTimelineItem.date(this.dateLabel) : message = null;
}

class GroupChatScreen extends StatefulWidget {
  final int groupChatId;
  final String groupChatName;

  const GroupChatScreen({
    required this.groupChatId,
    required this.groupChatName,
    Key? key,
  }) : super(key: key);

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const int _pageSize = 30;

  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final StreamController<List<Map<String, dynamic>>> _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasMoreMessages = true;
  int? currentUserId;
  // Минимальный интервал между подгрузками старых сообщений (защита от того,
  // что инерционный скролл вверх вызывает цепочку догрузок до начала чата).
  DateTime? _lastOlderLoadAt;

  @override
  void initState() {
    super.initState();
    PushNotificationService.setActiveConversation(
      conversationType: 'group',
      conversationId: widget.groupChatId,
    );
    _scrollController.addListener(_handleScroll);
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final results = await Future.wait<dynamic>([
        _chatService.getCachedCurrentUserId(),
        _chatService.getGroupMessages(
          widget.groupChatId,
          limit: _pageSize,
        ),
      ]);
      if (!mounted) return;

      currentUserId = results[0] as int?;
      final messages = List<Map<String, dynamic>>.from(results[1] as List);
      if (currentUserId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _messages = messages;
        _hasMoreMessages = messages.length == _pageSize;
        _isLoading = false;
      });
      _emitMessages();
      _scrollToBottom(animated: false);
      _connectToWebSocket();
      await _markMessagesAsRead();
    } catch (e) {
      debugPrint('Ошибка инициализации группового чата: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _chatService.markGroupMessagesAsRead(widget.groupChatId);
      ChatListScreen.state?.refreshUnreadMessagesCount();
    } catch (e) {
      debugPrint('Ошибка отметки сообщений как прочитанных: $e');
    }
  }

  void _emitMessages() {
    if (!_messagesController.isClosed) {
      _messagesController.add(_messages);
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingOlder ||
        !_hasMoreMessages) {
      return;
    }
    if (_lastOlderLoadAt != null &&
        DateTime.now().difference(_lastOlderLoadAt!) <
            const Duration(milliseconds: 600)) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _loadOlderMessages();
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;

    return _scrollController.position.pixels < 120;
  }

  Future<void> _loadOlderMessages() async {
    if (_messages.isEmpty || _isLoadingOlder || !_hasMoreMessages) return;

    final firstMessageId = _messages.first['id'];
    if (firstMessageId is! int) {
      setState(() {
        _hasMoreMessages = false;
      });
      return;
    }

    _lastOlderLoadAt = DateTime.now();
    setState(() {
      _isLoadingOlder = true;
    });

    try {
      final olderMessages = await _chatService.getGroupMessages(
        widget.groupChatId,
        limit: _pageSize,
        beforeId: firstMessageId,
      );
      if (!mounted) return;

      final existingIds =
          _messages.map((message) => message['id']).whereType<int>().toSet();
      final uniqueOlderMessages = olderMessages.where((message) {
        final id = message['id'];
        return id == null || !existingIds.contains(id);
      }).toList();

      setState(() {
        _messages = [...uniqueOlderMessages, ..._messages];
        _hasMoreMessages = olderMessages.length == _pageSize;
        _isLoadingOlder = false;
      });
      _emitMessages();
      // В reverse:true ListView позиция привязана к низу, поэтому при добавлении
      // старых сообщений сверху вьюпорт не сдвигается и ручная коррекция скролла
      // не нужна (раньше она вызывала лавинообразную догрузку до начала чата).
    } catch (e) {
      debugPrint('Ошибка загрузки старых групповых сообщений: $e');
      if (mounted) {
        setState(() {
          _isLoadingOlder = false;
        });
      }
    }
  }

  void _scrollToBottom({
    Duration delay = Duration.zero,
    bool animated = true,
  }) {
    if (_messages.isEmpty) return;

    void scroll() {
      if (!mounted || !_scrollController.hasClients) return;

      if (animated) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    }

    if (delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scroll());
    } else {
      Future.delayed(delay, scroll);
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      // Оптимистичное обновление
      final tempMessage = {
        'sender_id': currentUserId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'sender_name': 'Вы',
        'is_temp': true,
      };

      if (mounted) {
        final shouldScroll = _isNearBottom();
        setState(() {
          _messages.add(tempMessage);
        });
        _emitMessages();
        if (shouldScroll) {
          _scrollToBottom();
        }
      }

      await _chatService.sendGroupMessage(widget.groupChatId, content);
      if (!mounted) return;
      _messageController.clear();

      // Удаляем временное сообщение
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['is_temp'] == true);
        });
        _emitMessages();
      }
    } catch (e) {
      debugPrint('Ошибка отправки сообщения: $e');
      // Откатываем изменения при ошибке
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['is_temp'] == true);
        });
        _emitMessages();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить сообщение')),
      );
    }
  }

  void _showParticipants() {
    // Открываем лист мгновенно и грузим участников внутри (со спиннером),
    // чтобы не ждать сеть до появления окна.
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _chatService.getGroupChatParticipants(widget.groupChatId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Не удалось загрузить участников')),
                );
              }
              final participants = snapshot.data ?? const [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Участники (${participants.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: participants.length,
                      itemBuilder: (context, index) {
                        final participant = participants[index];
                        final rawAvatar =
                            (participant['avatar_url'] ?? '').toString();
                        final avatarUrl = rawAvatar.isEmpty
                            ? ''
                            : rawAvatar.replaceAll('localhost:9000',
                                AppConfig.mediaBaseUrlWithoutScheme);
                        final isMe = participant['id'] == currentUserId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            '${participant['full_name'] ?? 'Пользователь'}'
                            '${isMe ? ' (вы)' : ''}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showAddParticipantsModal() {
    if (currentUserId == null) return;

    // Открываем модалку сразу (без блокирующего пред-запроса участников) —
    // список подписчиков грузится внутри. Дубли всё равно не пройдут: бэкенд
    // в add_participant проверяет, что человек ещё не в чате.
    showDialog(
      context: context,
      builder: (context) => UserSelectionModal(
        userId: currentUserId!,
        onUserSelected: (int userId) async {
          try {
            await _chatService.addParticipantToGroupChat(
                widget.groupChatId, userId);
            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Участник добавлен')),
            );
          } catch (e) {
            debugPrint('Ошибка добавления участника: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка: ${e.toString()}')),
            );
          }
        },
      ),
    );
  }

  void _connectToWebSocket() {
    if (currentUserId == null) return;

    _chatService.connectToChat(
      currentUserId!,
      (message) {
        if (!mounted) return;

        // Сообщение удалено → убираем из UI у всех участников сразу.
        if (message['type'] == 'message_deleted' &&
            message['group_chat_id'] == widget.groupChatId) {
          final deletedId = message['message_id'];
          if (deletedId is int) {
            setState(() {
              _messages.removeWhere((m) => m['id'] == deletedId);
            });
            _emitMessages();
            ChatListScreen.state?.refreshUnreadMessagesCount();
          }
          return;
        }

        if (message['type'] == 'group' &&
            message['group_chat_id'] == widget.groupChatId &&
            mounted) {
          final messageId = message['id'];
          if (messageId is int &&
              _messages.any((item) => item['id'] == messageId)) {
            return;
          }

          final shouldScroll = _isNearBottom();
          setState(() {
            _messages.add(message);
          });
          _emitMessages();
          if (shouldScroll) {
            _scrollToBottom();
          }
          unawaited(_markMessagesAsRead());
        }
      },
    );
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final messageId = message['id'];
    if (messageId is! int) return;

    // Скрываем клавиатуру до показа диалога, чтобы не было прыжков layout-а.
    FocusManager.instance.primaryFocus?.unfocus();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Сообщение будет удалено у всех участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _chatService.deleteGroupMessage(widget.groupChatId, messageId);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
      });
      _emitMessages();
    } catch (e) {
      debugPrint('Ошибка удаления сообщения: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить сообщение')),
      );
    }
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isMe = message['sender_id'] == currentUserId;
    final isRead = message['is_read'] ?? false;
    final isTemp = message['is_temp'] ?? false;
    final senderName = message['sender_name']?.toString() ?? 'Пользователь';
    final time = _formatMessageTime(message['created_at']);

    final content = message['content']?.toString() ?? '';
    final textColor = isTemp
        ? AppColors.textMuted
        : (isMe ? AppColors.surface : AppColors.textPrimary);
    final metaColor =
        isMe ? AppColors.surface.withValues(alpha: 0.75) : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.md, 2),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && !isTemp)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            child: GestureDetector(
              onLongPress:
                  (isMe && !isTemp) ? () => _deleteMessage(message) : null,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: isMe ? null : Border.all(color: AppColors.border),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    content,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15.5,
                      height: 1.25,
                    ),
                  ),
                  if (time != null || (isMe && !isTemp)) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (time != null)
                          Text(
                            time,
                            style: TextStyle(
                              color: metaColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (isMe && !isTemp) ...[
                          if (time != null) const SizedBox(width: 3),
                          Icon(
                            isRead ? Icons.done_all : Icons.done,
                            color: isRead ? AppColors.routeSoft : metaColor,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseServerDateTime(dynamic rawDate) {
    final value = rawDate?.toString().trim();
    if (value == null || value.isEmpty) return null;

    final hasTimezone = RegExp(r'(z|Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
    final normalized = hasTimezone ? value : '${value}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  String? _formatMessageTime(dynamic rawDate) {
    final parsed = _parseServerDateTime(rawDate);
    if (parsed == null) return null;
    return DateFormat.Hm('ru').format(parsed);
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDay).inDays;

    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    return DateFormat.yMMMMd('ru').format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<_GroupChatTimelineItem> _buildTimelineItems(
    List<Map<String, dynamic>> messages,
  ) {
    final items = <_GroupChatTimelineItem>[];
    DateTime? previousDay;

    for (final message in messages) {
      final createdAt = _parseServerDateTime(message['created_at']);
      if (createdAt != null &&
          (previousDay == null || !_isSameDay(previousDay, createdAt))) {
        items.add(_GroupChatTimelineItem.date(_formatDateSeparator(createdAt)));
        previousDay = createdAt;
      }
      items.add(_GroupChatTimelineItem.message(message));
    }

    return items;
  }

  Widget _buildDateSeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    PushNotificationService.clearActiveConversation(
      conversationType: 'group',
      conversationId: widget.groupChatId,
    );
    unawaited(_markMessagesAsRead());
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messagesController.close();
    _chatService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: InkWell(
          onTap: _showParticipants,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.groupChatName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
        actions: [
          AppIconButton(
            icon: Icons.add,
            tooltip: 'Добавить участника',
            onPressed: _showAddParticipantsModal,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const AppLoading(label: 'Загружаем сообщения')
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _messagesController.stream,
                    initialData: _messages,
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const [];
                      final timelineItems = _buildTimelineItems(messages);
                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        itemCount:
                            timelineItems.length + (_isLoadingOlder ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingOlder &&
                              index == timelineItems.length) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.md),
                              child: AppLoading(),
                            );
                          }

                          final item =
                              timelineItems[timelineItems.length - 1 - index];
                          if (item.dateLabel != null) {
                            return _buildDateSeparator(item.dateLabel!);
                          }
                          return _buildMessage(item.message!);
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight:
                            120, // Максимальная высота (примерно 5 строк)
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Введите сообщение...',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null, // Автоматическое количество строк
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: IconButton(
                      tooltip: 'Отправить',
                      icon: const Icon(Icons.send_rounded,
                          color: AppColors.surface),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
