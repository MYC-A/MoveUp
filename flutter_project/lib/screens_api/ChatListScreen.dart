import 'dart:async'; // Импортируем библиотеку для работы с Timer
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();

  // Публичный метод для перезагрузки данных чата
  void reloadChatData() {
    if (state != null) {
      print("РАБОТАЕТ");
      state!._loadChatData();
    } else {
      print("НЕ РАБОТАЕТ");
    }
  }

  static _ChatListScreenState? state; // Публичное статическое поле
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _groupChats = [];
  final LkUsersService lkService = LkUsersService();
  bool _isLoading = true;
  int? currentUserId;
  Map<int, int> _unreadPersonalMessagesCount = {}; // Для личных чатов
  Map<int, int> _unreadGroupMessagesCount = {}; // Для групповых чатов
  Timer? _timer; // Таймер для polling

  @override
  void initState() {
    super.initState();
    ChatListScreen.state = this; // Устанавливаем ссылку на состояние
    print("Состояние установлено: ${ChatListScreen.state}");

    _loadChatData();
    _loadUnreadMessagesCount();

    // Запускаем polling каждые 5 секунд
    _timer = Timer.periodic(Duration(seconds: 5), (Timer t) {
      _loadChatData();
      _loadUnreadMessagesCount();
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Отменяем таймер при уничтожении виджета
    ChatListScreen.state = null; // Очищаем ссылку при уничтожении
    super.dispose();
  }

  Future<void> _loadChatData() async {
    try {
      final data = await _chatService.getChatData();
      setState(() {
        currentUserId = data['user']['id'];
        _users = List<Map<String, dynamic>>.from(data['users_with_messages']);
        _groupChats = List<Map<String, dynamic>>.from(data['group_chats']);
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка загрузки данных чата: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnreadMessagesCount() async {
    try {
      final count = await _chatService.getUnreadMessagesCount();
      setState(() {
        _unreadPersonalMessagesCount = count['personal'] ?? {};
        _unreadGroupMessagesCount = count['group'] ?? {};
        print(
            "Личные: $_unreadPersonalMessagesCount, Группы: $_unreadGroupMessagesCount");
      });
    } catch (e) {
      print('Ошибка загрузки количества непрочитанных сообщений: $e');
    }
  }

  // Публичный метод-обертка
  Future<void> refreshUnreadMessagesCount() async {
    await _loadUnreadMessagesCount();
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
                    final response = await lkService.fetchUserFollowers(
                        currentUserId!, 0, 100);
                    final followers =
                        response['followers'] as List<dynamic>? ?? [];

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
                                _loadChatData();
                                _loadUnreadMessagesCount();
                              } catch (e) {
                                print('Ошибка создания чата: $e');
                              }
                            }
                          },
                        );
                      },
                    );
                  } catch (e) {
                    print('Ошибка загрузки подписчиков: $e');
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
      appBar: AppBar(
        title: Text('Чаты'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showCreateGroupChatDialog,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ..._users.map((user) {
                  final unreadCount =
                      _unreadPersonalMessagesCount[user['id']] ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text(
                        user['full_name'][0],
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(user['full_name']),
                    subtitle: Text('Личный чат'),
                    trailing: unreadCount > 0
                        ? CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red,
                            child: Text(
                              unreadCount.toString(),
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatScreen(recipientId: user['id']),
                        ),
                      ).then((_) {
                        _loadUnreadMessagesCount();
                      });
                    },
                  );
                }).toList(),
                ..._groupChats.map((groupChat) {
                  final unreadCount =
                      _unreadGroupMessagesCount[groupChat['id']] ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.group, color: Colors.white),
                    ),
                    title: Text(groupChat['name']),
                    subtitle: Text('Групповой чат'),
                    trailing: unreadCount > 0
                        ? CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red,
                            child: Text(
                              unreadCount.toString(),
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            groupChatId: groupChat['id'],
                            groupChatName: groupChat['name'],
                          ),
                        ),
                      ).then((_) {
                        _loadUnreadMessagesCount();
                      });
                    },
                  );
                }).toList(),
              ],
            ),
    );
  }
}
