import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/push_notification_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';

class ChatScreen extends StatefulWidget {
  final int recipientId;

  ChatScreen({required this.recipientId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _pageSize = 30;

  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasMoreMessages = true;
  int? currentUserId;
  final _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  void initState() {
    super.initState();
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

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingOlder ||
        !_hasMoreMessages) {
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

    setState(() {
      _isLoadingOlder = true;
    });

    final oldMaxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;

        final scrollDelta =
            _scrollController.position.maxScrollExtent - oldMaxScrollExtent;
        final targetOffset = (_scrollController.offset + scrollDelta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(targetOffset.toDouble());
      });
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
      await _chatService.sendMessage(widget.recipientId, content);
      if (!mounted) return;
      _messageController.clear();

      final newMessage = {
        'sender_id': currentUserId,
        'content': content,
        'created_at': DateTime.now().toString(),
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

  Widget _buildMessage(Map<String, dynamic> message) {
    final isMe = message['sender_id'] == currentUserId;
    final text = message['content']?.toString() ?? '';
    final time = _formatMessageTime(message['created_at']?.toString());

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxs,
        horizontal: AppSpacing.md,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : AppRadii.md),
                bottomRight: Radius.circular(isMe ? AppRadii.md : 20),
              ),
              border: isMe ? null : Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.28,
                    color: isMe ? AppColors.surface : AppColors.textPrimary,
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isMe
                          ? AppColors.surface.withValues(alpha: 0.72)
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _formatMessageTime(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return null;
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return null;

    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.recipientId == currentUserId ? 'Избранное' : 'Чат'),
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
                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        itemCount: messages.length + (_isLoadingOlder ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingOlder && index == messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.md),
                              child: AppLoading(),
                            );
                          }

                          final messageIndex = messages.length - 1 - index;
                          return _buildMessage(messages[messageIndex]);
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
