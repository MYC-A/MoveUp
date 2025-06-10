import 'package:latlong2/latlong.dart';

class AdaptiveMovingAverageFilter {
  int minWindowSize;
  int maxWindowSize;
  double speedThreshold; // Порог скорости для изменения размера окна
  List<LatLng> _buffer = [];

  AdaptiveMovingAverageFilter({
    this.minWindowSize = 3,
    this.maxWindowSize = 10,
    this.speedThreshold = 2.0, // в м/с
  });

  LatLng filter(LatLng newPoint) {
    _buffer.add(newPoint);
    if (_buffer.length > maxWindowSize) {
      _buffer.removeAt(0);
    }

    // Адаптация размера окна в зависимости от скорости
    int windowSize = minWindowSize;
    if (_buffer.length >= 2) {
      double speed = const Distance().as(
        LengthUnit.Meter,
        _buffer[_buffer.length - 2],
        _buffer[_buffer.length - 1],
      );
      if (speed > speedThreshold) {
        windowSize = maxWindowSize;
      }
    }

    double avgLat = 0.0;
    double avgLng = 0.0;
    for (var point in _buffer.sublist(_buffer.length - windowSize)) {
      avgLat += point.latitude;
      avgLng += point.longitude;
    }
    avgLat /= windowSize;
    avgLng /= windowSize;

    return LatLng(avgLat, avgLng);
  }
}
