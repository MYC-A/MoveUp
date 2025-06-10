import 'package:geolocator/geolocator.dart';

class GpsService {
  Future<Position> getCurrentLocation() async {
    return await Geolocator.getCurrentPosition();
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: Duration(milliseconds: 3000),
      ),
    ).where((position) {
      if (position.accuracy > 10) {
        _handleInaccuratePosition(position); // Обработка неподходящей точки
        return false; // Исключаем точку из потока
      }
      _handleInaccuratePositionTrue(position);
      return true; // Включаем точку в поток
    });
  }

  void _handleInaccuratePosition(Position position) {
    print(
        'Неподходящая точка: ${position.latitude}, ${position.longitude} метров; Точность ${position.accuracy}');
    // Здесь можно добавить дополнительную логику, например:
    // - Сохранить точку в локальную базу данных
    // - Отправить точку на сервер для анализа
    // - Показать уведомление пользователю
  }

  void _handleInaccuratePositionTrue(Position position) {
    print(
        'Подходящая точка: ${position.latitude}, ${position.longitude} метров; Точность ${position.accuracy}');
    // Здесь можно добавить дополнительную логику, например:
    // - Сохранить точку в локальную базу данных
    // - Отправить точку на сервер для анализа
    // - Показать уведомление пользователю
  }
}
