import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // Для форматирования даты
import 'RoutePoint.dart'; // Импортируем новый класс
import 'dart:convert';

class RunningRoute {
  final String id;
  String name;
  List<RoutePoint> points;
  double distance;
  DateTime date;
  Duration duration;
  String description; //  Описание маршрута
  List<String> photos; // Фото к маршруту
  int is_downloaded;

  RunningRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.distance,
    required this.date,
    this.is_downloaded = 0,
    this.duration = Duration.zero,
    this.description = '', // По умолчанию пустое описание
    this.photos = const [], // По умолчанию пустой список фотографий
  });

  // Метод для добавления фотографии
  void addPhoto(String photoPath) {
    if (photos.length < 10) {
      photos.add(photoPath);
    } else {
      throw Exception('Максимальное количество фотографий достигнуто');
    }
  }

  // Добавление новой точки в маршрут
  void addPoint(LatLng coordinates) {
    if (points.isNotEmpty && points.last.coordinates == coordinates) {
      print('Точка дублируется, не добавляется.');
      return;
    }

    print('Добавление точки: $coordinates');
    final newPoint = RoutePoint(
      coordinates: coordinates,
      timestamp: DateTime.now(),
    );

    if (points.isNotEmpty) {
      final newDistance =
          _calculateDistance(points.last.coordinates, coordinates);
      print('Расчет расстояния до последней точки: $newDistance м');
      if (newDistance > 1) {
        // Измените порог при необходимости
        points.add(newPoint);
        distance += newDistance;
        _updateDuration();
        print('Точка добавлена, обновленная дистанция: $distance м');
      } else {
        print('Точка слишком близко, не добавляется.');
      }
    } else {
      points.add(newPoint);
      print('Первая точка добавлена.');
    }
  }

  // Очистка маршрута
  void clear() {
    print('Очистка маршрута.');
    points.clear();
    distance = 0.0;
    duration = Duration.zero;
  }

  // Обновление продолжительности маршрута
  void _updateDuration() {
    if (points.length >= 2) {
      final startTime = points.first.timestamp;
      final endTime = points.last.timestamp;
      duration = endTime.difference(startTime);
      print('Обновлена продолжительность маршрута: $duration');
    }
  }

  // Расчет дистанции между двумя точками
  double _calculateDistance(LatLng point1, LatLng point2) {
    final Distance distanceCalculator = Distance();
    final calculatedDistance = distanceCalculator.as(
      LengthUnit.Meter,
      point1,
      point2,
    );
    print('Расчет расстояния: $calculatedDistance м между $point1 и $point2');
    return calculatedDistance;
  }

  // Преобразование в JSON
  Map<String, dynamic> toJson() {
    try {
      final json = {
        'id': id,
        'name': name,
        'points': points.map((point) => point.toJson()).toList(),
        'distance': distance,
        'date': date.toIso8601String(),
        'duration': duration.inSeconds,
        'description': description, // Сохраняем описание
        'photos': jsonEncode(photos), // Сохраняем фотографии как JSON
      };
      print('Сериализация RunningRoute в JSON: $json');
      return json;
    } catch (e) {
      print('Ошибка при сериализации RunningRoute: $e');
      rethrow;
    }
  }

  // Создание объекта Route из JSON
  factory RunningRoute.fromJson(Map<String, dynamic> json) {
    try {
      print('Десериализация RunningRoute из JSON: $json');
      final route = RunningRoute(
        id: json['id'],
        name: json['name'],
        points: (json['points'] as List)
            .map((point) => RoutePoint.fromJson(point))
            .toList(),
        distance: json['distance'],
        date: DateTime.parse(json['date']),
        duration: Duration(seconds: json['duration']),
        description: json['description'] ?? '', // Загружаем описание
        photos: json['photos'] != null
            ? List<String>.from(jsonDecode(json['photos']))
            : [], // Загружаем фотографии
      );
      print('Успешная десериализация RunningRoute: $route');
      return route;
    } catch (e, stackTrace) {
      print('Ошибка при десериализации RunningRoute: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Форматирование даты для отображения
  String get formattedDate => DateFormat('dd.MM.yyyy HH:mm').format(date);

  // Форматирование продолжительности для отображения
  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
