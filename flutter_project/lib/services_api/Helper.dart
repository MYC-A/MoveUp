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

  /// Время мероприятия — «настенное» локальное, выбранное организатором.
  /// В отличие от серверных меток (posts/chat создаются через utcnow()), сервер
  /// хранит время события наивно, БЕЗ перевода в UTC. Поэтому здесь НЕ сдвигаем
  /// часовой пояс — иначе время «уезжает» на величину пояса.
  static DateTime? parseLocalWallClock(Object? input) {
    if (input == null) return null;
    if (input is DateTime) return input;
    if (input is! String) return null;
    final value = input.trim();
    if (value.isEmpty) return null;
    final dt = DateTime.tryParse(value);
    if (dt == null) return null;
    // Если вдруг пришёл суффикс таймзоны (Z/offset) — берём «настенные» поля как
    // есть, без конвертации, чтобы отображать ровно выбранное организатором время.
    return dt.isUtc
        ? DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)
        : dt;
  }

  /// Диапазон дат мероприятия (без сдвига пояса). Однодневное событие не
  /// дублирует дату: «05.06.2026 14:30 – 16:00».
  static String formatLocalDateRange(Object? start, Object? end) {
    final startDt = parseLocalWallClock(start);
    final endDt = parseLocalWallClock(end);

    if (startDt == null && endDt == null) return 'Время не указано';
    if (endDt == null) return DateFormat('dd.MM.yyyy HH:mm').format(startDt!);
    if (startDt == null) return DateFormat('dd.MM.yyyy HH:mm').format(endDt);

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
