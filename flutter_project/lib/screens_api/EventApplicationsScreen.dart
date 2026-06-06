import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/lk_service.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:flutter_application_1/screens_api/UserProfiles.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';

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
  Map<String, dynamic>? eventSummary;
  bool _changed = false;

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
        if (data['event'] is Map) {
          eventSummary = Map<String, dynamic>.from(data['event']);
        }
        skip += limit;
        hasMore = data['applications'].length == limit;
      });
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
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
        if (data['event'] is Map) {
          eventSummary = Map<String, dynamic>.from(data['event']);
        }
        participantsSkip += participantsLimit;
        hasMoreParticipants =
            data['participants'].length == participantsLimit;
      });
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
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
      final result =
          await lkService.approveApplication(widget.eventId, participantId);
      if (result['event'] is Map && mounted) {
        setState(() {
          eventSummary = Map<String, dynamic>.from(result['event']);
        });
      }
      _changed = true;
      await _reloadApplications();
      await _reloadParticipants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка одобрена')),
      );
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  Future<void> _rejectApplication(int participantId) async {
    try {
      final result =
          await lkService.rejectApplication(widget.eventId, participantId);
      if (result['event'] is Map && mounted) {
        setState(() {
          eventSummary = Map<String, dynamic>.from(result['event']);
        });
      }
      _changed = true;
      await _reloadApplications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Заявка отклонена')),
      );
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  Future<void> _removeParticipant(int participantId) async {
    try {
      final result =
          await lkService.removeEventParticipant(widget.eventId, participantId);
      if (result['event'] is Map && mounted) {
        setState(() {
          eventSummary = Map<String, dynamic>.from(result['event']);
        });
      }
      _changed = true;
      await _reloadParticipants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Участник удален')),
      );
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: WillPopScope(
        onWillPop: () async {
          Navigator.pop(context, _changed);
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Участники события'),
            centerTitle: true,
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Заявки'),
                Tab(text: 'Участники'),
              ],
            ),
          ),
          body: Column(
            children: [
              _buildEventSummary(),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildApplicationsList(),
                    _buildParticipantsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventSummary() {
    final summary = eventSummary;
    if (summary == null) return const SizedBox.shrink();

    final available = _intValue(summary['available_seats']);
    final maxParticipants = _intValue(summary['max_participants']);
    final approved = _intValue(summary['participants_count']);
    final pending = _intValue(summary['pending_applications_count']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _SummaryValue(
            icon: Icons.event_seat_outlined,
            label: 'Свободно',
            value: '$available/$maxParticipants',
          ),
          _SummaryValue(
            icon: Icons.groups_outlined,
            label: 'Участники',
            value: '$approved',
          ),
          _SummaryValue(
            icon: Icons.hourglass_top_outlined,
            label: 'Ожидают',
            value: '$pending',
          ),
        ],
      ),
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _openUserProfile(dynamic userId) {
    final id = userId is int ? userId : int.tryParse(userId?.toString() ?? '');
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserProfiles(userId: id)),
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
                child: CircularProgressIndicator(color: AppColors.primary),
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
              leading: CircleAvatar(
                child: Text(_initial(application['user_name'])),
              ),
              title: Text(application['user_name'] ?? 'Участник'),
              subtitle: const Text(
                'Ожидает решения · нажмите, чтобы открыть профиль',
              ),
              onTap: () => _openUserProfile(application['user_id']),
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
                child: CircularProgressIndicator(color: AppColors.primary),
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
                child: Text(_initial(participant['user_name'])),
              ),
              title: Text(participant['user_name'] ?? 'Участник'),
              subtitle: const Text('Одобрен · нажмите, чтобы открыть профиль'),
              onTap: () => _openUserProfile(participant['user_id']),
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

  String _initial(dynamic name) {
    final value = name?.toString().trim() ?? '';
    return value.isEmpty ? '?' : value.substring(0, 1).toUpperCase();
  }
}

class _SummaryValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}
