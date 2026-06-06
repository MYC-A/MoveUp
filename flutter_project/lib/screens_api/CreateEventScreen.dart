import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:flutter_application_1/services_api/EventTranslations.dart';
import 'package:flutter_application_1/widgets/common/osm_tile_layer.dart';

class CreateEventScreen extends StatefulWidget {
  @override
  _CreateEventScreenState createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final EventService _eventService = EventService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _goalController = TextEditingController();
  final TextEditingController _maxParticipantsController =
      TextEditingController();
  List<String> _cities = EventService.fallbackCities;
  String? _selectedCity;
  bool _isLoadingCities = false;
  String _eventType = 'Бег';
  String _difficulty = 'Новичок';
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isPublic = true;
  static const double _maxRouteDistanceKm = 200;
  static const LatLng _defaultMapCenter = LatLng(55.7558, 37.6176);
  static final Map<String, LatLng> _cityCenters = {
    'москва': const LatLng(55.7558, 37.6176),
    'санкт-петербург': const LatLng(59.9343, 30.3351),
    'новосибирск': const LatLng(55.0084, 82.9357),
    'екатеринбург': const LatLng(56.8389, 60.6057),
    'казань': const LatLng(55.7961, 49.1064),
    'нижний новгород': const LatLng(56.2965, 43.9361),
    'челябинск': const LatLng(55.1644, 61.4368),
    'красноярск': const LatLng(56.0153, 92.8932),
    'самара': const LatLng(53.1959, 50.1002),
    'уфа': const LatLng(54.7388, 55.9721),
    'ростов-на-дону': const LatLng(47.2357, 39.7015),
    'омск': const LatLng(54.9885, 73.3242),
    'краснодар': const LatLng(45.0355, 38.9753),
    'воронеж': const LatLng(51.6608, 39.2003),
    'пермь': const LatLng(58.0105, 56.2502),
    'волгоград': const LatLng(48.708, 44.5133),
    'саратов': const LatLng(51.5336, 46.0343),
    'тюмень': const LatLng(57.153, 65.5343),
    'ижевск': const LatLng(56.8526, 53.2045),
    'иркутск': const LatLng(52.2864, 104.2807),
    'сочи': const LatLng(43.5855, 39.7231),
    'калининград': const LatLng(54.7104, 20.4522),
    'владивосток': const LatLng(43.1155, 131.8855),
    'хабаровск': const LatLng(48.4802, 135.0719),
  };

  final MapController _mapController = MapController();
  final List<LatLng> _routePoints = [];
  List<LatLng> _optimizedRoutePoints = [];
  bool _isOptimizing = false;
  bool _showOptimizedRoute = false;
  double _blueLineDistance = 0;
  double _redLineDistance = 0;
  int _blueLineDuration = 0;
  int _redLineDuration = 0;
  int? _selectedMarkerIndex;
  bool _createGroupChat = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    setState(() {
      _isLoadingCities = true;
    });

