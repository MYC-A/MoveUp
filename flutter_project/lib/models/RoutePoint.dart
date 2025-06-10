import 'package:latlong2/latlong.dart';

class RoutePoint {
  final LatLng coordinates;
  final DateTime timestamp;

  RoutePoint({
    required this.coordinates,
    required this.timestamp,
  });

  // Преобразование в JSON
  Map<String, dynamic> toJson() => {
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
        'timestamp': timestamp.toIso8601String(),
      };

  // Создание объекта RoutePoint из JSON
  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
        coordinates: LatLng(json['latitude'], json['longitude']),
        timestamp: DateTime.parse(json['timestamp']),
      );
}
