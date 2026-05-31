import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import '../services_api/lk_service.dart';
import '../services_api/EventService.dart';
import '../services_api/auth_service.dart';
import '../services_api/api_error_ui.dart';

/// Полноэкранная форма редактирования профиля — заменяет тесный диалог.
/// Возвращает `true` через Navigator.pop, если профиль был сохранён.
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final LkService _lkService = LkService();
  final EventService _eventService = EventService();
  final AuthService _authService = AuthService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;
  String _city = '';

  List<String> _cities = EventService.fallbackCities;
  bool _saving = false;

  static const int _bioMax = 500;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nameCtrl = TextEditingController(text: (u['full_name'] ?? '').toString());
    _bioCtrl = TextEditingController(text: (u['bio'] ?? '').toString());
    _weightCtrl = TextEditingController(
        text: u['weight'] != null ? '${u['weight']}' : '');
    _heightCtrl = TextEditingController(
        text: u['height'] != null ? '${u['height']}' : '');
    _city = (u['city'] ?? '').toString();
    _loadCities();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await _eventService.getEventCities();
      if (!mounted || cities.isEmpty) return;
      setState(() => _cities = cities);
    } catch (_) {/* остаётся fallback-список */}
  }

  String _norm(String v) => v.trim().toLowerCase().replaceAll('ё', 'е');
  bool _isKnownCity(String v) => _cities.any((c) => _norm(c) == _norm(v));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _lkService.updateProfile(
        fullName: _nameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        city: _city.trim(),
        weight: double.tryParse(_weightCtrl.text.trim().replaceAll(',', '.')),
        height: double.tryParse(_heightCtrl.text.trim().replaceAll(',', '.')),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(title: const Text('Редактирование профиля')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Section(
              title: 'Основное',
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Имя должно быть не короче 3 символов'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _bioCtrl,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _bioMax,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    alignLabelWithHint: true,
                    helperText: 'Маршруты, цели, любимые дистанции',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'Данные для статистики',
              children: [
                // Город — выбор из списка (как в событиях).
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _city),
                  optionsBuilder: (value) {
                    final q = _norm(value.text);
                    if (q.isEmpty) return _cities.take(8);
                    return _cities.where((c) => _norm(c).contains(q)).take(12);
                  },
                  onSelected: (city) => setState(() => _city = city),
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Город',
                        prefixIcon: Icon(Icons.location_city_outlined),
                        helperText: 'Выберите из списка',
                      ),
                      onChanged: (value) => _city = value,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        if (!_isKnownCity(value)) {
                          return 'Выберите город из списка';
                        }
                        return null;
                      },
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Вес, кг',
                          prefixIcon: Icon(Icons.monitor_weight_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final w = double.tryParse(v.replaceAll(',', '.'));
                          if (w == null) return 'Число';
                          if (w < 30 || w > 250) return '30–250 кг';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Рост, см',
                          prefixIcon: Icon(Icons.height),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final h = double.tryParse(v.replaceAll(',', '.'));
                          if (h == null) return 'Число';
                          if (h < 100 || h > 250) return '100–250 см';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'Безопасность',
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Сменить пароль'),
                  ),
                ),
              ],
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
                  decoration:
                      const InputDecoration(labelText: 'Текущий пароль'),
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
                          error =
                              e.toString().replaceFirst('Exception: ', '');
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
}

/// Карточка-секция формы — единый стиль с экраном создания поста.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}
