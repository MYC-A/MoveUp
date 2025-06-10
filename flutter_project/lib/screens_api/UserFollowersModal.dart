import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services_api/LkUsersService.dart';
import '../screens_api/UserProfiles.dart';

class UserFollowersModal extends StatefulWidget {
  final int userId;

  const UserFollowersModal({required this.userId, Key? key}) : super(key: key);

  @override
  _UserFollowersModalState createState() => _UserFollowersModalState();
}

class _UserFollowersModalState extends State<UserFollowersModal> {
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

  String _getAvatarUrl(String? url) {
    return (url ?? '')
            .replaceAll('http://localhost:9000', 'http://91.200.84.206/minio')
            .isNotEmpty
        ? url!.replaceAll('http://localhost:9000', 'http://91.200.84.206/minio')
        : 'https://via.placeholder.com/150';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подписчики'),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: followers.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < followers.length) {
              final follower = followers[index];
              final avatarUrl = _getAvatarUrl(follower['avatar_url']);
              print('Avatar URL: $avatarUrl'); // Для отладки
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(avatarUrl),
                  child: avatarUrl == 'https://via.placeholder.com/150'
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(follower['full_name'] ?? 'Нет имени'),
                onTap: () {
                  if (follower['id'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UserProfiles(userId: follower['id']),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('ID пользователя не найден')),
                    );
                  }
                },
              );
            } else {
              return const Center(
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
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
