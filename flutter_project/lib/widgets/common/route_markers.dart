import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_colors.dart';

/// Единый круглый маркер маршрута (как в ленте): цветной круг с белой обводкой
/// и белой иконкой. Используется везде (лента, история, детали, трекер), чтобы
/// маркеры не расходились по стилю.
Marker buildRouteMarker(
  LatLng point, {
  required IconData icon,
  required Color color,
  double size = 34,
}) {
  return Marker(
    point: point,
    width: size,
    height: size,
    child: Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: Icon(icon, color: AppColors.surface, size: size * 0.45),
    ),
  );
}

/// Маркер старта — зелёный бегущий человечек.
Marker routeStartMarker(LatLng point, {double size = 34}) => buildRouteMarker(
      point,
      icon: Icons.directions_run,
      color: AppColors.success,
      size: size,
    );

/// Маркер финиша — синий флажок.
Marker routeFinishMarker(LatLng point, {double size = 34}) => buildRouteMarker(
      point,
      icon: Icons.flag,
      color: AppColors.route,
      size: size,
    );

/// Прореживание точек трека для лёгкой отрисовки на карте (концы сохраняются).
/// Возвращает исходный список, если точек немного.
List<LatLng> downsampleRoute(List<LatLng> points, {int maxPoints = 120}) {
  if (points.length <= maxPoints) return points;
  final step = (points.length - 1) / (maxPoints - 1);
  return List.generate(maxPoints, (i) {
    final idx = (i * step).round().clamp(0, points.length - 1);
    return points[idx];
  });
}
