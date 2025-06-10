import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/ChatService.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';

class EventApplicationsScreen extends StatefulWidget {
  final int eventId;

  EventApplicationsScreen({required this.eventId});

  @override
  _EventApplicationsScreenState createState() =>
      _EventApplicationsScreenState();
}

class _EventApplicationsScreenState extends State<EventApplicationsScreen> {
  final LkService lkService = LkService();
  ChatService chatService = ChatService();
  List<dynamic> applications = [];
  int skip = 0;
  final int limit = 10;
  bool isLoading = false;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    if (isLoading || !hasMore) return;

    setState(() {
      isLoading = true;
    });

    try {
      final data =
          await lkService.fetchEventApplications(widget.eventId, skip, limit);
      setState(() {
        applications.addAll(data['applications']);
        skip += limit;
        hasMore = data['applications'].length == limit;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _approveApplication(
      int participantId, int participanUsertId) async {
    try {
      print(
          "participantId: $participanUsertId  participanUsertId: $participanUsertId");
      // Одобряем заявку и получаем данные мероприятия
      final eventData =
          await lkService.approveApplication(widget.eventId, participantId);
      final groupChatId = eventData['group_chat_id'];

      // Проверяем, есть ли group_chat_id
      if (groupChatId != null) {
        // Добавляем участника в групповой чат
        await chatService.addParticipantToGroupChat(
            groupChatId, participanUsertId);
      } else {
        // Показываем уведомление, если групповой чат не существует
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Групповой чат для этого мероприятия отсутствует')),
        );
      }

      // Обновляем список заявок
      await _loadApplications();

      // Показываем уведомление
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка одобрена')),
      );
    } catch (e) {
      // Показываем уведомление об ошибке
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _rejectApplication(int participantId) async {
    try {
      await lkService.rejectApplication(widget.eventId, participantId);
      _loadApplications(); // Обновляем список заявок
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка отклонена')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Заявки на мероприятие'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: applications.isEmpty && !isLoading
                ? Center(
                    child: Text(
                      'Заявок на мероприятие нет.',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: applications.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == applications.length) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                            ),
                          ),
                        );
                      }

                      final application = applications[index];
                      return Card(
                        margin:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          title: Text(application['user_name']),
                          subtitle: Text('Статус: ${application['status']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.check, color: Colors.green),
                                onPressed: () => _approveApplication(
                                    application['id'], application['user_id']),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: Colors.red),
                                onPressed: () =>
                                    _rejectApplication(application['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
