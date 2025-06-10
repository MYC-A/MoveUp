import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/GpsService.dart';
import '../services/StorageService.dart';
import '../models/RunningRoute.dart';
import 'RouteHistoryScreen.dart';
import '../models/RoutePoint.dart';
import 'package:permission_handler/permission_handler.dart';

// Класс для фильтрации GPS-данных
class GpsFilter {
  // Фильтр точности: удаляет точки с низкой точностью
  static List<Position> filterByAccuracy(
      List<Position> points, double minAccuracy) {
    return points.where((point) => point.accuracy <= minAccuracy).toList();
  }

  // Интерполяция: добавляет промежуточные точки между существующими
  static List<Position> interpolatePoints(
      List<Position> points, double maxDistance) {
    final interpolatedPoints = <Position>[];

    for (var i = 0; i < points.length - 1; i++) {
      final point1 = points[i];
      final point2 = points[i + 1];
      interpolatedPoints.add(point1);

      final distance = Geolocator.distanceBetween(
        point1.latitude,
        point1.longitude,
        point2.latitude,
        point2.longitude,
      );

      if (distance > maxDistance) {
        final steps = (distance / maxDistance).ceil();
        for (var j = 1; j < steps; j++) {
          final fraction = j / steps;
          interpolatedPoints
              .add(_interpolatePosition(point1, point2, fraction));
        }
      }
    }

    if (points.isNotEmpty) {
      interpolatedPoints.add(points.last);
    }

    return interpolatedPoints;
  }

  static Position _interpolatePosition(
      Position point1, Position point2, double fraction) {
    return Position(
      latitude:
          point1.latitude + (point2.latitude - point1.latitude) * fraction,
      longitude:
          point1.longitude + (point2.longitude - point1.longitude) * fraction,
      timestamp: point1.timestamp
          .add(point2.timestamp.difference(point1.timestamp) * fraction),
      accuracy: _average(point1.accuracy, point2.accuracy),
      altitude: _average(point1.altitude, point2.altitude),
      altitudeAccuracy: _average(
          point1.altitudeAccuracy ?? 0.0, point2.altitudeAccuracy ?? 0.0),
      heading: _average(point1.heading, point2.heading),
      headingAccuracy: _average(
          point1.headingAccuracy ?? 0.0, point2.headingAccuracy ?? 0.0),
      speed: _average(point1.speed, point2.speed),
      speedAccuracy: _average(point1.speedAccuracy, point2.speedAccuracy),
    );
  }

  static double _average(double a, double b) => (a + b) / 2;

  // Скользящее среднее: усредняет координаты по окну
  static List<Position> applyMovingAverage(
      List<Position> points, int windowSize) {
    if (points.isEmpty || windowSize < 1) return points;

    final averagedPoints = <Position>[];
    final halfWindow = windowSize ~/ 2;

    for (var i = 0; i < points.length; i++) {
      final start = (i - halfWindow).clamp(0, points.length - 1);
      final end = (i + halfWindow + 1).clamp(0, points.length);

      final window = points.sublist(start, end);
      averagedPoints.add(_averagePosition(points[i], window));
    }

    return averagedPoints;
  }

  static Position _averagePosition(Position base, List<Position> window) {
    final avgLat =
        window.map((p) => p.latitude).reduce((a, b) => a + b) / window.length;
    final avgLon =
        window.map((p) => p.longitude).reduce((a, b) => a + b) / window.length;

    return Position(
      latitude: avgLat,
      longitude: avgLon,
      timestamp: base.timestamp,
      accuracy: base.accuracy,
      altitude: base.altitude,
      altitudeAccuracy: base.altitudeAccuracy,
      heading: base.heading,
      headingAccuracy: base.headingAccuracy,
      speed: base.speed,
      speedAccuracy: base.speedAccuracy,
    );
  }

