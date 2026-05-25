import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/RoutePoint.dart';
import 'package:flutter_application_1/models/RunningRoute.dart';
import 'package:flutter_application_1/models_api/post.dart';
import 'package:flutter_application_1/services/StorageService.dart';
import 'package:latlong2/latlong.dart';

Future<void> saveRouteFromPost(BuildContext context, Post post) async {
  if (post.routeData.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Маршрут отсутствует в этом посте')),
    );
    return;
  }

  try {
    final points = post.routeData.map((point) {
      return RoutePoint(
        coordinates: LatLng(
          _toDouble(point['latitude']),
          _toDouble(point['longitude']),
        ),
        timestamp: _parseTimestamp(point['timestamp'], post.createdAt),
      );
    }).toList();

    final route = RunningRoute(
      id: post.id.toString(),
      name: post.content.trim().isNotEmpty
          ? post.content.trim()
          : 'Маршрут ${post.id}',
      points: points,
      distance: post.distance,
      date: post.createdAt,
      duration: Duration(seconds: post.duration),
      description: post.content,
      is_downloaded: 1,
    );

    await StorageService().downloadRoute(route);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Маршрут сохранен успешно')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка при сохранении маршрута: $e')),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}

DateTime _parseTimestamp(dynamic value, DateTime fallback) {
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}
