import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class FullScreenMap extends StatefulWidget {
  final List<dynamic> routeData;

  const FullScreenMap({
    Key? key,
    required this.routeData,
  }) : super(key: key);

  @override
  _FullScreenMapState createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<FullScreenMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomToRoute(List<dynamic> routeData) {
    if (routeData.length == 1) {
      final point = LatLng(
        routeData[0]['latitude'],
        routeData[0]['longitude'],
      );
      _mapController.move(point, 15.0);
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      routeData
          .map((point) => LatLng(point['latitude'], point['longitude']))
          .toList(),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
  }

  // Метод для создания маркера одиночной точки
  Marker _buildSinglePointMarker(LatLng point) {
    return Marker(
      width: 40.0,
      height: 40.0,
      point: point,
      child: Icon(Icons.location_pin, color: Colors.red, size: 40),
    );
  }

  // Метод для создания маркера начала маршрута
  Marker _buildStartMarker(LatLng point) {
    return Marker(
      width: 30.0,
      height: 30.0,
      point: point,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.directions_run, color: Colors.white, size: 16),
      ),
    );
  }

  // Метод для создания маркера конца маршрута
  Marker _buildFinishMarker(LatLng point) {
    return Marker(
      width: 30.0,
      height: 30.0,
      point: point,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.flag, color: Colors.white, size: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startIcon = Icon(
      Icons.run_circle,
      color: Colors.green,
      size: 25,
    );

    final finishIcon = Icon(
      Icons.flag_circle,
      color: Colors.blue,
      size: 25,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Карта маршрута'),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(
            widget.routeData[0]['latitude'],
            widget.routeData[0]['longitude'],
          ),
          initialZoom: 13.0,
          onMapReady: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(Duration(milliseconds: 500), () {
                _zoomToRoute(widget.routeData);
              });
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          if (widget.routeData.length == 1) ...[
            MarkerLayer(
              markers: [
                _buildSinglePointMarker(LatLng(
                  widget.routeData[0]['latitude'],
                  widget.routeData[0]['longitude'],
                )),
              ],
            ),
          ] else ...[
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.routeData
                      .map((point) =>
                          LatLng(point['latitude'], point['longitude']))
                      .toList(),
                  strokeWidth: 4.0,
                  color: Colors.orange,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                _buildStartMarker(LatLng(
                  widget.routeData.first['latitude'],
                  widget.routeData.first['longitude'],
                )),
                _buildFinishMarker(LatLng(
                  widget.routeData.last['latitude'],
                  widget.routeData.last['longitude'],
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