  // Фильтр Калмана
  static List<Position> applyKalmanFilter(List<Position> points) {
    final filteredPoints = <Position>[];
    double? latEstimate, lonEstimate;
    double latVariance = 1.0, lonVariance = 1.0;
    const processNoise = 1e-5, measurementNoise = 1e-1;

    for (final point in points) {
      if (latEstimate == null || lonEstimate == null) {
        latEstimate = point.latitude;
        lonEstimate = point.longitude;
      } else {
        latVariance += processNoise;
        lonVariance += processNoise;

        final kalmanGainLat = latVariance / (latVariance + measurementNoise);
        final kalmanGainLon = lonVariance / (lonVariance + measurementNoise);

        latEstimate += kalmanGainLat * (point.latitude - latEstimate);
        lonEstimate += kalmanGainLon * (point.longitude - lonEstimate);

        latVariance *= (1 - kalmanGainLat);
        lonVariance *= (1 - kalmanGainLon);
      }

      filteredPoints.add(Position(
        latitude: latEstimate,
        longitude: lonEstimate,
        timestamp: point.timestamp,
        accuracy: point.accuracy,
        altitude: point.altitude,
        altitudeAccuracy: point.altitudeAccuracy,
        heading: point.heading,
        headingAccuracy: point.headingAccuracy,
        speed: point.speed,
        speedAccuracy: point.speedAccuracy,
      ));
    }

    return filteredPoints;
  }

  // Сворачивание точек
  static List<Position> collapsePoints(
      List<Position> points, double maxDistance, Duration maxTime) {
    final collapsedPoints = <Position>[];
    Position? lastPoint;

    for (final point in points) {
      if (lastPoint == null ||
          Geolocator.distanceBetween(lastPoint.latitude, lastPoint.longitude,
                  point.latitude, point.longitude) >
              maxDistance ||
          point.timestamp.difference(lastPoint.timestamp) > maxTime) {
        collapsedPoints.add(point);
        lastPoint = point;
      }
    }

    return collapsedPoints;
  }
}

class LiveTrackerScreen extends StatefulWidget {
  final RunningRoute? route;

  const LiveTrackerScreen({super.key, this.route});

  @override
  _LiveTrackerScreenState createState() => _LiveTrackerScreenState();
}

class _LiveTrackerScreenState extends State<LiveTrackerScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Сохраняем состояние экрана
  final GpsService _gpsService = GpsService();
  final StorageService _storageService = StorageService();
  RunningRoute? _route;
  bool _isTracking = false;
  bool _isPaused = false;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _trackingTimer;
  Duration _trackingDuration = Duration.zero;
  bool _followUser = true;
  final MapController _mapController = MapController();
  List<LatLng> _accumulatedPoints = [];
  bool _isWidgetActive = false; // Флаг для управления состоянием виджета
  bool _hasCenteredOnce = true;

  @override
  void initState() {
    super.initState();
    // Инициализация только при первом создании экрана
    if (_isWidgetActive) {
      startBackgroundService();
      _route = widget.route;
      if (_route != null) {
        _trackingDuration = _route!.duration;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkLocationPermission();
      if (_currentPosition == null && mounted) {
        setState(() {
          _loadWorldMap();
        });
      }
    });
  }

  void _loadWorldMap() {
    // Загружаем карту с центром в Челябинске
    setState(() {
      _currentPosition = LatLng(55.1644, 61.4368); // Координаты Челябинска
    });
    _mapController.move(_currentPosition!,
        1.0); // Зум для города (10.0 - примерный уровень для обзора города)
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await _gpsService.getCurrentLocation();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      if (!_hasCenteredOnce) {
        _centerMapOnUser(); // <-- Центрируем только один раз
        _hasCenteredOnce = true; // <-- Помечаем, что уже центрировали
      }
      _positionStreamSubscription = _gpsService.getPositionStream().listen(
        (position) {
          final newPosition = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentPosition = newPosition;
          });
          if (_followUser) {
            _smoothMoveTo(newPosition);
          }
          if (_isTracking && !_isPaused) {
            _addPoint(newPosition);
          }
        },
        onError: (error) {
          print('Ошибка в потоке позиций: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка получения местоположения')),
          );
        },
      );
    } catch (e) {
      print('Ошибка получения текущего местоположения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка получения местоположения')),
      );
    }
  }

  void startBackgroundService() {
    final service = FlutterBackgroundService();
    service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
    service.startService();
  }

  static void onStart(ServiceInstance service) async {
    // Устанавливаем режим foreground (для Android)
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Трекер маршрута",
        content: "Запущено",
      );
    }

    // Обработка команд
    service.on('closeNotification').listen((event) {
      if (service is AndroidServiceInstance) {
        service.stopSelf(); // Закрываем уведомление
      }
    });

    // Таймер для обновления данных
    Timer.periodic(Duration(seconds: 1), (timer) async {
      bool isRunning = await FlutterBackgroundService().isRunning();
      if (!isRunning) {
        timer.cancel();
        return;
      }

      // Отправляем данные в уведомление
      service.invoke(
        'update',
        {
          "title": "Трекер маршрута",
          "content":
              "Дистанция: 0 м, Время: 00:00:00", // Заглушка, замените на реальные данные
        },
      );
    });
  }

  void showNotification() {
    final service = FlutterBackgroundService();
    service.invoke(
      'update',
      {
        "title": "Трекер маршрута",
        "content":
            "Дистанция: ${_route?.distance.toStringAsFixed(2) ?? 0} м, Время: ${_trackingDuration.inHours.toString().padLeft(2, '0')}:${(_trackingDuration.inMinutes % 60).toString().padLeft(2, '0')}:${(_trackingDuration.inSeconds % 60).toString().padLeft(2, '0')}",
      },
    );
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Новая проверка: если GPS выключен
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS отключен')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Доступ к геопозиции обязателен для работы')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Разрешение отклонено'),
          content: Text('Включите разрешение в настройках'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('Отмена')),
            TextButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
                Navigator.pop(context);
              },
              child: Text('Настройки'),
            ),
          ],
        ),
      );
      return;
    }

    // Всё ок — можем получить координаты
    await _getCurrentLocation();
  }

  void _reinitializeGPS() async {
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

    // Получаем новую позицию
    await _getCurrentLocation();

    // После обновления позиции — центрируем карту
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMapOnUser(); // <-- Здесь
    });
  }
