import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              subdomains: ['mt0', 'mt1', 'mt2', 'mt3'],
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points:
                      route.points.map((point) => point.coordinates).toList(),
                  strokeWidth: 4.0,
                  color: Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
