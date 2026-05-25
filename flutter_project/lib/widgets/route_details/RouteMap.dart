import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/RunningRoute.dart';
import '../../screens/RouteViewScreen.dart';

class RouteMap extends StatelessWidget {
  final RunningRoute route;
  final MapController _mapController = MapController();

  RouteMap({super.key, required this.route}) {
    Future.delayed(Duration(milliseconds: 500), _zoomToRoute);
  }

  void _zoomToRoute() {
    if (route.points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(
      route.points.map((point) => point.coordinates).toList(),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RouteViewScreen(route: route),
            ),
          );
        },
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: route.points.first.coordinates,
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: ['a', 'b', 'c'],
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points:
                      route.points.map((point) => point.coordinates).toList(),
                  strokeWidth: 4.0,
                  color: AppColors.route,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                _routeMarker(
                  route.points.first.coordinates,
                  'Старт',
                  AppColors.success,
                ),
                if (route.points.length > 1)
                  _routeMarker(
                    route.points.last.coordinates,
                    'Финиш',
                    AppColors.danger,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Marker _routeMarker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 66,
      height: 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_pin, color: color, size: 30),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