/*
  Future<void> _getCurrentLocation() async {
    Position position = await _gpsService.getCurrentLocation();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    

    _positionStreamSubscription =
        _gpsService.getPositionStream().listen((position) {
      final newPosition = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = newPosition;
      });

      if (_followUser) {
        _smoothMoveTo(newPosition);
      }

      if (_isTracking && !_isPaused) {
        _addPoint(newPosition);
      }
    });
  }
  */

  void _smoothMoveTo(LatLng newPosition) {
    const int steps = 10;
    const Duration duration = Duration(milliseconds: 500);
    final LatLng startPosition = _mapController.camera.center;

    final double latStep =
        (newPosition.latitude - startPosition.latitude) / steps;
    final double lngStep =
        (newPosition.longitude - startPosition.longitude) / steps;

    int step = 0;
    Timer.periodic(duration ~/ steps, (timer) {
      if (step >= steps) {
        timer.cancel();
        return;
      }

      final LatLng intermediatePosition = LatLng(
        startPosition.latitude + latStep * step,
        startPosition.longitude + lngStep * step,
      );

      _mapController.move(intermediatePosition, _mapController.camera.zoom);
      step++;
    });
  }

  void _addPoint(LatLng newPoint) {
    _accumulatedPoints.add(newPoint);
    if (_accumulatedPoints.length >= 3) {
      _processAndDrawPoints();
      _accumulatedPoints.clear();
    }
  }

  void _processAndDrawPoints() {
    final processedPoints = _processPoints(_accumulatedPoints);
    _updateRoute(processedPoints);
  }

  List<LatLng> _processPoints(List<LatLng> points) {
    final processedPoints = <LatLng>[];
    for (var i = 0; i < points.length - 1; i++) {
      final point1 = points[i];
      final point2 = points[i + 1];
      processedPoints.add(point1);

      if (i > 0) {
        final previousPoint = points[i - 1];
        final angle = _calculateAngle(previousPoint, point1, point2);
        if (angle.abs() > 10) {
          final midPoint = LatLng(
            (point1.latitude + point2.latitude) / 2,
            (point1.longitude + point2.longitude) / 2,
          );
          processedPoints.add(midPoint);
        }
      }
    }
    processedPoints.add(points.last);
    return processedPoints;
  }

  double _calculateAngle(LatLng p1, LatLng p2, LatLng p3) {
    final bearing1 = _calculateBearing(p1, p2);
    final bearing2 = _calculateBearing(p2, p3);
    return bearing2 - bearing1;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (pi / 180);
    final lon1 = start.longitude * (pi / 180);
    final lat2 = end.latitude * (pi / 180);
    final lon2 = end.longitude * (pi / 180);

    final y = sin(lon2 - lon1) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);
    return atan2(y, x) * (180 / pi);
  }

  void _updateRoute(List<LatLng> processedPoints) {
    setState(() {
      for (final point in processedPoints) {
        final routePoint = RoutePoint(
          coordinates: point,
          timestamp: DateTime.now(),
        );
        _route!.addPoint(point);
      }
    });
  }

  void _startTracking() async {
    final status = await Permission.location.status;
    if (!status.isGranted) {
      await Permission.location.request();
    }

    if (await Permission.location.isGranted) {
      setState(() {
        _route = RunningRoute(
          id: DateTime.now().toString(),
          name: 'Новый маршрут',
          points: [],
          distance: 0.0,
          date: DateTime.now(),
        );
        _isTracking = true;
        _isPaused = false;
        _isWidgetActive = true; // Активируем виджет
        _trackingDuration = Duration.zero;
        _trackingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
          setState(() {
            _trackingDuration += Duration(seconds: 1);
          });
          showNotification(); // Обновляем уведомление каждую секунду
        });
      });

      startBackgroundService(); // Запускаем фоновый сервис
      if (_currentPosition != null) {
        _route!.addPoint(_currentPosition!);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Разрешение на доступ к местоположению не предоставлено')),
      );
    }
  }

  void _pauseTracking() {
    setState(() {
      _isPaused = true;
    });
    _positionStreamSubscription?.pause();
    _trackingTimer?.cancel();
  }

  void _resumeTracking() {
    setState(() {
      _isPaused = false;
    });
    _positionStreamSubscription?.resume();
    _trackingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _trackingDuration += Duration(seconds: 1);
      });
    });
  }

  void _stopAndSaveRoute() {
    // 1) Завершить трекинг
    setState(() {
      _isTracking = false;
      _isPaused = false;
      _isWidgetActive = false;
    });
    _positionStreamSubscription?.cancel();
    _trackingTimer?.cancel();
    FlutterBackgroundService().invoke('stopService');
    FlutterBackgroundService().invoke('closeNotification');

    // 2) Если нет движения — сразу сообщить и выйти
    final movedDistance = _route?.distance ?? 0.0;
    if (_route == null || movedDistance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Движение не обнаружено — маршрут не сохранён')),
      );
      _clearRoute();
      return;
    }

    // 3) Если всё ок — спросить пользователя
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сохранить маршрут?'),
        content: Text(
            'Дистанция: ${movedDistance.toStringAsFixed(0)} м. Сохранить?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearRoute();
            },
            child: Text('Нет'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _saveRoute();
            },
            child: Text('Да'),
          ),
        ],
      ),
    );
  }

  void _clearRoute() {
    setState(() {
      _route = null;
    });
  }

  Future<void> _saveRoute() async {
    // Дополнительная страховка: вдруг сюда кто-то добрался без движения
    final movedDistance = _route?.distance ?? 0.0;
    if (_route == null || movedDistance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Нечего сохранять: нет пройденного пути')),
      );
      _clearRoute();
      return;
    }

    // Фильтруем и сжимаем точки
    final positions = _route!.points
        .map((pt) => Position(
              latitude: pt.coordinates.latitude,
              longitude: pt.coordinates.longitude,
              timestamp: pt.timestamp,
              accuracy: 15.0,
              altitude: 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
            ))
        .toList();

    final averaged = GpsFilter.applyMovingAverage(positions, 3);
    //final interpolated = GpsFilter.interpolatePoints(averaged, 10.0);
    final collapsed =
        GpsFilter.collapsePoints(averaged, 2.0, Duration(seconds: 60));

    _route!.points = collapsed
        .map((pos) => RoutePoint(
            coordinates: LatLng(pos.latitude, pos.longitude),
            timestamp: pos.timestamp))
        .toList();

    // Запрос имени
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('Название маршрута'),
          content: TextField(
              controller: ctrl,
              decoration: InputDecoration(hintText: 'Введите название')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: Text('Сохранить')),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Маршрут не сохранён: имя не указано')),
      );
      _clearRoute();
      return;
    }

    // Сохраняем
    _route!.name = name;
    await _storageService.saveRoute(_route!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Маршрут сохранён')),
    );
    _clearRoute();
  }

  void _centerMapOnUser() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _mapController.camera.zoom);
      setState(() {
        _followUser = true;
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  double _calculateCalories() {
    const double caloriesPerKmPerKg = 0.75; // Коэффициент сжигания калорий
    const double userWeight = 70.0; // Вес пользователя в кг
    double distanceInKm = _route != null ? _route!.distance / 1000 : 0.0;
    return distanceInKm * userWeight * caloriesPerKmPerKg;
  }

  bool _isRecording = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Трекер маршрута'),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => RouteHistoryScreen()),
            ),
          ),
        ],
      ),
      body: _currentPosition == null
          ? _buildLoadingIndicator()
          : Column(
              children: [
                if (_route != null) _buildStatsPanel(),
                Expanded(child: _buildMap()),
              ],
            ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 16),
          Text(
            'Поиск GPS сигнала...',
            style: TextStyle(color: Colors.grey),
          )
        ],
      ),
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            Icons.directions_run,
            _route!.distance >= 1000
                ? '${(_route!.distance / 1000).toStringAsFixed(2)} км'
                : '${_route!.distance.toStringAsFixed(2)} м',
            'Дистанция',
          ),
          _buildStatItem(
            Icons.timer,
            '${_trackingDuration.inHours.toString().padLeft(2, '0')}:'
                '${(_trackingDuration.inMinutes % 60).toString().padLeft(2, '0')}:'
                '${(_trackingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
            'Время',
          ),
          _buildStatItem(
            Icons.local_fire_department,
            '${_calculateCalories().toStringAsFixed(0)} ккал',
            'Калории',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.blue[800]),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition!,
        initialZoom: 16.0,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) setState(() => _followUser = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
          subdomains: ['mt0', 'mt1', 'mt2', 'mt3'],
          userAgentPackageName: 'com.example.runTracker',
        ),
        if (_route != null && _route!.points.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _route!.points.map((p) => p.coordinates).toList(),
                strokeWidth: 4.0,
                color: Colors.blue,
                borderColor: Colors.blue.withOpacity(0.2),
                borderStrokeWidth: 6.0,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              width: 40.0,
              height: 40.0,
              point: _currentPosition!,
              child: Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFloatingActions() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Для перезапуска GPS (было gps_fixed)
        FloatingActionButton(
          heroTag: 'gps_reinit',
          onPressed: _reinitializeGPS,
          child: Icon(Icons.place,
              size: 28, color: Colors.blueAccent), // "Обновление" с акцентом
        ),

        SizedBox(height: 8),

// Для центрирования карты
        FloatingActionButton(
          heroTag: 'map_center',
          onPressed: _centerMapOnUser,
          child: Icon(Icons.location_searching,
              size: 28, color: Colors.deepPurple), // "Фокус" вместо геолокации
        ),
        SizedBox(height: 8),
        if (_isTracking)
          FloatingActionButton(
            heroTag: 'stop_tracking',
            backgroundColor: Colors.red,
            onPressed: _stopAndSaveRoute,
            child: Icon(Icons.stop, size: 28),
          ),
        SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'start_stop',
          onPressed: _isTracking
              ? (_isPaused ? _resumeTracking : _pauseTracking)
              : _startTracking,
          child: Icon(
            _isTracking
                ? (_isPaused ? Icons.play_arrow : Icons.pause)
                : Icons.directions_run,
            size: 28,
          ),
        ),
      ],
    );
  }
}
