import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/screens_api/EventApplicationsScreen.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onNotificationsUpdated;

  NotificationsScreen({this.onNotificationsUpdated});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final LkService lkService = LkService();
  Map<String, dynamic> notifications = {};

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final data = await lkService.fetchNotifications();
      setState(() {
        notifications = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _markNotificationAsRead(int eventId, String type) async {
    try {
      await lkService.markNotificationAsRead(eventId, type);
      await _loadNotifications();
      if (widget.onNotificationsUpdated != null) {
        widget.onNotificationsUpdated!();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Уведомления'),
          centerTitle: true,
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          bottom: TabBar(
            tabs: [
              Tab(text: 'Мои мероприятия'),
              Tab(text: 'Мои заявки'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildNotificationSection(
              notifications: notifications['new_applications'] ?? [],
              type: 'application',
            ),
            _buildNotificationSection(
              notifications: notifications['user_applications_changes'] ?? [],
              type: 'change',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSection({
    required List<dynamic> notifications,
    required String type,
  }) {
    return ListView(
      children: [
        if (notifications.isEmpty)
          Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Нет уведомлений',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ...notifications.map((notification) {
          return ListTile(
            title: Text(notification['event_title']),
            subtitle: Text('Количество: ${notification['count']}'),
            trailing: notification['is_new']
                ? Icon(Icons.circle, color: Colors.red, size: 12)
                : Icon(Icons.arrow_forward),
            onTap: () async {
              // Помечаем уведомление как прочитанное перед переходом
              await _markNotificationAsRead(notification['event_id'], type);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EventApplicationsScreen(
                    eventId: notification['event_id'],
                  ),
                ),
              ).then((_) {
                // Обновляем уведомления после возврата
                _loadNotifications();
              });
            },
          );
        }).toList(),
      ],
    );
  }
}
