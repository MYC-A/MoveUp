import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/RunningRoute.dart';
import '../../screens/RouteViewScreen.dart';
import 'package:flutter_application_1/widgets/common/osm_tile_layer.dart';
import 'package:flutter_application_1/widgets/common/route_markers.dart';

class RouteMap extends StatefulWidget {
  final RunningRoute route;

  const RouteMap({super.key, required this.route});

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final MapController _mapController = MapController();

  // Кешируем точки один раз, чтобы не пересчитывать на каждом build.
  late final List<LatLng> _points =
      widget.route.points.map((point) => point.coordinates).toList();

  void _zoomToRoute() {
    if (_points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(_points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
        maxZoom: 17.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(child: Text('Маршрут недоступен')),
      );
    }

    return SizedBox(
      height: 250,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RouteViewScreen(route: widget.route),
            ),
          );
        },
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _points.first,
            initialZoom: 13.0,
            onMapReady: _zoomToRoute,
          ),
          children: [
            osmTileLayer(
              retina: MediaQuery.of(context).devicePixelRatio > 1.5,
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: downsampleRoute(_points),
                  strokeWidth: 5.0,
                  color: AppColors.route,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                routeStartMarker(_points.first, size: 38),
                if (_points.length > 1) routeFinishMarker(_points.last, size: 34),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
