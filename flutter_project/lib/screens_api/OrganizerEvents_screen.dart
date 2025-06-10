import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/EventApplicationsScreen.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/services_api/EventTranslations.dart';

class OrganizerEventsScreen extends StatefulWidget {
  @override
  _OrganizerEventsScreenState createState() => _OrganizerEventsScreenState();
}

class _OrganizerEventsScreenState extends State<OrganizerEventsScreen> {
  final LkService lkService = LkService();

  // Мероприятия
  List<dynamic> events = [];
  int skipEvents = 0;
  final int limitEvents = 10;
  bool isLoadingEvents = false;
  bool hasMoreEvents = true;
  final ScrollController _eventScrollController = ScrollController();

  // Заявки
  List<dynamic> userApplications = [];
  int skipApplications = 0;
  final int limitApplications = 10;
  bool isLoadingApplications = false;
  bool hasMoreApplications = true;
  final ScrollController _applicationsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _loadUserApplications();
    _markNotificationsAsRead();

    _eventScrollController.addListener(_onEventScroll);
    _applicationsScrollController.addListener(_onApplicationsScroll);
  }

  // Загружаем мероприятия при скролле вниз
  void _onEventScroll() {
    if (_eventScrollController.position.pixels >=
        _eventScrollController.position.maxScrollExtent - 200) {
      _loadEvents();
    }
  }

  // Загружаем заявки при скролле вниз
  void _onApplicationsScroll() {
    if (_applicationsScrollController.position.pixels >=
        _applicationsScrollController.position.maxScrollExtent - 200) {
      _loadUserApplications();
    }
  }

  Future<void> _loadEvents() async {
    if (isLoadingEvents || !hasMoreEvents) return;

    setState(() {
      isLoadingEvents = true;
    });

    try {
      final data = await lkService.fetchEvents(skipEvents, limitEvents);
      setState(() {
        events.addAll(data['events']);
        skipEvents += data['events'].length as int;
        hasMoreEvents = data['events'].length == limitEvents;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки мероприятий: $e')),
      );
    } finally {
      setState(() {
        isLoadingEvents = false;
      });
    }
  }

  Future<void> _loadUserApplications() async {
    if (isLoadingApplications || !hasMoreApplications) return;

    setState(() {
      isLoadingApplications = true;
    });

    try {
      final data = await lkService.fetchUserApplications(
          skipApplications, limitApplications);
      setState(() {
        userApplications.addAll(data['applications']);
        skipApplications += data['applications'].length as int;
        hasMoreApplications = data['applications'].length == limitApplications;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки заявок: $e')),
      );
    } finally {
      setState(() {
        isLoadingApplications = false;
      });
    }
  }

  Future<void> _markNotificationsAsRead() async {
    try {
      await lkService.markNotificationsAsRead();
    } catch (e) {
      print('Ошибка при сбросе уведомлений: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Мои мероприятия'),
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
            _buildEventsSection(),
            _buildApplicationsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsSection() {
    return ListView.builder(
      controller: _eventScrollController,
      itemCount: events.length + (hasMoreEvents ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == events.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.blueAccent),
            ),
          );
        }
        return _buildEventCard(events[index]);
      },
    );
  }

  Widget _buildEventCard(dynamic event) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(event['title']),
        subtitle: Text(
          'Дата: ${Helper.formatDateTime(event['start_time'])} - ${Helper.formatDateTime(event['end_time'])}',
        ),
        trailing: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    EventApplicationsScreen(eventId: event['id']),
              ),
            );
          },
          child: Text('Заявки'),
        ),
      ),
    );
  }

  Widget _buildApplicationsSection() {
    return ListView.builder(
      controller: _applicationsScrollController,
      itemCount: userApplications.length + (hasMoreApplications ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == userApplications.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.blueAccent),
            ),
          );
        }
        return _buildApplicationCard(userApplications[index]);
      },
    );
  }

  Widget _buildApplicationCard(dynamic application) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(application['event_title']),
        subtitle: Text(
            'Статус: ${EventTranslations.getStatusDisplayName(application['status'])}'),
      ),
    );
  }

  @override
  void dispose() {
    _eventScrollController.dispose();
    _applicationsScrollController.dispose();
    super.dispose();
  }
}
