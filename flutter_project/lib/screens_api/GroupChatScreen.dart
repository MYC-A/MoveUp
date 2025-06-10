import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:intl/intl.dart';

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
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final StreamController<List<Map<String, dynamic>>> _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  int? currentUserId;
  late StreamSubscription<bool> _keyboardVisibilitySubscription;

  @override
  void initState() {
    super.initState();
    _initChat();

    _keyboardVisibilitySubscription =
        KeyboardVisibilityController().onChange.listen((bool visible) {
      if (visible) {
        _scrollToBottom();
      }
    });
  }

  Future<void> _initChat() async {
    await _getCurrentUserId();
    await _loadMessages();
    _connectToWebSocket();
    await _markMessagesAsRead();
  }

  Future<void> _getCurrentUserId() async {
    try {
      final data = await _chatService.getChatData();
      if (mounted) {
        setState(() {
          currentUserId = data['user']['id'];
        });
      }
    } catch (e) {
      print('Ошибка получения ID пользователя: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _chatService.getGroupMessages(widget.groupChatId);
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        _messagesController.add(_messages);
        _scrollToBottomWithDelay();
      }
    } catch (e) {
      print('Ошибка загрузки сообщений: $e');
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
      final unreadCount = await _chatService.getUnreadMessagesCount();
      print('Непрочитанных сообщений: $unreadCount');
    } catch (e) {
      print('Ошибка отметки сообщений как прочитанных: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _messages.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 150,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _scrollToBottomWithDelay() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 150,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
        setState(() {
          _messages.add(tempMessage);
        });
        _messagesController.add(_messages);
        _scrollToBottom();
      }

      await _chatService.sendGroupMessage(widget.groupChatId, content);
      _messageController.clear();

      // Удаляем временное сообщение
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['is_temp'] == true);
        });
      }
    } catch (e) {
      print('Ошибка отправки сообщения: $e');
      // Откатываем изменения при ошибке
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['is_temp'] == true);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить сообщение')),
      );
    }
  }

  void _showAddParticipantsModal() {
    if (currentUserId == null) return;

    showDialog(
      context: context,
      builder: (context) => UserSelectionModal(
        userId: currentUserId!,
        onUserSelected: (int userId) async {
          try {
            await _chatService.addParticipantToGroupChat(
                widget.groupChatId, userId);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Участник добавлен')),
            );
          } catch (e) {
            print('Ошибка добавления участника: $e');
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
        if (message['type'] == 'group' &&
            message['group_chat_id'] == widget.groupChatId &&
            mounted) {
          setState(() {
            _messages.add(message);
          });
          _messagesController.add(_messages);
          _scrollToBottom();
        }
      },
    );
  }

  Widget _buildMessage(int index) {
    final message = _messages[index];
    final isMe = message['sender_id'] == currentUserId;
    final isRead = message['is_read'] ?? false;
    final isTemp = message['is_temp'] ?? false;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isTemp)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Text(
              "${message['sender_name']} - ${_formatDateTime(message['created_at'])}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[100] : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message['content'],
                style: TextStyle(
                  color: isTemp ? Colors.grey : Colors.black,
                ),
              ),
              if (isMe && !isTemp)
                Icon(
                  isRead ? Icons.done_all : Icons.done,
                  color: isRead ? Colors.blue : Colors.grey,
                  size: 16,
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String isoDate) {
    try {
      // Парсим время из базы данных
      final dateFromDb = DateTime.parse(isoDate);

      const timeDifferenceHours = 5;

      // Корректируем время, добавляя разницу
      final dateCorrected =
          dateFromDb.add(Duration(hours: timeDifferenceHours));

      final now = DateTime.now();
      if (dateCorrected.year == now.year &&
          dateCorrected.month == now.month &&
          dateCorrected.day == now.day) {
        return DateFormat.Hm('ru')
            .format(dateCorrected); // Только время, если сегодня
      } else {
        return DateFormat.yMMMd('ru')
            .add_Hm()
            .format(dateCorrected); // Дата и время
      }
    } catch (e) {
      print('Ошибка форматирования времени: $e');
      return isoDate;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messagesController.close();
    _keyboardVisibilitySubscription.cancel();
    _chatService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupChatName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddParticipantsModal,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _messagesController.stream,
                    initialData: _messages,
                    builder: (context, snapshot) {
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: snapshot.data?.length ?? 0,
                        itemBuilder: (context, index) {
                          return _buildMessage(index);
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 120, // Максимальная высота (примерно 5 строк)
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Введите сообщение...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
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
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
