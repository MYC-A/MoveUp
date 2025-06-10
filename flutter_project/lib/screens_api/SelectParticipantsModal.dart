import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';

class SelectParticipantsModal extends StatefulWidget {
  final int userId;
  final Function(List<int>) onParticipantsSelected;

  const SelectParticipantsModal({
    required this.userId,
    required this.onParticipantsSelected,
  });

  @override
  _SelectParticipantsModalState createState() =>
      _SelectParticipantsModalState();
}

class _SelectParticipantsModalState extends State<SelectParticipantsModal> {
  final LkUsersService lkService = LkUsersService();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> followers = [];
  List<int> selectedParticipants = [];
  int skip = 0;
  int limit = 10;
  bool isLoading = false;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    if (isLoading || !hasMore) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response =
          await lkService.fetchUserFollowers(widget.userId, skip, limit);

      if (response == null || response['followers'] == null) {
        throw Exception("Ошибка загрузки подписчиков: данные отсутствуют");
      }

      final List<Map<String, dynamic>> newFollowers =
          List<Map<String, dynamic>>.from(response['followers']);

      setState(() {
        followers.addAll(newFollowers);
        skip += limit;
        hasMore = newFollowers.length == limit;
      });
    } catch (e) {
      print('Ошибка при загрузке подписчиков: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при загрузке подписчиков')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent) {
      _loadFollowers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Выберите участников'),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: followers.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < followers.length) {
              final follower = followers[index];
              String? avatarUrl = follower['avatar_url'] as String?;

              // Проверяем, есть ли полный URL
              bool isValidUrl = avatarUrl != null &&
                  avatarUrl.isNotEmpty &&
                  (avatarUrl.startsWith("http://") ||
                      avatarUrl.startsWith("https://"));

              return CheckboxListTile(
                value: selectedParticipants.contains(follower['id']),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    if (value) {
                      selectedParticipants.add(follower['id']);
                    } else {
                      selectedParticipants.remove(follower['id']);
                    }
                  });
                },
                title: Text(follower['full_name'] ?? 'Нет имени'),
                secondary: CircleAvatar(
                  backgroundImage: isValidUrl
                      ? NetworkImage(avatarUrl!)
                      : AssetImage('assets/images/default_avatar.png')
                          as ImageProvider,
                  onBackgroundImageError: (_, __) {
                    // Если изображение не загружается, используем заглушку
                    setState(() {});
                  },
                ),
              );
            } else {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (mounted) {
              Navigator.pop(context);
            }
          },
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (selectedParticipants.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Выберите хотя бы одного участника')),
              );
              return;
            }

            try {
              widget.onParticipantsSelected(selectedParticipants);
              if (mounted) {
                Navigator.pop(context);
              }
            } catch (e) {
              print('Ошибка при передаче участников: $e');
            }
          },
          child: Text('Готово'),
        ),
      ],
    );
  }
}