    final cities = await _eventService.getEventCities();
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _isLoadingCities = false;
    });
  }

  String _normalizeCityName(String value) {
    return value.trim().toLowerCase().replaceAll('ё', 'е');
  }

  bool _isKnownCity(String? value) {
    if (value == null) return false;
    final normalized = _normalizeCityName(value);
    return _cities.any((city) => _normalizeCityName(city) == normalized);
  }

  void _selectCity(String city) {
    final trimmedCity = city.trim();
    setState(() {
      _selectedCity = trimmedCity;
    });
    _moveMapToCity(trimmedCity);
  }

  void _moveMapToCity(String city) {
    final center = _cityCenters[_normalizeCityName(city)];
    if (center == null) return;

    try {
      _mapController.move(center, 11.5);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(center, 11.5);
      });
    }
  }

  Future<void> _optimizeRoute() async {
    if (_routePoints.length < 2) {
      _showRouteMessage('Добавьте минимум две точки для оптимизации маршрута.');
      return;
    }

    if (_blueLineDistance > _maxRouteDistanceKm) {
      _showRouteTooLongMessage();
      return;
    }

    setState(() {
      _isOptimizing = true;
    });

    try {
      final data = await _eventService.buildRoute(_routePoints, false);
      final coordinates =
          data['features'][0]['geometry']['coordinates'] as List;
      final routeInfo = _extractRouteInfo(data);

      if (routeInfo.distanceKm > _maxRouteDistanceKm) {
        _showRouteTooLongMessage();
        return;
      }

      setState(() {
        _optimizedRoutePoints =
            coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        _showOptimizedRoute = true;
        _redLineDistance = routeInfo.distanceKm;
        _redLineDuration = routeInfo.durationMinutes;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка оптимизации маршрута: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOptimizing = false;
        });
      }
    }
  }

  ({double distanceKm, int durationMinutes}) _extractRouteInfo(
    Map<String, dynamic> route,
  ) {
    if (route['features'] != null && route['features'].isNotEmpty) {
      final segments = route['features'][0]['properties']['segments'] as List;
      final totalDistance = segments.fold<double>(
        0,
        (sum, seg) => sum + ((seg['distance'] as num?)?.toDouble() ?? 0),
      );
      final totalDuration = segments.fold<double>(
        0,
        (sum, seg) => sum + ((seg['duration'] as num?)?.toDouble() ?? 0),
      );

      return (
        distanceKm: totalDistance / 1000,
        durationMinutes: (totalDuration / 60).ceil(),
      );
    }

    return (distanceKm: 0, durationMinutes: 0);
  }

  void _updateBlueLineInfo() {
    if (_routePoints.length > 1) {
      final distance = _eventService.calculateDistance(_routePoints);
      const speed = 5;
      final duration = ((distance / speed) * 60).ceil();

      setState(() {
        _blueLineDistance = distance;
        _blueLineDuration = duration;
      });
    } else {
      setState(() {
        _blueLineDistance = 0;
        _blueLineDuration = 0;
      });
    }
  }

  void _clearRoute() {
    setState(() {
      _routePoints.clear();
      _optimizedRoutePoints = [];
      _selectedMarkerIndex = null;
      _showOptimizedRoute = false;
      _blueLineDistance = 0;
      _redLineDistance = 0;
      _blueLineDuration = 0;
      _redLineDuration = 0;
    });
  }

  bool _isRouteTooLong(List<LatLng> points) {
    return _eventService.calculateDistance(points) > _maxRouteDistanceKm;
  }

  void _showRouteTooLongMessage() {
    _showRouteMessage('Маршрут не должен быть длиннее 200 км.');
  }

  void _showRouteMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  List<LatLng> get _visibleRouteLinePoints {
    if (_showOptimizedRoute && _optimizedRoutePoints.length > 1) {
      return _optimizedRoutePoints;
    }
    return _routePoints;
  }

  List<Marker> _buildRoutePointMarkers() {
    return _routePoints.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;

      return Marker(
        point: point,
        width: 56,
        height: 56,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => _onMarkerTap(index),
          onLongPress: () => _removeRoutePoint(index),
          child: _RoutePointMarker(
            index: index,
            total: _routePoints.length,
            isSelected: _selectedMarkerIndex == index,
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildRouteDirectionMarkers() {
    final points = _visibleRouteLinePoints;
    if (points.length < 2) return [];

    final arrowsCount = points.length <= 8
        ? points.length - 1
        : math.min(6, math.max(2, (points.length / 30).ceil()));
    final usedSegments = <int>{};
    final markers = <Marker>[];

    for (var i = 1; i <= arrowsCount; i++) {
      final segmentIndex = ((points.length - 1) * i / (arrowsCount + 1))
          .floor()
          .clamp(0, points.length - 2)
          .toInt();
      if (!usedSegments.add(segmentIndex)) continue;

      final from = points[segmentIndex];
      final to = points[segmentIndex + 1];
      markers.add(
        Marker(
          point: _midpoint(from, to),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: _RouteDirectionArrow(
            angle: _bearingRadians(from, to),
            color: _showOptimizedRoute ? Colors.red : Colors.blue,
          ),
        ),
      );
    }

    return markers;
  }

  void _removeRoutePoint(int index) {
    setState(() {
      _routePoints.removeAt(index);
      _optimizedRoutePoints = [];
      _selectedMarkerIndex = null;
      _showOptimizedRoute = false;
      _redLineDistance = 0;
      _redLineDuration = 0;
    });
    _updateBlueLineInfo();
  }

  LatLng _midpoint(LatLng from, LatLng to) {
    return LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );
  }

  double _bearingRadians(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return math.atan2(y, x);
  }

  Future<void> _submitForm() async {
    // Проверка обязательных полей
    final errors = <String>[];

    if (_titleController.text.isEmpty) errors.add('Название мероприятия');
    if (!_isKnownCity(_selectedCity)) errors.add('Город из списка');
    if (_maxParticipantsController.text.isEmpty)
      errors.add('Максимум участников');
    if (_startTime == null) errors.add('Время начала');
    if (_endTime == null) errors.add('Время окончания');
    if (_routePoints.length < 2) errors.add('Маршрут (минимум 2 точки)');

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заполните обязательные поля: ${errors.join(", ")}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final maxParticipants = int.tryParse(_maxParticipantsController.text);
    if (maxParticipants == null || maxParticipants <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Укажите корректное количество участников'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Проверка времени: окончание строго позже начала (равенство тоже недопустимо).
    if (!_endTime!.isAfter(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Время окончания должно быть позже времени начала'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Сверяем с серверным временем (часы телефона могут быть неверны), с
    // фоллбеком на локальное время, если запрос не удался.
    final serverNow = await _eventService.getServerTime();
    if (!mounted) return;
    final now = serverNow ?? DateTime.now();
    if (_startTime!.isBefore(now.subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Время начала не может быть в прошлом'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_endTime!.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Время окончания не может быть в прошлом'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Сохраняем именно маршрут по дорогам (геометрию ORS), а не сырые точки —
    // иначе на карте рисуются прямые отрезки между точками («раздельные линии»).
    // Если пользователь не нажал «оптимизировать» — строим маршрут автоматически.
    List<LatLng> routePointsToSave;
    double routeDistance;
    if (_showOptimizedRoute && _optimizedRoutePoints.isNotEmpty) {
      routePointsToSave = _optimizedRoutePoints;
      routeDistance = _redLineDistance;
    } else {
      try {
        final data = await _eventService.buildRoute(_routePoints, false);
        final coordinates =
            data['features'][0]['geometry']['coordinates'] as List;
        routePointsToSave =
            coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        routeDistance = _extractRouteInfo(data).distanceKm;
      } catch (_) {
        // Маршрут не построился (нет сети/непроходимо) — сохраняем сырые точки,
        // чтобы создание не блокировалось.
        routePointsToSave = _routePoints;
        routeDistance = _eventService.calculateDistance(_routePoints);
      }
    }

    if (routeDistance > _maxRouteDistanceKm) {
      _showRouteTooLongMessage();
      return;
    }

    final eventCreate = EventCreate(
      title: _titleController.text,
      description: _descriptionController.text.isEmpty
          ? "Без описания"
          : _descriptionController.text,
      eventType: EventTranslations.getEventTypeValue(
          _eventType), // Преобразование в английское значение
      goal: _goalController.text.isEmpty
          ? "Цель не указана"
          : _goalController.text,
      city: _selectedCity!.trim(),
      startTime: _startTime,
      endTime: _endTime,
      difficulty: EventTranslations.getDifficultyValue(
          _difficulty), // Преобразование в английское значение
      maxParticipants: maxParticipants,
      isPublic: _isPublic,
      routeData: routePointsToSave
          .map((point) => {
                'latitude': point.latitude,
                'longitude': point.longitude,
              })
          .toList(),
      createGroupChat: _createGroupChat,
    );

    try {
      await _eventService.createEvent(eventCreate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Мероприятие успешно создано!')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка создания мероприятия: $e')),
      );
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _startTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _endTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _onMarkerTap(int index) {
    setState(() {
      _selectedMarkerIndex = index;
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    final candidate = List<LatLng>.from(_routePoints);

    if (_selectedMarkerIndex != null) {
      candidate[_selectedMarkerIndex!] = latLng;
    } else {
      candidate.add(latLng);
    }

    if (candidate.length > 1 && _isRouteTooLong(candidate)) {
      _showRouteTooLongMessage();
      return;
    }

    setState(() {
      if (_selectedMarkerIndex != null) {
        _routePoints[_selectedMarkerIndex!] = latLng;
        _selectedMarkerIndex = null;
      } else {
        _routePoints.add(latLng);
      }
      _optimizedRoutePoints = [];
      _showOptimizedRoute = false;
      _redLineDistance = 0;
      _redLineDuration = 0;
    });
    _updateBlueLineInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Создание мероприятия', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.green,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade100, Colors.blue.shade100],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'Название*',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: Icon(Icons.title, color: Colors.green),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Обязательное поле';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: 'Описание',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon:
                                Icon(Icons.description, color: Colors.green),
                          ),
                          maxLines: 3,
                        ),
                        SizedBox(height: 16),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue value) {
                            final query = _normalizeCityName(value.text);
                            if (query.isEmpty) {
                              return _cities.take(8);
                            }
                            return _cities.where((city) {
                              final normalized = _normalizeCityName(city);
                              return normalized.contains(query);
                            }).take(12);
                          },
                          onSelected: _selectCity,
                          fieldViewBuilder: (
                            context,
                            textEditingController,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            return TextFormField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'Город*',
                                helperText: _isLoadingCities
                                    ? 'Загружаем список городов'
                                    : 'Выберите город из списка',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                prefixIcon: Icon(Icons.location_city,
                                    color: Colors.green),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selectedCity =
                                      _isKnownCity(value) ? value.trim() : null;
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _eventType,
                          decoration: InputDecoration(
                            labelText: 'Тип мероприятия',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon:
                                Icon(Icons.directions_run, color: Colors.green),
                          ),
                          items: EventTranslations.eventTypeTranslations.values
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _eventType = value!;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _goalController,
                          decoration: InputDecoration(
                            labelText: 'Цель',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: Icon(Icons.flag, color: Colors.green),
                          ),
                        ),
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _difficulty,
                          decoration: InputDecoration(
                            labelText: 'Уровень сложности',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon:
                                Icon(Icons.terrain, color: Colors.green),
                          ),
                          items: EventTranslations.difficultyTranslations.values
                              .map((difficulty) => DropdownMenuItem(
                                    value: difficulty,
                                    child: Text(difficulty),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _difficulty = value!;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _maxParticipantsController,
                          decoration: InputDecoration(
                            labelText: 'Максимум участников*',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: Icon(Icons.people, color: Colors.green),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Обязательное поле';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                        SwitchListTile(
                          title: Text('Создать групповой чат'),
                          value: _createGroupChat,
                          onChanged: (value) {
                            setState(() {
                              _createGroupChat = value;
                            });
                          },
                          tileColor: Colors.grey[200],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        SizedBox(height: 16),
                        SwitchListTile(
                          title: Text('Публичное мероприятие'),
                          value: _isPublic,
                          onChanged: (value) {
                            setState(() {
                              _isPublic = value;
                            });
                          },
                          tileColor: Colors.grey[200],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        SizedBox(height: 16),
                        Column(
                          children: [
                            ElevatedButton(
                              onPressed: _selectStartTime,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _startTime == null
                                    ? Colors.red.shade300
                                    : Colors.orange,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                minimumSize: Size(double.infinity, 50),
                              ),
                              child: Text(
                                _startTime != null
                                    ? 'Начало: ${DateFormat('dd.MM.yyyy HH:mm').format(_startTime!)}'
                                    : 'Выбрать время начала*',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: _startTime == null
                                        ? FontWeight.bold
                                        : FontWeight.normal),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _selectEndTime,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _endTime == null
                                    ? Colors.red.shade300
                                    : Colors.orange,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                minimumSize: Size(double.infinity, 50),
                              ),
                              child: Text(
                                _endTime != null
                                    ? 'Окончание: ${DateFormat('dd.MM.yyyy HH:mm').format(_endTime!)}'
                                    : 'Выбрать время окончания*',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: _endTime == null
                                        ? FontWeight.bold
                                        : FontWeight.normal),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Маршрут*',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _routePoints.isEmpty
                                      ? Colors.red
                                      : Colors.black,
                                ),
                              ),
                            ),
                            if (_routePoints.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text(
                                  '(минимум 2 точки)',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            if (_routePoints.isNotEmpty)
                              TextButton.icon(
                                onPressed: _clearRoute,
                                icon: Icon(Icons.delete_sweep_outlined),
                                label: Text('Стереть'),
                              ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 400,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _routePoints.isEmpty
                                  ? Colors.red
                                  : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _defaultMapCenter,
                                initialZoom: 13.0,
                                onTap: _onMapTap,
                              ),
                              children: [
                                osmTileLayer(),
                                PolylineLayer(
                                  polylines: [
                                    if (_routePoints.isNotEmpty &&
                                        !_showOptimizedRoute)
                                      Polyline(
                                        points: _routePoints,
                                        color: Colors.blue,
                                        strokeWidth: 4.0,
                                      ),
                                    if (_optimizedRoutePoints.isNotEmpty &&
                                        _showOptimizedRoute)
                                      Polyline(
                                        points: _optimizedRoutePoints,
                                        color: Colors.red,
                                        strokeWidth: 4.0,
                                      ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    ..._buildRouteDirectionMarkers(),
                                    ..._buildRoutePointMarkers(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_routePoints.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Добавьте минимум две точки маршрута',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        SizedBox(height: 8),
                        Text(
                          'Лимит длины маршрута: до 200 км',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Ваш маршрут',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        '${_blueLineDistance.toStringAsFixed(2)} км',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.blue),
                                      ),
                                      Text(
                                        '$_blueLineDuration мин',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.blue),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Оптимизированный',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        '${_redLineDistance.toStringAsFixed(2)} км',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.red),
                                      ),
                                      Text(
                                        '$_redLineDuration мин',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Column(
                          children: [
                            ElevatedButton(
                              onPressed: _isOptimizing ? null : _optimizeRoute,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                minimumSize: Size(double.infinity, 50),
                              ),
                              child: _isOptimizing
                                  ? CircularProgressIndicator(
                                      color: Colors.white)
                                  : Text(
                                      'Оптимизировать маршрут',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                            SizedBox(height: 8),
                            if (_optimizedRoutePoints.isNotEmpty)
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _showOptimizedRoute = !_showOptimizedRoute;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  minimumSize: Size(double.infinity, 50),
                                ),
                                child: Text(
                                  _showOptimizedRoute
                                      ? 'Показать исходный маршрут'
                                      : 'Показать оптимизированный маршрут',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: Text(
                      'Создать мероприятие',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutePointMarker extends StatelessWidget {
  final int index;
  final int total;
  final bool isSelected;

  const _RoutePointMarker({
    required this.index,
    required this.total,
    required this.isSelected,
  });

  bool get _isStart => index == 0;
  bool get _isFinish => total > 1 && index == total - 1;

  @override
  Widget build(BuildContext context) {
    final color = _isStart
        ? Colors.green
        : _isFinish
            ? Colors.blue
            : Colors.deepOrange;
    final icon = _isStart
        ? Icons.play_arrow_rounded
        : _isFinish
            ? Icons.flag_rounded
            : null;
    final label = _isStart
        ? 'Старт'
        : _isFinish
            ? 'Финиш'
            : '${index + 1}';

    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: isSelected ? 1.16 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isStart || _isFinish) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.amber : Colors.white,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: icon == null
                ? Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class _RouteDirectionArrow extends StatelessWidget {
  final double angle;
  final Color color;

  const _RouteDirectionArrow({
    required this.angle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation_rounded,
          color: color,
          size: 18,
        ),
      ),
    );
  }
}
