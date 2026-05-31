import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Единый сервис геокодирования через Nominatim (поиск места и обратное
/// определение города). Убирает дублирование URL/User-Agent/utf8-разбора по
/// экранам. Политика Nominatim требует валидного User-Agent.
class GeocodingService {
  static const String _userAgent =
      'MoveUp/1.0 (com.moveup.app; support@moveup.app)';
  static const Duration _timeout = Duration(seconds: 8);

  Map<String, String> get _headers => {
        'Accept-Language': 'ru',
        'User-Agent': _userAgent,
      };

  // Очистка запроса: оставляем буквы (с «ё»), цифры и пробелы; режем короткие слова.
  String _cleanQuery(String query) {
    String cleaned = query.replaceAll(RegExp(r'[^а-яА-ЯёЁa-zA-Z0-9\s]'), '');
    cleaned = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final words = cleaned.split(' ').where((w) => w.length >= 3).toList();
    return words.join(' ').trim();
  }

  String _fallbackQuery(String query, bool firstWordOnly) {
    final words = query.split(' ');
    if (firstWordOnly && words.isNotEmpty) return words[0];
    if (words.length > 1) return words.sublist(0, words.length - 1).join(' ');
    return query;
  }

  /// Один запрос к Nominatim search. Бросает только при сетевой/серверной ошибке.
  Future<List<Map<String, dynamic>>> _query(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?format=json&limit=8&accept-language=ru'
      '&q=${Uri.encodeQueryComponent(trimmed)}',
    );
    final response = await http.get(url, headers: _headers).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Nominatim HTTP ${response.statusCode}');
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => <String, dynamic>{
              'display_name': item['display_name'],
              'lat': item['lat'],
              'lon': item['lon'],
            })
        .where((item) => item['lat'] != null && item['lon'] != null)
        .toList();
  }

  /// Поиск места: сначала по исходному запросу, затем по упрощённым вариантам.
  Future<List<Map<String, dynamic>>> search(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return [];
    var results = await _query(trimmed);
    if (results.isEmpty) {
      final cleaned = _cleanQuery(trimmed);
      if (cleaned.isNotEmpty && cleaned != trimmed.toLowerCase()) {
        results = await _query(cleaned);
      }
      if (results.isEmpty && cleaned.contains(' ')) {
        results = await _query(_fallbackQuery(cleaned, false));
      }
      if (results.isEmpty && cleaned.contains(' ')) {
        results = await _query(_fallbackQuery(cleaned, true));
      }
    }
    return results;
  }

  /// Обратное геокодирование точки в название города. null при любой ошибке
  /// или таймауте — город необязателен и не должен блокировать сценарий.
  Future<String?> reverseCity(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&zoom=10&accept-language=ru&lat=$lat&lon=$lon',
      );
      final response =
          await http.get(url, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final address = decoded['address'];
      if (address is! Map) return null;
      for (final key in ['city', 'town', 'village', 'municipality', 'state']) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    } catch (e) {
      debugPrint('reverseCity: $e');
      return null;
    }
  }
}
