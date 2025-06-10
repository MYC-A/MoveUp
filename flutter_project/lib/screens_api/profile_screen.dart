import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/NotificationsScreen.dart';
import 'package:flutter_application_1/screens_api/OrganizerEvents_screen.dart';
import 'package:flutter_application_1/screens_api/followers_modal.dart';
import 'package:flutter_application_1/screens_api/following_modal.dart';
import '../services_api/lk_service.dart';
import 'dart:async'; // Для использования Timer
import 'package:image_picker/image_picker.dart'; // Для выбора изображения
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LkService lkService = LkService();
  final TextEditingController _bioController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isBioExpanded = false;

  // Метод для показа модального окна редактирования биографии
  void _showEditBioDialog(String? currentBio) {
    _bioController.text = currentBio ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Редактировать биографию'),
        content: TextField(
          controller: _bioController,
          maxLines: 4,
          decoration: InputDecoration(hintText: 'Введите биографию'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await lkService.updateProfile(bio: _bioController.text);
                Navigator.pop(context);
                setState(() {}); // Обновляем UI
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Биография обновлена')),
                );
              } catch (e) {
                print('Ошибка при обновлении профиля: $e'); // Логируем ошибку
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка при обновлении профиля: $e')),
                );
              }
            },
            child: Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // Метод для выбора изображения
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        await lkService.updateProfile(avatarPath: image.path);
        setState(() {}); // Обновляем UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Аватарка обновлена')),
        );
      }
    } catch (e) {
      print('Ошибка при обновлении аватарки: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при обновлении аватарки: $e')),
      );
    }
  }

  // Метод для показа диалога выбора источника изображения
  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выберите источник'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
            child: Text('Галерея'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
            child: Text('Камера'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Личный кабинет'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        actions: [
          NotificationIcon(lkService: lkService),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: lkService.fetchProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Ошибка: ${snapshot.error}',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
            );
          } else if (!snapshot.hasData) {
            return Center(
              child: Text(
                'Нет данных',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          final profile = snapshot.data!;
          final user = profile['user'];
          print('Аватарка: ${user['avatar_url']}');
          final stats = profile['stats'];

          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Аватар и информация о пользователе
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap:
                            _showImageSourceDialog, // Вызываем диалог по нажатию
                        child: Stack(
                          children: [
                            CircleAvatar(
                              backgroundImage: NetworkImage(
                                (user['avatar_url'] ?? '').replaceAll(
                                    'localhost:9000', '91.200.84.206/minio'),
                              ),
                              radius: 50,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        user['full_name'] ?? 'Нет имени',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _isBioExpanded
                                ? (user['bio'] ?? 'Нет биографии')
                                : (user['bio'] != null &&
                                        user['bio'].length > 150
                                    ? '${user['bio'].substring(0, 150)}...'
                                    : user['bio'] ?? 'Нет биографии'),
                            textAlign: TextAlign.center,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if ((user['bio']?.length ?? 0) > 150)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isBioExpanded = !_isBioExpanded;
                                    });
                                  },
                                  child: Text(_isBioExpanded
                                      ? 'Свернуть'
                                      : 'Развернуть'),
                                ),
                              IconButton(
                                icon: Icon(Icons.edit, size: 20),
                                onPressed: () =>
                                    _showEditBioDialog(user['bio']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Статистика активности
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Статистика активности',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('Постов: ${stats['posts_count']}'),
                        Text('Комментариев: ${stats['comments_count']}'),
                        Text('Лайков: ${stats['likes_count']}'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),

                // Подписчики и подписки
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => FollowersModal(),
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            '${user['total_subscribers']}',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text('Подписчики'),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => FollowingModal(),
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            '${user['total_subscriptions']}',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text('Подписки'),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '${stats['posts_count']}',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text('Посты'),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 24),

                // Кнопка для просмотра мероприятий
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrganizerEventsScreen(),
                        ),
                      );
                    },
                    child: Text('Просмотреть мероприятия'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationIcon extends StatefulWidget {
  final LkService lkService;

  NotificationIcon({required this.lkService});

  @override
  _NotificationIconState createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  bool hasNewNotifications = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkNotifications();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 10), (timer) {
      _checkNotifications();
    });
  }

  Future<void> _checkNotifications() async {
    try {
      final notifications = await widget.lkService.fetchNotifications();
      setState(() {
        hasNewNotifications = notifications['new_applications'].isNotEmpty ||
            notifications['user_applications_changes'].isNotEmpty;
      });
    } catch (e) {
      print('Ошибка при проверке уведомлений: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        children: [
          Icon(Icons.notifications),
          if (hasNewNotifications)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotificationsScreen(),
          ),
        ).then((_) {
          _checkNotifications();
        });
      },
    );
  }
}
