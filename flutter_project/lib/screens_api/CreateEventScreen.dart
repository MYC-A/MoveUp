import 'package:flutter/material.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:flutter_application_1/services_api/EventTranslations.dart';

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
  String _eventType = 'Бег';
  String _difficulty = 'Новичок';
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isPublic = true;
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

  Future<void> _optimizeRoute() async {
    if (_routePoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Добавьте минимум две точки для оптимизации маршрута.')),
      );
      return;
    }

    setState(() {
      _isOptimizing = true;
    });

    try {
      final data = await _eventService.buildRoute(_routePoints, false);
      final coordinates =
          data['features'][0]['geometry']['coordinates'] as List;
      setState(() {
        _optimizedRoutePoints =
            coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        _showOptimizedRoute = true;
        _updateRouteInfo(data);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка оптимизации маршрута: $e')),
      );
    } finally {
      setState(() {
        _isOptimizing = false;
      });
    }
  }

  void _updateRouteInfo(Map<String, dynamic> route) {
    if (route['features'] != null && route['features'].isNotEmpty) {
      final segments = route['features'][0]['properties']['segments'];
      final totalDistance =
          segments.fold(0.0, (sum, seg) => sum + seg['distance']);
      final totalDuration =
          segments.fold(0.0, (sum, seg) => sum + seg['duration']);

      setState(() {
        _redLineDistance = totalDistance / 1000; // в км
        _redLineDuration = (totalDuration / 60).ceil(); // в минутах
      });
    }
  }

  void _updateBlueLineInfo() {
    if (_routePoints.length > 1) {
      final distance = _eventService.calculateDistance(_routePoints);
      const speed = 5; // Скорость 5 км/ч
      final duration = ((distance / speed) * 60).ceil(); // Время в минутах

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

  Future<void> _submitForm() async {
    // Проверка обязательных полей
    final errors = <String>[];

    if (_titleController.text.isEmpty) errors.add('Название мероприятия');
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

    // Проверка времени
    if (_endTime!.isBefore(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Время окончания должно быть позже времени начала'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final routePointsToSave =
        _showOptimizedRoute && _optimizedRoutePoints.isNotEmpty
            ? _optimizedRoutePoints
            : _routePoints;

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
      startTime: _startTime,
      endTime: _endTime,
      difficulty: EventTranslations.getDifficultyValue(
          _difficulty), // Преобразование в английское значение
      maxParticipants: int.parse(_maxParticipantsController.text),
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
      print("_createGroupChat отправлен: $_createGroupChat");
      await _eventService.createEvent(eventCreate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Мероприятие успешно создано!')),
      );
      Navigator.pop(context);
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
    if (_selectedMarkerIndex != null) {
      setState(() {
        _routePoints[_selectedMarkerIndex!] = latLng;
        _selectedMarkerIndex = null;
        _updateBlueLineInfo();
        _showOptimizedRoute = false;
      });
      _optimizeRoute();
    } else {
      setState(() {
        _routePoints.add(latLng);
        _updateBlueLineInfo();
        _showOptimizedRoute = false;
      });
    }
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
                            print("_createGroupChat: $value");
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
                            Text('Маршрут*',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _routePoints.isEmpty
                                        ? Colors.red
                                        : Colors.black)),
                            if (_routePoints.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text('(минимум 2 точки)',
                                    style: TextStyle(color: Colors.red)),
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
                              options: MapOptions(
                                initialCenter: LatLng(55.7558, 37.6176),
                                initialZoom: 13.0,
                                onTap: _onMapTap,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: ['a', 'b', 'c'],
                                ),
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
                                  markers: _routePoints
                                      .asMap()
                                      .entries
                                      .map(
                                        (entry) => Marker(
                                          point: entry.value,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _onMarkerTap(entry.key),
                                            onLongPress: () {
                                              setState(() {
                                                _routePoints
                                                    .removeAt(entry.key);
                                                _updateBlueLineInfo();
                                                _showOptimizedRoute = false;
                                              });
                                            },
                                            child: Icon(
                                              Icons.location_on,
                                              color: _selectedMarkerIndex ==
                                                      entry.key
                                                  ? Colors.blue
                                                  : Colors.red,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
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
