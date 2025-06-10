import 'package:latlong2/latlong.dart';

class GpsSmoother {
  final int _bufferSize; // Размер буфера для сглаживания
  final List<LatLng> _positionBuffer =
      []; // Буфер для хранения последних позиций

  GpsSmoother({int bufferSize = 5}) : _bufferSize = bufferSize;

  // Добавление новой позиции в буфер
  LatLng addPosition(LatLng newPosition) {
    _positionBuffer.add(newPosition);
    if (_positionBuffer.length > _bufferSize) {
      _positionBuffer
          .removeAt(0); // Удаляем старую позицию, если буфер переполнен
    }

    // Вычисляем среднюю позицию
    double avgLat =
        _positionBuffer.map((p) => p.latitude).reduce((a, b) => a + b) /
            _positionBuffer.length;
    double avgLng =
        _positionBuffer.map((p) => p.longitude).reduce((a, b) => a + b) /
            _positionBuffer.length;

    return LatLng(avgLat, avgLng);
  }

  // Очистка буфера
  void clear() {
    _positionBuffer.clear();
  }
}
