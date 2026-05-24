import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:flutter_application_1/screens_api/UserSelectionModal.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/screens_api/GroupChatScreen.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';

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

  void _notifyUnreadTotal(
    Map<int, int> personalCount,
    Map<int, int> groupCount,
  ) {
    final totalPersonal =
        personalCount.values.fold<int>(0, (sum, value) => sum + value);
    final totalGroup =
        groupCount.values.fold<int>(0, (sum, value) => sum + value);
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
          : _buildChatList(),
    );
  }

  Widget _buildChatList() {
    final itemCount = _users.length + _groupChats.length;
    if (itemCount == 0) {
      return Center(
        child: Text(
          'Пока нет чатов',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: itemCount,
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
    final unreadCount = _unreadPersonalMessagesCount[userId] ?? 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue,
        child: Text(
          _initialForName(fullName),
          style: TextStyle(color: Colors.white),
        ),
      ),
      title: Text(fullName),
      subtitle: Text('Личный чат'),
      trailing: _buildUnreadBadge(unreadCount),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(recipientId: userId),
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

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green,
        child: Icon(Icons.group, color: Colors.white),
      ),
      title: Text(groupChatName),
      subtitle: Text('Групповой чат'),
      trailing: _buildUnreadBadge(unreadCount),
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

  Widget? _buildUnreadBadge(int unreadCount) {
    if (unreadCount <= 0) return null;

    return CircleAvatar(
      radius: 12,
      backgroundColor: Colors.red,
      child: Text(
        unreadCount.toString(),
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
