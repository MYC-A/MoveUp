import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/RunningRoute.dart';
import 'dart:async'; // Импорт для StreamSubscription

class RouteViewScreen extends StatefulWidget {
  final RunningRoute route;

  const RouteViewScreen({super.key, required this.route});

  @override
  _RouteViewScreenState createState() => _RouteViewScreenState();
}

class _RouteViewScreenState extends State<RouteViewScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isFollowing = false;
  LatLngBounds? _routeBounds;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _calculateRouteBounds(); // Рассчитываем границы маршрута
    _getCurrentLocation(); // Получаем текущее местоположение
  }

  void _calculateRouteBounds() {
    if (widget.route.points.isEmpty) {
      debugPrint('Маршрут пуст');
      return;
    }

    final validPoints = widget.route.points
        .where((point) =>
            point.coordinates.latitude.isFinite &&
            point.coordinates.longitude.isFinite &&
            point.coordinates.latitude >= -90 &&
            point.coordinates.latitude <= 90 &&
            point.coordinates.longitude >= -180 &&
            point.coordinates.longitude <= 180)
        .toList();

    if (validPoints.isEmpty) {
      debugPrint('Нет валидных точек для маршрута');
      return;
    }

    setState(() {
      _routeBounds = LatLngBounds.fromPoints(
        validPoints.map((point) => point.coordinates).toList(),
      );
      _isMapReady = true; // Карта готова к отрисовке
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Пожалуйста, включите GPS')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Доступ к местоположению отклонен')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Доступ к местоположению отклонен навсегда')),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    _positionStreamSubscription =
        Geolocator.getPositionStream().listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      if (_isFollowing) {
        _mapController.move(_currentPosition!, _mapController.camera.zoom);
      }
    });
  }

  void _toggleFollow() {
    setState(() {
      _isFollowing = !_isFollowing;
    });

    if (_isFollowing && _currentPosition != null) {
      _mapController.move(_currentPosition!, _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validPoints = widget.route.points
        .where((point) =>
            point.coordinates.latitude.isFinite &&
            point.coordinates.longitude.isFinite &&
            point.coordinates.latitude >= -90 &&
            point.coordinates.latitude <= 90 &&
            point.coordinates.longitude >= -180 &&
            point.coordinates.longitude <= 180)
        .toList();

    if (validPoints.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Просмотр маршрута'),
        ),
        body: Center(
          child: Text('Маршрут не содержит корректных точек'),
        ),
      );
    }

    final hasSinglePoint = validPoints.length == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Просмотр маршрута'),
        actions: [
          IconButton(
            icon: Icon(_isFollowing ? Icons.location_on : Icons.location_off),
            onPressed: _toggleFollow,
          ),
        ],
      ),
      body: _isMapReady
          ? FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _routeBounds!.center, // Центр маршрута
                initialZoom: 13.0, // Начальный масштаб
                onMapReady: () async {
                  // Добавляем небольшую задержку перед масштабированием
                  await Future.delayed(Duration(milliseconds: 300));
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: _routeBounds!,
                      padding: EdgeInsets.all(50), // Отступы для границ
                    ),
                  );
                  // Принудительно обновляем карту
                  _mapController.move(
                      _routeBounds!.center, _mapController.camera.zoom);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: ['mt0', 'mt1', 'mt2', 'mt3'],
                ),
                if (!hasSinglePoint)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: validPoints
                            .map((point) => point.coordinates)
                            .toList(),
                        strokeWidth: 4.0,
                        color: Colors.blue.withOpacity(0.7),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_currentPosition != null)
                      Marker(
                        point: _currentPosition!,
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.5),
                                spreadRadius: 3,
                                blurRadius: 7,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Marker(
                      point: validPoints.first.coordinates,
                      width: 80, // Увеличиваем ширину маркера
                      height: 80, // Увеличиваем высоту маркера
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.flag_circle, // Иконка старта
                            color: Colors.green,
                            size: 40,
                          ),
                          SizedBox(
                              height:
                                  8), // Увеличиваем отступ между иконкой и текстом
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2), // Отступы для текста
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withOpacity(0.8), // Фон текста
                              borderRadius:
                                  BorderRadius.circular(4), // Скругление углов
                            ),
                            child: Text(
                              'Старт',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!hasSinglePoint)
                      Marker(
                        point: validPoints.last.coordinates,
                        width: 80, // Увеличиваем ширину маркера
                        height: 80, // Увеличиваем высоту маркера
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.flag_circle, // Иконка финиша
                              color: Colors.red,
                              size: 40,
                            ),
                            SizedBox(
                                height:
                                    8), // Увеличиваем отступ между иконкой и текстом
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2), // Отступы для текста
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.8), // Фон текста
                                borderRadius: BorderRadius.circular(
                                    4), // Скругление углов
                              ),
                              child: Text(
                                'Финиш',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hasSinglePoint)
                      Marker(
                        point: validPoints.first.coordinates,
                        width: 60,
                        height: 60,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.flag_circle, // Иконка финиша
                              color: Colors.red,
                              size: 40,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Финиш',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            )
          : Center(
              child: CircularProgressIndicator(), // Индикатор загрузки
            ),
    );
  }
}
