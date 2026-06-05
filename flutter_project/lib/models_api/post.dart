class Post {
  final int id;
  final int userId;
  final String content;
  final double distance;
  final int duration;
  final String? city; // Город старта поста
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
    this.city,
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

  static DateTime _parseServerDateTime(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return DateTime.now().toLocal();

    final hasTimezone = RegExp(r'(z|Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
    final normalized = hasTimezone ? value : '${value}Z';
    return DateTime.tryParse(normalized)?.toLocal() ?? DateTime.now().toLocal();
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    return Post(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      content: (json['content'] ?? '').toString(),
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      city: json['city'] as String?,
      routeData: (json['route_data'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      createdAt: _parseServerDateTime(json['created_at'] as String?),
      userFullName: (user['full_name'] ?? 'Пользователь').toString(),
      userAvatarUrl: user['avatar_url'] as String?, // Может быть null
      photoUrls: json['photo_urls'] != null
          ? List<String>.from(json['photo_urls'])
          : null, // Может быть null
      likedByCurrentUser: json['liked_by_current_user'] ?? false,
      isExpanded: false, // По умолчанию текст свернут
    );
  }
}
