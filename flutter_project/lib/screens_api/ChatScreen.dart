import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatListScreen.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

class ChatScreen extends StatefulWidget {
  final int recipientId;

  ChatScreen({required this.recipientId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  int? currentUserId;
  late final KeyboardVisibilityController _keyboardVisibilityController;
  final _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  void initState() {
    super.initState();
    _keyboardVisibilityController = KeyboardVisibilityController();
    _keyboardVisibilityController.onChange.listen((bool visible) {
      if (visible) {
        _scrollToBottom();
      }
    });

    _initChat();
  }

  Future<void> _initChat() async {
    await _getCurrentUserId();
    await _loadMessages();
    _connectToChat();
    await _markMessagesAsRead();
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _chatService.markMessagesAsRead(widget.recipientId);
      ChatListScreen.state?.refreshUnreadMessagesCount();
    } catch (e) {
      print('Ошибка при отметке сообщений как прочитанных: $e');
    }
  }

  Future<void> _getCurrentUserId() async {
    final data = await _chatService.getChatData();
    setState(() {
      currentUserId = data['user']['id'];
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _messages.isNotEmpty) {
      // Добавляем небольшую задержку для гарантии, что контент обновился
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent +
              100, // Небольшой дополнительный отступ
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _chatService.disconnect();
    _messagesController.close();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final messages =
          await _chatService.getMessagesBetweenUsers(widget.recipientId);
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _messagesController.add(_messages);
      // Добавляем двойную задержку для гарантии прокрутки
      Future.delayed(const Duration(milliseconds: 50), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('Ошибка загрузки сообщений: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _connectToChat() {
    _chatService.connectToChat(
      currentUserId!,
      (message) {
        if (message['type'] == 'personal' &&
            message['sender_id'] == widget.recipientId &&
            message['recipient_id'] == currentUserId) {
          setState(() {
            _messages.add(message);
          });
          _messagesController.add(_messages);
          _scrollToBottom();
          ChatListScreen.state?.refreshUnreadMessagesCount();
        }
      },
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    try {
      await _chatService.sendMessage(widget.recipientId, content);
      _messageController.clear();

      final newMessage = {
        'sender_id': currentUserId,
        'content': content,
        'created_at': DateTime.now().toString(),
      };

      setState(() {
        _messages.add(newMessage);
      });

      _messagesController.add(_messages);
      _scrollToBottom();
      ChatListScreen.state?.refreshUnreadMessagesCount();
    } catch (e) {
      print('Ошибка отправки сообщения: $e');
    }
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isMe = message['sender_id'] == currentUserId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message['content'],
              style: TextStyle(
                fontSize: 16,
                color: isMe ? Colors.white : Colors.black,
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.recipientId == currentUserId
            ? 'Избранное'
            : 'Чат с пользователем'),
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
                          return _buildMessage(snapshot.data![index]);
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
