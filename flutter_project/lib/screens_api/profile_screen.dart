import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens_api/NotificationsScreen.dart';
import 'package:flutter_application_1/screens_api/OrganizerEvents_screen.dart';
import 'package:flutter_application_1/screens_api/followers_modal.dart';
import 'package:flutter_application_1/screens_api/following_modal.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_application_1/widgets/common/app_empty_state.dart';
import 'package:flutter_application_1/widgets/common/app_error_state.dart';
import 'package:flutter_application_1/widgets/common/app_loading.dart';
import 'package:flutter_application_1/widgets/UserPosts.dart';
import 'package:flutter_application_1/widgets/profile/profile_hero.dart';
import 'package:flutter_application_1/services_api/api_error_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services_api/lk_service.dart';
import '../services_api/EventService.dart';
import '../services_api/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const ProfileScreen({Key? key, this.onLogout}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LkService lkService = LkService();
  final EventService _eventService = EventService();
  final AuthService _authService = AuthService();
  final TextEditingController _bioController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;
  bool _isProfileVisible = true;
  DateTime _lastLoadAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _refreshTimer;

  /// Список городов для выбора в профиле (как в событиях).
  List<String> _cities = EventService.fallbackCities;

  // Допустимые границы для «обычного» человека — отсекаем явные опечатки.
  static const double _minWeightKg = 30;
  static const double _maxWeightKg = 250;
  static const double _minHeightCm = 100;
  static const double _maxHeightCm = 250;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCities();
    _startAutoRefresh();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await _eventService.getEventCities();
      if (!mounted || cities.isEmpty) return;
      setState(() => _cities = cities);
    } catch (e) {
      debugPrint('Не удалось загрузить список городов: $e');
    }
  }

  String _normalizeCityName(String value) {
    return value.trim().toLowerCase().replaceAll('ё', 'е');
  }

  bool _isKnownCity(String value) {
    final normalized = _normalizeCityName(value);
    return _cities.any((city) => _normalizeCityName(city) == normalized);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _bioController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Загрузка профиля. background=true — тихое обновление агрегатов без экрана
  // загрузки и без пересоздания списка постов (UserPosts остаётся смонтирован).
  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _lastLoadAt = DateTime.now();
    try {
      final data = await lkService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_profile == null) _error = e.toString();
      });
    }
  }

  // ЛК — вкладка в IndexedStack. При возврате тихо освежаем статистику и
  // запускаем периодическое обновление, пока экран виден.
  void _onVisibilityChanged(double visibleFraction) {
    final nowVisible = visibleFraction > 0.5;
    if (nowVisible && !_isProfileVisible) {
      if (DateTime.now().difference(_lastLoadAt) >
          const Duration(seconds: 2)) {
        _load(background: true);
      }
      _startAutoRefresh();
    } else if (!nowVisible && _isProfileVisible) {
      _stopAutoRefresh();
    }
    _isProfileVisible = nowVisible;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isProfileVisible) _load(background: true);
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _reloadProfile() => _load();

  Future<void> _handleRefresh() => _load(background: true);

  // Проверяет вес/рост/город. Возвращает текст ошибки или null, если всё ок.
  // Пустые значения допустимы (поля необязательные).
  String? _validateWeight(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null) return 'Введите число';
    if (value < _minWeightKg || value > _maxWeightKg) {
      return 'Вес должен быть от ${_minWeightKg.toInt()} до ${_maxWeightKg.toInt()} кг';
    }
    return null;
  }

  String? _validateHeight(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null) return 'Введите число';
    if (value < _minHeightCm || value > _maxHeightCm) {
      return 'Рост должен быть от ${_minHeightCm.toInt()} до ${_maxHeightCm.toInt()} см';
    }
    return null;
  }

  String? _validateCity(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!_isKnownCity(text)) return 'Выберите город из списка';
    return null;
  }

  static const int _bioMaxLength = 500;

  void _showEditProfileDialog(Map<String, dynamic> user) {
    final nameCtrl =
        TextEditingController(text: (user['full_name'] ?? '').toString());
    final bioCtrl =
        TextEditingController(text: (user['bio'] ?? '').toString());
    final cityCtrl =
        TextEditingController(text: (user['city'] ?? '').toString());
    final weightCtrl = TextEditingController(
        text: user['weight'] != null ? '${user['weight']}' : '');
    final heightCtrl = TextEditingController(
        text: user['height'] != null ? '${user['height']}' : '');

    String? nameError;
    String? cityError;
    String? weightError;
    String? heightError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Редактировать профиль'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Имя',
                    prefixIcon: const Icon(Icons.person_outline),
                    errorText: nameError,
                  ),
                  onChanged: (value) => setDialogState(() {
                    nameError = value.trim().length < 3
                        ? 'Имя должно быть не короче 3 символов'
                        : null;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioCtrl,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: _bioMaxLength,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    alignLabelWithHint: true,
                    helperText: 'Расскажите о себе, любимых маршрутах и целях',
                  ),
                ),
                const SizedBox(height: 4),
                // Город выбираем из известного списка (как в событиях).
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: cityCtrl.text),
                  optionsBuilder: (value) {
                    final query = _normalizeCityName(value.text);
                    if (query.isEmpty) return _cities.take(8);
                    return _cities
                        .where((c) => _normalizeCityName(c).contains(query))
                        .take(12);
                  },
                  onSelected: (city) {
                    cityCtrl.text = city;
                    setDialogState(() => cityError = _validateCity(city));
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Город',
                        helperText: 'Выберите город из списка',
                        errorText: cityError,
                      ),
                      onChanged: (value) {
                        cityCtrl.text = value;
                        setDialogState(() => cityError = _validateCity(value));
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Вес, кг',
                    errorText: weightError,
                  ),
                  onChanged: (value) =>
                      setDialogState(() => weightError = _validateWeight(value)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Рост, см',
                    errorText: heightError,
                  ),
                  onChanged: (value) =>
                      setDialogState(() => heightError = _validateHeight(value)),
                ),
              ],
            ),
          ),
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showChangePasswordDialog();
              },
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Сменить пароль'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                // Финальная проверка перед сохранением.
                final nErr = nameCtrl.text.trim().length < 3
                    ? 'Имя должно быть не короче 3 символов'
                    : null;
                final cErr = _validateCity(cityCtrl.text);
                final wErr = _validateWeight(weightCtrl.text);
                final hErr = _validateHeight(heightCtrl.text);
                if (nErr != null ||
                    cErr != null ||
                    wErr != null ||
                    hErr != null) {
                  setDialogState(() {
                    nameError = nErr;
                    cityError = cErr;
                    weightError = wErr;
                    heightError = hErr;
                  });
                  return;
                }

                try {
                  await lkService.updateProfile(
                    fullName: nameCtrl.text.trim(),
                    bio: bioCtrl.text,
                    city: cityCtrl.text.trim(),
                    weight: double.tryParse(
                        weightCtrl.text.trim().replaceAll(',', '.')),
                    height: double.tryParse(
                        heightCtrl.text.trim().replaceAll(',', '.')),
                  );
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  _load(background: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Профиль обновлён')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  showApiError(context, e);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final repeatCtrl = TextEditingController();
    String? error;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Смена пароля'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Текущий пароль'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Новый пароль'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: repeatCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Повторите новый пароль',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (newCtrl.text.length < 5) {
                        setDialogState(() =>
                            error = 'Пароль должен быть не короче 5 символов');
                        return;
                      }
                      if (newCtrl.text != repeatCtrl.text) {
                        setDialogState(() => error = 'Пароли не совпадают');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _authService.changePassword(
                          oldPassword: oldCtrl.text,
                          newPassword: newCtrl.text,
                        );
                        if (!mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Пароль изменён')),
                        );
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: Text(saving ? 'Сохраняем…' : 'Сменить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        await lkService.updateProfile(avatarPath: image.path);
        if (!mounted) return;
        _reloadProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватарка обновлена')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при обновлении аватарки: $e')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Галерея'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Камера'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFollowers() {
    showDialog(
      context: context,
      builder: (context) => FollowersModal(),
    );
  }

  void _openFollowing() {
    showDialog(
      context: context,
      builder: (context) => FollowingModal(),
    );
  }

  void _openOrganizerEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizerEventsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          NotificationIcon(lkService: lkService),
          if (widget.onLogout != null)
            IconButton(
              tooltip: 'Выйти',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
            ),
        ],
      ),
      body: VisibilityDetector(
        key: const Key('profile_visibility'),
        onVisibilityChanged: (info) =>
            _onVisibilityChanged(info.visibleFraction),
        child: Builder(
        builder: (context) {
          if (_profile == null) {
            if (_loading) {
              return const AppLoading(label: 'Загружаем профиль');
            }
            if (_error != null) {
              return AppErrorState(message: _error, onRetry: _reloadProfile);
            }
            return const AppEmptyState(
              icon: Icons.person_outline,
              title: 'Профиль не найден',
              message: 'Попробуйте обновить экран позже.',
            );
          }

          final profile = _profile!;
          final user = profile['user'];
          final stats = profile['stats'];
          final avatarUrl = (user['avatar_url'] ?? '').toString().replaceAll(
                'localhost:9000',
                AppConfig.mediaBaseUrlWithoutScheme,
              );
          final userId = (user['id'] as num?)?.toInt();

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileHero(
                          fullName: (user['full_name'] ?? 'Нет имени').toString(),
                          avatarImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          bio: user['bio']?.toString(),
                          city: user['city']?.toString(),
                          weight: user['weight'] is num
                              ? user['weight'] as num
                              : null,
                          height: user['height'] is num
                              ? user['height'] as num
                              : null,
                          postsCount:
                              ((stats['posts_count'] ?? 0) as num).toInt(),
                          followersCount:
                              ((user['total_subscribers'] ?? 0) as num).toInt(),
                          followingCount:
                              ((user['total_subscriptions'] ?? 0) as num)
                                  .toInt(),
                          onFollowersTap: _openFollowers,
                          onFollowingTap: _openFollowing,
                          badgeLabel: 'Ваш профиль',
                          badgeIcon: Icons.verified_user_outlined,
                          actions: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () =>
                                          _showEditProfileDialog(user),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      label: const Text('Редактировать'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  OutlinedButton(
                                    onPressed: _showImageSourceDialog,
                                    child: const Icon(
                                        Icons.photo_camera_outlined,
                                        size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _openOrganizerEvents,
                                  icon: const Icon(Icons.event_outlined,
                                      size: 18),
                                  label: const Text('Мои мероприятия'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Мои публикации',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (userId != null)
                  UserPosts(
                    userId: userId,
                    scrollController: _scrollController,
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              ],
            ),
          );
        },
        ),
      ),
    );
  }
}

class NotificationIcon extends StatefulWidget {
  final LkService lkService;

  const NotificationIcon({required this.lkService});

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
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkNotifications();
    });
  }

  Future<void> _checkNotifications() async {
    try {
      final notifications = await widget.lkService.fetchNotifications();
      if (!mounted) return;
      bool notEmpty(String key) {
        final value = notifications[key];
        return value is List && value.isNotEmpty;
      }

      setState(() {
        hasNewNotifications = notEmpty('new_applications') ||
            notEmpty('user_applications_changes') ||
            notEmpty('event_updates');
      });
    } catch (e) {
      debugPrint('Ошибка при проверке уведомлений: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Уведомления',
      icon: Stack(
        children: [
          const Icon(Icons.notifications_outlined),
          if (hasNewNotifications)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
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
