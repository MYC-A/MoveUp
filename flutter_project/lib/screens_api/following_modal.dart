import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens_api/UserProfiles.dart';
import '../services_api/lk_service.dart';

class FollowingModal extends StatefulWidget {
  const FollowingModal({Key? key}) : super(key: key);

  @override
  _FollowingModalState createState() => _FollowingModalState();
}

class _FollowingModalState extends State<FollowingModal> {
  final LkService lkService = LkService();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> following = [];
  int skip = 0;
  int limit = 10;
  bool isLoading = false;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    if (isLoading || !hasMore) return;
    setState(() {
      isLoading = true;
    });

    try {
      final response = await lkService.fetchFollowing(skip, limit);
      final newFollowing = response['following'];
      setState(() {
        following.addAll(newFollowing);
        skip += limit;
        hasMore = newFollowing.length == limit;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке подписок: $e')),
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
      _loadFollowing();
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
      title: const Text('Подписки'),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: following.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < following.length) {
              final user = following[index];
              final avatarUrl = _getAvatarUrl(user['avatar_url']);
              print('Avatar URL (FollowingModal): $avatarUrl'); // Для отладки
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(avatarUrl),
                  child: avatarUrl == 'https://via.placeholder.com/150'
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(user['full_name'] ?? 'Нет имени'),
                onTap: () {
                  if (user['id'] != null) {
                    Navigator.pop(context); // Закрыть модальное окно
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfiles(userId: user['id']),
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
