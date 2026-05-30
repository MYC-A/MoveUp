import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services_api/post_service.dart';
import '../services_api/api_error_ui.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/widgets/common/osm_tile_layer.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';

class CreatePostWithoutRouteScreen extends StatefulWidget {
  @override
  _CreatePostWithoutRouteScreenState createState() =>
      _CreatePostWithoutRouteScreenState();
}

class _CreatePostWithoutRouteScreenState
    extends State<CreatePostWithoutRouteScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final PostService _postService = PostService();
  final ImagePicker _picker = ImagePicker();

  List<String> _photos = [];
  LatLng? _selectedLocation;
  bool _showMap = false;
  bool _isSearching = false;
  bool _isSaving = false;
  final MapController _mapController = MapController();

  /// Дебаунс «живого» поиска по мере ввода (соблюдаем лимит Nominatim).
  Timer? _searchDebounce;

  /// Список результатов поиска (каждый элемент — Map<String, dynamic> из Nominatim)
  List<Map<String, dynamic>> _searchResults = [];

  /// User-Agent для Nominatim. Политика сервиса требует идентифицировать
  /// приложение реальным значением — иначе запросы могут отклоняться (HTTP 403).
  static const String _userAgent = 'MoveUp/1.0 (com.moveup.app; support@moveup.app)';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _descriptionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // Живой поиск: запускаем запрос спустя паузу после ввода (>= 3 символов).
  void _onSearchChanged() {
    if (!_showMap) return;
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 3) {
      if (_searchResults.isNotEmpty) {
        setState(() => _searchResults = []);
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), _searchLocation);
  }

  // Функция для очистки запроса
  String cleanQuery(String query) {
    // Удаляем все символы, кроме букв (включая «ё»), цифр и пробелов.
    String cleaned = query.replaceAll(RegExp(r'[^а-яА-ЯёЁa-zA-Z0-9\s]'), '');
    // Приводим к нижнему регистру
    cleaned = cleaned.toLowerCase();
    // Заменяем множественные пробелы на один
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    // Удаляем слова короче 3 символов
    List<String> words =
        cleaned.split(' ').where((word) => word.length >= 3).toList();
    // Объединяем обратно
    return words.join(' ').trim();
  }

  // Функция для вторичного/третичного поиска при пустых результатах
  String fallbackQuery(String query, bool firstWordOnly) {
    List<String> words = query.split(' ');
    if (firstWordOnly && words.isNotEmpty) {
      return words[0];
    }
    if (words.length > 1) {
      return words.sublist(0, words.length - 1).join(' ');
    }
    return query;
  }

  Future<void> _addPhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _photos.add(pickedFile.path);
      });
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  Future<void> _savePost() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      List<Map<String, dynamic>> routeData = [];
      if (_selectedLocation != null) {
        routeData = [
          {
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ];
      }

      await _postService.createPost(
        content: _descriptionController.text,
        distance: 0.0,
        duration: 0,
        routeData: routeData,
        photoPaths: _photos,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост успешно создан!')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleMapVisibility() {
    setState(() {
      _showMap = !_showMap;
      if (!_showMap) {
        // Очищаем результаты поиска и сбрасываем метку
        _searchResults.clear();
        _selectedLocation = null;
      }
    });
  }

  void _setMarker(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _searchResults.clear();
    });
  }

  /// Один запрос к Nominatim. Возвращает разобранный список (или пустой),
  /// бросает исключение только при сетевой/серверной ошибке.
  Future<List<Map<String, dynamic>>> _queryNominatim(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?format=json&limit=8&accept-language=ru'
      '&q=${Uri.encodeQueryComponent(trimmed)}',
    );
    final response = await http.get(
      url,
      headers: {
        'Accept-Language': 'ru',
        'User-Agent': _userAgent,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Nominatim HTTP ${response.statusCode}');
    }

    // Важно: декодируем как UTF-8, иначе кириллица в названиях ломается.
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => <String, dynamic>{
              'display_name': item['display_name'],
              'lat': item['lat'],
              'lon': item['lon'],
            })
        .where((item) => item['lat'] != null && item['lon'] != null)
        .toList();
  }

  Future<void> _searchLocation() async {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // 1) Сначала ищем по исходному запросу — Nominatim сам разбирает адреса.
      var results = await _queryNominatim(raw);

      // 2) Если пусто — пробуем «очищенный» запрос и постепенные упрощения.
      if (results.isEmpty) {
        final cleaned = cleanQuery(raw);
        if (cleaned.isNotEmpty && cleaned != raw.toLowerCase()) {
          results = await _queryNominatim(cleaned);
        }
        if (results.isEmpty && cleaned.contains(' ')) {
          results = await _queryNominatim(fallbackQuery(cleaned, false));
        }
        if (results.isEmpty && cleaned.contains(' ')) {
          results = await _queryNominatim(fallbackQuery(cleaned, true));
        }
      }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Место не найдено. Уточните запрос или выберите точку на карте.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка поиска места: $e');
      if (!mounted) return;
      setState(() {
        _searchResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось выполнить поиск. Попробуйте позже.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _selectResult(int index) {
    final item = _searchResults[index];
    final latitude = double.tryParse(item['lat'] ?? '');
    final longitude = double.tryParse(item['lon'] ?? '');
    if (latitude != null && longitude != null) {
      setState(() {
        _selectedLocation = LatLng(latitude, longitude);
        _mapController.move(_selectedLocation!, 15.0);
        _searchResults.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Новый пост'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _savePost,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(_isSaving ? 'Публикуем…' : 'Опубликовать'),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Описание
            _Section(
              title: 'Описание',
              child: TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Поделитесь мыслями о пробежке…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Фотографии
            _Section(
              title: 'Фотографии',
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                ),
                itemCount: _photos.length + 1,
                itemBuilder: (context, index) {
                  if (index == _photos.length) {
                    return _AddPhotoTile(onTap: _addPhoto);
                  }
                  return _PhotoTile(
                    path: _photos[index],
                    onRemove: () => _removePhoto(index),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Метка на карте
            _Section(
              title: 'Метка на карте',
              trailing: Switch(
                value: _showMap,
                onChanged: (_) => _toggleMapVisibility(),
              ),
              child: _showMap ? _buildMapBlock() : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Поле поиска вместе со списком подсказок
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск места',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textMuted, size: 20),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _searchLocation,
                        ),
                ),
                onSubmitted: (_) => _searchLocation(),
              ),
              if (_searchResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      return ListTile(
                        leading: const Icon(Icons.location_on_outlined,
                            size: 20, color: AppColors.textMuted),
                        title: Text(
                          item['display_name'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        dense: true,
                        onTap: () => _selectResult(index),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Карта
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: SizedBox(
            height: 300,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(55.7558, 37.6176),
                initialZoom: 13.0,
                onTap: (_, LatLng location) {
                  _setMarker(location);
                },
              ),
              children: [
                osmTileLayer(),
                if (_selectedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 40.0,
                        height: 40.0,
                        point: _selectedLocation!,
                        child: const Icon(
                          Icons.location_pin,
                          color: AppColors.danger,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),

        // Координаты выбранного места
        if (_selectedLocation != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Выбрано: '
                    '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                    '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Карточка-секция формы — единый стиль (поверхность, рамка, заголовок).
class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? child;

  const _Section({required this.title, this.trailing, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.sm),
            child!,
          ],
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPhotoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                size: 26, color: AppColors.textMuted),
            SizedBox(height: AppSpacing.xxs),
            Text(
              'Добавить',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _PhotoTile({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.cover),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
