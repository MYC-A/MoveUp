import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services_api/post_service.dart';
import 'package:http/http.dart' as http;

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
  final MapController _mapController = MapController();

  /// Список результатов поиска (каждый элемент — Map<String, dynamic> из Nominatim)
  List<Map<String, dynamic>> _searchResults = [];

  /// Заголовок User-Agent для Nominatim (замените на подходящий)
  static const String _userAgent = 'myFlutterApp/1.0 (contact@myapp.com)';

  // Функция для очистки запроса
  String cleanQuery(String query) {
    // Удаляем все символы, кроме букв, цифр и пробелов
    String cleaned = query.replaceAll(RegExp(r'[^а-яА-Яa-zA-Z0-9\s]'), '');
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Пост успешно создан!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка создания поста: $e')),
      );
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

  Future<void> _searchLocation() async {
    setState(() {
      _isSearching = true;
      _searchResults.clear();
    });

    String query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
      });
      return;
    }

    try {
      // Очищаем запрос
      String cleanedQuery = cleanQuery(query);

      // Основной запрос
      var url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=$cleanedQuery&accept-language=ru');
      var response = await http.get(
        url,
        headers: {
          'Accept-Language': 'ru',
          'User-Agent': _userAgent,
        },
      );

      if (response.statusCode == 200) {
        var results = json.decode(response.body) as List<dynamic>;
        if (results.isEmpty && cleanedQuery.contains(' ')) {
          // Вторичный запрос: убрать последнее слово
          cleanedQuery = fallbackQuery(cleanedQuery, false);
          url = Uri.parse(
              'https://nominatim.openstreetmap.org/search?format=json&q=$cleanedQuery&accept-language=ru');
          response = await http.get(
            url,
            headers: {
              'Accept-Language': 'ru',
              'User-Agent': _userAgent,
            },
          );
          results = json.decode(response.body) as List<dynamic>;

          if (results.isEmpty && cleanedQuery.contains(' ')) {
            // Третичный запрос: только первое слово
            cleanedQuery = fallbackQuery(cleanedQuery, true);
            url = Uri.parse(
                'https://nominatim.openstreetmap.org/search?format=json&q=$cleanedQuery&accept-language=ru');
            response = await http.get(
              url,
              headers: {
                'Accept-Language': 'ru',
                'User-Agent': _userAgent,
              },
            );
            results = json.decode(response.body) as List<dynamic>;
          }
        }

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as List<dynamic>;
          if (data.isNotEmpty) {
            setState(() {
              _searchResults = data.map((item) {
                return {
                  'display_name': item['display_name'],
                  'lat': item['lat'],
                  'lon': item['lon'],
                };
              }).toList();
            });
          } else {
            setState(() {
              _searchResults.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Место не найдено. Попробуйте уточнить запрос или выберите место на карте.',
                ),
              ),
            );
          }
        } else if (response.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ошибка 403. Проверьте User-Agent (требуется корректный идентификатор).',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка поиска: ${response.statusCode}')),
          );
        }
      } else if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка 403. Проверьте User-Agent (требуется корректный идентификатор).',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка поиска: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
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
      appBar: AppBar(
        title: Text('Создать пост без маршрута'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _savePost,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Описание
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 16),

            // Фотографии
            Text(
              'Фотографии',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _photos.length + 1,
              itemBuilder: (context, index) {
                if (index == _photos.length) {
                  return GestureDetector(
                    onTap: _addPhoto,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.add, size: 40),
                    ),
                  );
                } else {
                  return Stack(
                    children: [
                      Image.file(
                        File(_photos[index]),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removePhoto(index),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
            SizedBox(height: 16),

            // Переключатель показа карты и поиска
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Добавить метку на карту',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _showMap,
                  onChanged: (value) {
                    _toggleMapVisibility();
                  },
                ),
              ],
            ),

            if (_showMap) ...[
              SizedBox(height: 16),

              // Поле поиска вместе со списком подсказок
              Stack(
                children: [
                  // Этот контейнер задаёт фон и отступы для поля поиска и подсказок
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Само поле ввода
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Поиск места',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: InputBorder.none,
                            suffixIcon: _isSearching
                                ? Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(Icons.search),
                                    onPressed: _searchLocation,
                                  ),
                          ),
                          onSubmitted: (_) => _searchLocation(),
                        ),

                        // Список подсказок внизу поля
                        if (_searchResults.isNotEmpty)
                          Container(
                            // Максимальная высота контейнера с подсказками
                            constraints: BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final item = _searchResults[index];
                                return ListTile(
                                  title: Text(
                                    item['display_name'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                ],
              ),

              SizedBox(height: 16),

              // Карта
              Container(
                height: 300,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(55.7558, 37.6176),
                    initialZoom: 13.0,
                    onTap: (_, LatLng location) {
                      _setMarker(location);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: ['a', 'b', 'c'],
                    ),
                    if (_selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 40.0,
                            height: 40.0,
                            point: _selectedLocation!,
                            child: Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Координаты выбранного места
              if (_selectedLocation != null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Выбрано место: '
                    '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                    '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
