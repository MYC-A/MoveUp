import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:intl/intl.dart';

class _ChatTimelineItem {
  final Map<String, dynamic>? message;
  final String? dateLabel;

  const _ChatTimelineItem.message(this.message) : dateLabel = null;
  const _ChatTimelineItem.date(this.dateLabel) : message = null;
}

class ChatScreen extends StatefulWidget {
  final int recipientId;

  /// Имя собеседника, если оно уже известно — чтобы заголовок показался сразу,
  /// без мигания «Чат» во время загрузки профиля.
  final String? recipientName;

  ChatScreen({required this.recipientId, this.recipientName});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _pageSize = 30;

  final ChatService _chatService = ChatService();
  final LkUsersService _lkService = LkUsersService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasMoreMessages = true;
  int? currentUserId;
  String? _recipientName;
  // Минимальный интервал между подгрузками старых сообщений — чтобы один
  // «флинг» вверх не вызывал цепочку догрузок до начала переписки.
  DateTime? _lastOlderLoadAt;
  final _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  void initState() {
    super.initState();
    _recipientName = widget.recipientName;
    PushNotificationService.setActiveConversation(
      conversationType: 'personal',
      conversationId: widget.recipientId,
    );
    _scrollController.addListener(_handleScroll);

    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final results = await Future.wait<dynamic>([
        _chatService.getCachedCurrentUserId(),
        _chatService.getMessagesBetweenUsers(
          widget.recipientId,
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
      _connectToChat();
      _loadRecipientName();
      await _markMessagesAsRead();
    } catch (e) {
      debugPrint('Ошибка инициализации чата: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _chatService.markMessagesAsRead(widget.recipientId);
      ChatListScreen.state?.refreshUnreadMessagesCount();
    } catch (e) {
      debugPrint('Ошибка при отметке сообщений как прочитанных: $e');
    }
  }

  void _emitMessages() {
    if (!_messagesController.isClosed) {
      _messagesController.add(_messages);
    }
  }

  Future<void> _loadRecipientName() async {
    if (widget.recipientId == currentUserId) return;
    // Имя уже передали — не дёргаем сеть и не мигаем заголовком.
    if (_recipientName != null && _recipientName!.isNotEmpty) return;
    try {
      final profile = await _lkService.fetchUserProfile(widget.recipientId);
      final name = profile['user']?['full_name']?.toString();
      if (mounted && name != null && name.isNotEmpty) {
        setState(() => _recipientName = name);
      }
    } catch (e) {
      debugPrint('Не удалось загрузить имя собеседника: $e');
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingOlder ||
        !_hasMoreMessages) {
      return;
    }
    // Не чаще одной догрузки в 600мс, иначе инерционный скролл вверх
    // успевает дёрнуть подгрузку много раз подряд.
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

  @override
  void dispose() {
    PushNotificationService.clearActiveConversation(
      conversationType: 'personal',
      conversationId: widget.recipientId,
    );
    unawaited(_markMessagesAsRead());
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _chatService.disconnect();
    _messagesController.close();
    super.dispose();
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
      final olderMessages = await _chatService.getMessagesBetweenUsers(
        widget.recipientId,
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
      // В reverse:true ListView позиция привязана к низу, поэтому ручная
      // коррекция скролла не нужна (раньше она вызывала лавинообразную
      // догрузку до начала переписки с одного свайпа).
    } catch (e) {
      debugPrint('Ошибка загрузки старых сообщений: $e');
      if (mounted) {
        setState(() {
          _isLoadingOlder = false;
        });
      }
    }
  }

  void _connectToChat() {
    _chatService.connectToChat(
      currentUserId!,
      (message) {
        if (!mounted) return;

        // Собеседник прочитал наши сообщения → меняем ✓ на ✓✓ в реальном времени.
        if (message['type'] == 'read_receipt' &&
            message['reader_id'] == widget.recipientId) {
          setState(() {
            for (int i = 0; i < _messages.length; i++) {
              if (_messages[i]['sender_id'] == currentUserId &&
                  _messages[i]['is_read'] == false) {
                _messages[i] = Map<String, dynamic>.from(_messages[i])
                  ..['is_read'] = true;
              }
            }
          });
          return;
        }

        if (message['type'] == 'personal' &&
            message['sender_id'] == widget.recipientId &&
            message['recipient_id'] == currentUserId) {
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

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      final shouldScroll = _isNearBottom();
      final savedMessage =
          await _chatService.sendMessage(widget.recipientId, content);
      if (!mounted) return;
      _messageController.clear();

      final newMessage = {
        ...savedMessage,
        'sender_id': savedMessage['sender_id'] ?? currentUserId,
        'recipient_id': savedMessage['recipient_id'] ?? widget.recipientId,
        'content': savedMessage['content'] ?? content,
        'created_at': savedMessage['created_at'] ??
            DateTime.now().toUtc().toIso8601String(),
      };

      setState(() {
        _messages.add(newMessage);
      });

      _emitMessages();
      if (shouldScroll) {
        _scrollToBottom();
      }
      ChatListScreen.state?.refreshUnreadMessagesCount();
    } catch (e) {
      debugPrint('Ошибка отправки сообщения: $e');
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final messageId = message['id'];
    if (messageId is! int) return;

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
      await _chatService.deleteMessage(messageId);
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
    final text = message['content']?.toString() ?? '';
    final time = _formatMessageTime(message['created_at']?.toString());

    final metaColor =
        isMe ? AppColors.surface.withValues(alpha: 0.75) : AppColors.textMuted;

    final bubble = Container(
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
            text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.25,
              color: isMe ? AppColors.surface : AppColors.textPrimary,
            ),
          ),
          if (time != null || isMe) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time != null)
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: metaColor,
                    ),
                  ),
                if (isMe) ...[
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
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.md, 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          child: isMe
              ? GestureDetector(
                  onLongPress: () => _deleteMessage(message),
                  child: bubble,
                )
              : bubble,
        ),
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

  List<_ChatTimelineItem> _buildTimelineItems(
    List<Map<String, dynamic>> messages,
  ) {
    final items = <_ChatTimelineItem>[];
    DateTime? previousDay;

    for (final message in messages) {
      final createdAt = _parseServerDateTime(message['created_at']);
      if (createdAt != null &&
          (previousDay == null || !_isSameDay(previousDay, createdAt))) {
        items.add(_ChatTimelineItem.date(_formatDateSeparator(createdAt)));
        previousDay = createdAt;
      }
      items.add(_ChatTimelineItem.message(message));
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          widget.recipientId == currentUserId
              ? 'Избранное'
              : (_recipientName ?? 'Чат'),
        ),
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
