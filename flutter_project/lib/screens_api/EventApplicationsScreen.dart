import 'package:flutter/material.dart';
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
  List<dynamic> applications = [];
  List<dynamic> participants = [];
  int skip = 0;
  final int limit = 10;
  bool isLoading = false;
  bool hasMore = true;
  int participantsSkip = 0;
  final int participantsLimit = 50;
  bool isLoadingParticipants = false;
  bool hasMoreParticipants = true;

  @override
  void initState() {
    super.initState();
    _loadApplications();
    _loadParticipants();
  }

  Future<void> _reloadApplications() async {
    setState(() {
      applications.clear();
      skip = 0;
      hasMore = true;
    });
    await _loadApplications();
  }

  Future<void> _reloadParticipants() async {
    setState(() {
      participants.clear();
      participantsSkip = 0;
      hasMoreParticipants = true;
    });
    await _loadParticipants();
  }

  Future<void> _loadApplications() async {
    if (isLoading || !hasMore) return;

    setState(() {
      isLoading = true;
    });

    try {
      final data =
          await lkService.fetchEventApplications(widget.eventId, skip, limit);
      if (!mounted) return;
      setState(() {
        applications.addAll(data['applications']);
        skip += limit;
        hasMore = data['applications'].length == limit;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadParticipants() async {
    if (isLoadingParticipants || !hasMoreParticipants) return;

    setState(() {
      isLoadingParticipants = true;
    });

    try {
      final data = await lkService.fetchEventParticipants(
          widget.eventId, participantsSkip, participantsLimit);
      if (!mounted) return;
      setState(() {
        participants.addAll(data['participants']);
        participantsSkip += participantsLimit;
        hasMoreParticipants =
            data['participants'].length == participantsLimit;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoadingParticipants = false;
        });
      }
    }
  }

  Future<void> _approveApplication(int participantId) async {
    try {
      await lkService.approveApplication(widget.eventId, participantId);
      await _reloadApplications();
      await _reloadParticipants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка одобрена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _rejectApplication(int participantId) async {
    try {
      await lkService.rejectApplication(widget.eventId, participantId);
      await _reloadApplications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка отклонена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _removeParticipant(int participantId) async {
    try {
      await lkService.removeEventParticipant(widget.eventId, participantId);
      await _reloadParticipants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Участник удален')),
      );
    } catch (e) {
      if (!mounted) return;
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
          title: Text('Участники события'),
          centerTitle: true,
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          bottom: TabBar(
            tabs: [
              Tab(text: 'Заявки'),
              Tab(text: 'Участники'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildApplicationsList(),
            _buildParticipantsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationsList() {
    if (applications.isEmpty && !isLoading) {
      return Center(
        child: Text(
          'Заявок на мероприятие нет.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reloadApplications,
      child: ListView.builder(
        itemCount: applications.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == applications.length) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            );
          }

          final application = applications[index];
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              title: Text(application['user_name']),
              subtitle: Text('Ожидает решения'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Одобрить',
                    icon: Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () => _approveApplication(application['id']),
                  ),
                  IconButton(
                    tooltip: 'Отклонить',
                    icon: Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => _rejectApplication(application['id']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildParticipantsList() {
    if (participants.isEmpty && !isLoadingParticipants) {
      return Center(
        child: Text(
          'Одобренных участников пока нет.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reloadParticipants,
      child: ListView.builder(
        itemCount: participants.length + (hasMoreParticipants ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == participants.length) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            );
          }

          final participant = participants[index];
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (participant['user_name'] ?? '?').toString().isEmpty
                      ? '?'
                      : (participant['user_name'] ?? '?')
                          .toString()
                          .substring(0, 1),
                ),
              ),
              title: Text(participant['user_name'] ?? 'Участник'),
              subtitle: Text('Одобрен'),
              trailing: IconButton(
                tooltip: 'Удалить участника',
                icon: Icon(Icons.person_remove_alt_1, color: Colors.red),
                onPressed: () => _removeParticipant(participant['id']),
              ),
            ),
          );
        },
      ),
    );
  }
}
