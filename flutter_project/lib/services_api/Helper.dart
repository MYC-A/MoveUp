import 'package:intl/intl.dart';

class Helper {
  /// Парсит дату-время, пришедшее от сервера.
  ///
  /// Бэкенд отдаёт время в UTC, но в наивном виде (isoformat без суффикса
  /// таймзоны). Dart по умолчанию трактует такую строку как локальное время,
  /// из-за чего время «уезжает» на величину часового пояса. Поэтому если в
  /// строке нет таймзоны — считаем её UTC и переводим в локальный пояс.
  static DateTime? parseServerDateTime(Object? input) {
    if (input == null) return null;

    if (input is DateTime) return input.toLocal();

    if (input is! String) return null;

    final value = input.trim();
    if (value.isEmpty) return null;

    final hasTimezone = RegExp(r'(z|Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
    // Пробел между датой и временем заменяем на 'T', чтобы корректно добавить 'Z'.
    final isoValue = value.contains(' ') && !value.contains('T')
        ? value.replaceFirst(' ', 'T')
        : value;
    final normalized = hasTimezone ? isoValue : '${isoValue}Z';

    return DateTime.tryParse(normalized)?.toLocal();
  }

  static String formatDateTime(Object? input) {
    if (input == null) return "Не указано";

    final dateTime = parseServerDateTime(input);
    if (dateTime == null) return "Ошибка даты";

    return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
  }

  /// Форматирует диапазон дат. Если начало и конец приходятся на один день —
  /// дата не дублируется: «05.06.2026 14:30 – 16:00». Так строка короче и
  /// помещается на узких экранах.
  static String formatDateRange(Object? start, Object? end) {
    final startDt = parseServerDateTime(start);
    final endDt = parseServerDateTime(end);

    if (startDt == null && endDt == null) return 'Время не указано';
    if (endDt == null) return formatDateTime(start);
    if (startDt == null) return formatDateTime(end);

    final startStr = DateFormat('dd.MM.yyyy HH:mm').format(startDt);
    final sameDay = startDt.year == endDt.year &&
        startDt.month == endDt.month &&
        startDt.day == endDt.day;

    if (sameDay) {
      return '$startStr – ${DateFormat('HH:mm').format(endDt)}';
    }
    return '$startStr – ${DateFormat('dd.MM.yyyy HH:mm').format(endDt)}';
  }
}
