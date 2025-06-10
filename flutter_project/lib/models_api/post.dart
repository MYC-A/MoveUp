class Post {
  final int id;
  final int userId;
  final String content;
  final double distance;
  final int duration;
  final List<Map<String, dynamic>> routeData;
  int likesCount;
  int commentsCount;
  final DateTime createdAt;
  final String userFullName;
  final String? userAvatarUrl; // Поле может быть null
  final List<String>? photoUrls; // Поле может быть null
  bool likedByCurrentUser;
  bool isExpanded; // Новое поле для управления состоянием текста

  Post({
    required this.id,
    required this.userId,
    required this.content,
    required this.distance,
    required this.duration,
    required this.routeData,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    required this.userFullName,
    this.userAvatarUrl, // Поле может быть null
    this.photoUrls, // Поле может быть null
    this.likedByCurrentUser = false,
    this.isExpanded = false, // По умолчанию текст свернут
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    DateTime createdAt;
    if (createdAtRaw != null) {
      final parsedDate = DateTime.tryParse(createdAtRaw);
      if (parsedDate != null) {
        // Предполагаем, что время в UTC+5, конвертируем в UTC
        createdAt = parsedDate.subtract(Duration(hours: 5)); // UTC+5 -> UTC
        createdAt = createdAt.toLocal(); // UTC -> локальный пояс
        print('Parsed created_at: $createdAtRaw -> $createdAt');
      } else {
        createdAt = DateTime.now().toLocal();
        print(
            'Invalid created_at format: $createdAtRaw, using current time: $createdAt');
      }
    } else {
      createdAt = DateTime.now().toLocal();
      print('created_at is null, using current time: $createdAt');
    }

    return Post(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      distance: json['distance'],
      duration: json['duration'],
      routeData: List<Map<String, dynamic>>.from(json['route_data']),
      likesCount: json['likes_count'],
      commentsCount: json['comments_count'],
      createdAt: createdAt,
      userFullName: json['user']['full_name'],
      userAvatarUrl: json['user']['avatar_url'], // Может быть null
      photoUrls: json['photo_urls'] != null
          ? List<String>.from(json['photo_urls'])
          : null, // Может быть null
      likedByCurrentUser: json['liked_by_current_user'] ?? false,
      isExpanded: false, // По умолчанию текст свернут
    );
  }
}
