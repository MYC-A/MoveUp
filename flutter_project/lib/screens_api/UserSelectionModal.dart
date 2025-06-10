import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';

class UserSelectionModal extends StatefulWidget {
  final int userId;
  final Function(int) onUserSelected;

  UserSelectionModal({required this.userId, required this.onUserSelected});

  @override
  _UserSelectionModalState createState() => _UserSelectionModalState();
}

class _UserSelectionModalState extends State<UserSelectionModal> {
  final LkUsersService lkService = LkUsersService();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> followers = [];
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
      final newFollowers = response['followers'];
      setState(() {
        followers.addAll(newFollowers);
        skip += limit;
        hasMore = newFollowers.length == limit;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке подписчиков: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
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
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(follower['avatar_url'] ?? ''),
                ),
                title: Text(follower['full_name'] ?? 'Нет имени'),
                onTap: () {
                  widget.onUserSelected(follower['id']);
                },
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
            Navigator.pop(context);
          },
          child: Text('Закрыть'),
        ),
      ],
    );
  }
}
