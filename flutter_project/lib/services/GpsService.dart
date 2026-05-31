import 'package:geolocator/geolocator.dart';

class GpsService {
  Future<Position> getCurrentLocation() async {
    return await Geolocator.getCurrentPosition();
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        // high достаточно для бега и заметно экономнее, чем bestForNavigation.
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(milliseconds: 3000),
      ),
    ).where((position) {
      // Отбрасываем заведомо неточные точки (шум GPS).
      return position.accuracy <= 20;
    });
  }
}
