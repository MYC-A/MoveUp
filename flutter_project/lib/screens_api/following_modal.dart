import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens_api/UserProfiles.dart';
import '../services_api/lk_service.dart';
import '../services_api/api_error_ui.dart';

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
      if (mounted) showApiError(context, e);
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
            .replaceAll('http://localhost:9000', AppConfig.mediaBaseUrl)
            .isNotEmpty
        ? url!.replaceAll('http://localhost:9000', AppConfig.mediaBaseUrl)
        : 'https://via.placeholder.com/150';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подписки'),
      content: Container(
        width: double.maxFinite,
        child: following.isEmpty && isLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : following.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Вы пока ни на кого не подписаны'),
                  )
                : ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: following.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < following.length) {
              final user = following[index];
              final avatarUrl = _getAvatarUrl(user['avatar_url']);
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
