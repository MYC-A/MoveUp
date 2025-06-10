import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/UserFollowersModal.dart';
import 'package:flutter_application_1/screens_api/UserFollowingModal.dart';
import 'package:flutter_application_1/services_api/LkUsersService.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
import 'package:flutter_application_1/screens_api/ChatScreen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class UserProfiles extends StatefulWidget {
  final int userId;

  UserProfiles({required this.userId});

  @override
  _UserProfilesState createState() => _UserProfilesState();
}

class _UserProfilesState extends State<UserProfiles> {
  final LkUsersService lkUsersService = LkUsersService();
  final ScrollController _scrollController = ScrollController();
  bool isFollowing = false;
  bool isLoadingFollowStatus = true;

  // Единый CacheManager для приложения
  final customCacheManager = CacheManager(
    Config(
      'customCacheKey',
      stalePeriod: Duration(days: 7),
      maxNrOfCacheObjects: 100,
    ),
  );

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFollowStatus() async {
    try {
      final response = await lkUsersService.isFollowing(widget.userId);
      setState(() {
        isFollowing = response['is_following'] ?? false;
        isLoadingFollowStatus = false;
      });
    } catch (e) {
      print('Ошибка при проверке статуса подписки: $e');
      setState(() {
        isLoadingFollowStatus = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    try {
      if (isFollowing) {
        await lkUsersService.unfollowUser(widget.userId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вы отписались от пользователя')),
        );
      } else {
        await lkUsersService.followUser(widget.userId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вы подписались на пользователя')),
        );
      }
      setState(() {
        isFollowing = !isFollowing;
      });
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
        title: Text('Профиль пользователя'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: lkUsersService.fetchUserProfile(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return Center(child: Text('Нет данных'));
          }

          final profile = snapshot.data!;
          final user = profile['user'];
          final stats = profile['stats'];
          final avatarUrl = (user['avatar_url'] ?? '')
              .replaceAll('localhost:9000', '91.200.84.206/minio');

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      avatarUrl,
                                      cacheManager: customCacheManager,
                                    )
                                  : null,
                              radius: 50,
                              child: avatarUrl.isEmpty
                                  ? Icon(Icons.person, size: 50)
                                  : null,
                            ),
                            SizedBox(height: 16),
                            Text(
                              user['full_name'] ?? 'Нет имени',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text(user['bio'] ?? 'Нет биографии'),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Статистика активности',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('Постов: ${stats['posts_count']}'),
                      Text('Комментариев: ${stats['comments_count']}'),
                      Text('Лайков: ${stats['likes_count']}'),
                      SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FutureBuilder<Map<String, dynamic>>(
                            future: lkUsersService.fetchUserFollowers(
                                widget.userId, 0, 1),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return CircularProgressIndicator();
                              } else if (snapshot.hasError) {
                                return Text('Ошибка');
                              } else if (!snapshot.hasData) {
                                return Text('Нет данных');
                              }

                              final followersData = snapshot.data!;
                              final totalFollowers =
                                  followersData['total_followers'] ?? 0;

                              return Column(
                                children: [
                                  Text(
                                    'Подписчики',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text('$totalFollowers'),
                                  ElevatedButton(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            UserFollowersModal(
                                                userId: widget.userId),
                                      );
                                    },
                                    child: Text('Показать'),
                                  ),
                                ],
                              );
                            },
                          ),
                          FutureBuilder<Map<String, dynamic>>(
                            future: lkUsersService.fetchUserFollowing(
                                widget.userId, 0, 1),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return CircularProgressIndicator();
                              } else if (snapshot.hasError) {
                                return Text('Ошибка');
                              } else if (!snapshot.hasData) {
                                return Text('Нет данных');
                              }

                              final followingData = snapshot.data!;
                              final totalFollowing =
                                  followingData['total_following'] ?? 0;

                              return Column(
                                children: [
                                  Text(
                                    'Подписки',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text('$totalFollowing'),
                                  ElevatedButton(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            UserFollowingModal(
                                                userId: widget.userId),
                                      );
                                    },
                                    child: Text('Показать'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ChatScreen(recipientId: widget.userId),
                                ),
                              );
                            },
                            child: Text('Начать диалог'),
                          ),
                          isLoadingFollowStatus
                              ? CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _toggleFollow,
                                  child: Text(isFollowing
                                      ? 'Отписаться'
                                      : 'Подписаться'),
                                ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Посты пользователя',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              UserPosts(
                userId: widget.userId,
                scrollController: _scrollController,
              ),
            ],
          );
        },
      ),
    );
  }
}
