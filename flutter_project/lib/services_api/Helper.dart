import 'package:intl/intl.dart';

class Helper {
  static String formatDateTime(Object? input) {
    if (input == null) return "Не указано";

    DateTime? dateTime;

    if (input is String) {
      dateTime = DateTime.tryParse(input);
      if (dateTime == null) {
        try {
          // Поддержка нестандартного формата, например, "yyyy-MM-dd HH:mm:ss"
          final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
          dateTime = formatter.parse(input);
        } catch (e) {
          print('Ошибка парсинга даты: $input, ошибка: $e');
        }
      }
      if (dateTime != null) {
        dateTime = dateTime.toLocal();
      }
    } else if (input is DateTime) {
      dateTime = input.toLocal();
    }

    if (dateTime == null) return "Ошибка даты";

    return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
  }
}
