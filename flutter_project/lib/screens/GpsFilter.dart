import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class GpsFilter {
  // Фильтр точности: удаляет точки с низкой точностью
  static List<Position> filterByAccuracy(
      List<Position> points, double minAccuracy) {
    return points.where((point) => point.accuracy <= minAccuracy).toList();
  }

  // Фильтр скорости: удаляет точки, где скорость превышает порог
  static List<Position> filterBySpeed(List<Position> points, double maxSpeed) {
    final filteredPoints = <Position>[];
    for (var i = 0; i < points.length; i++) {
      if (i == 0 || points[i].speed <= maxSpeed) {
        filteredPoints.add(points[i]);
      }
    }
    return filteredPoints;
  }

  // Фильтр ускорения: удаляет точки, где ускорение превышает порог
  static List<Position> filterByAcceleration(
      List<Position> points, double maxAcceleration) {
    final filteredPoints = <Position>[];
    for (var i = 1; i < points.length; i++) {
      final timeDiff =
          points[i].timestamp.difference(points[i - 1].timestamp).inSeconds;
      if (timeDiff > 0) {
        final acceleration = (points[i].speed - points[i - 1].speed) / timeDiff;
        if (acceleration.abs() <= maxAcceleration) {
          filteredPoints.add(points[i]);
        }
      }
    }
    return filteredPoints;
  }

  // Сворачивание точек: объединяет точки, находящиеся близко друг к другу
  static List<Position> collapsePoints(
      List<Position> points, double maxDistance, Duration maxTime) {
    final collapsedPoints = <Position>[];
    Position? lastAddedPoint;

    for (final point in points) {
      if (lastAddedPoint == null ||
          Geolocator.distanceBetween(
                lastAddedPoint.latitude,
                lastAddedPoint.longitude,
                point.latitude,
                point.longitude,
              ) >
              maxDistance ||
          point.timestamp.difference(lastAddedPoint.timestamp) > maxTime) {
        collapsedPoints.add(point);
        lastAddedPoint = point;
      }
    }
    return collapsedPoints;
  }

  // Медианный фильтр: сглаживает маршрут, удаляя выбросы
  static List<Position> applyMedianFilter(
      List<Position> points, int windowSize) {
    final filteredPoints = <Position>[];
    for (var i = 0; i < points.length; i++) {
      final start = i - windowSize ~/ 2;
      final end = i + windowSize ~/ 2;
      final window = points.sublist(
        start.clamp(0, points.length),
        end.clamp(0, points.length),
      );
      final medianLat = _median(window.map((p) => p.latitude).toList());
      final medianLon = _median(window.map((p) => p.longitude).toList());
      filteredPoints.add(Position(
        latitude: medianLat,
        longitude: medianLon,
        timestamp: points[i].timestamp,
        accuracy: points[i].accuracy,
        altitude: points[i].altitude,
        altitudeAccuracy: points[i].altitudeAccuracy ?? 0.0, // Добавлено
        heading: points[i].heading,
        headingAccuracy: points[i].headingAccuracy ?? 0.0, // Добавлено
        speed: points[i].speed,
        speedAccuracy: points[i].speedAccuracy,
      ));
    }
    return filteredPoints;
  }

  // Вспомогательный метод для вычисления медианы
  static double _median(List<double> values) {
    values.sort();
    final mid = values.length ~/ 2;
    if (values.length % 2 == 1) {
      return values[mid];
    } else {
      return (values[mid - 1] + values[mid]) / 2;
    }
  }
}
