import 'dart:convert';
import 'dart:math';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

import 'api_client.dart';
import 'api_exception.dart';

class EventService {
  final String baseUrl = AppConfig.apiBaseUrl;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final String openRouteApiKey = AppConfig.openRouteServiceApiKey;

  static const List<String> fallbackCities = [
    'Москва',
    'Санкт-Петербург',
    'Новосибирск',
    'Екатеринбург',
    'Казань',
    'Нижний Новгород',
    'Челябинск',
    'Красноярск',
    'Самара',
    'Уфа',
    'Ростов-на-Дону',
    'Омск',
    'Краснодар',
    'Воронеж',
    'Пермь',
    'Волгоград',
    'Саратов',
    'Тюмень',
    'Ижевск',
    'Иркутск',
    'Сочи',
    'Калининград',
    'Владивосток',
    'Хабаровск',
  ];

  // Построение маршрута через OpenRouteService
  Future<Map<String, dynamic>> buildRoute(
      List<LatLng> points, bool roundTrip) async {
    if (points.length < 2) {
      throw Exception('Добавьте минимум две точки для построения маршрута.');
    }
    if (openRouteApiKey.isEmpty) {
      throw Exception(
          'OPEN_ROUTE_API_KEY не задан. Запустите Flutter с --dart-define=OPEN_ROUTE_API_KEY=...');
    }

    // Формируем координаты для запроса
    var coordinates =
        points.map((point) => [point.longitude, point.latitude]).toList();

    // Если выбран круговой маршрут, добавляем первую точку в конец массива
    if (roundTrip) {
      coordinates.add(coordinates[0]);
    }

    // Тело запроса
    final requestBody = {
      "coordinates": coordinates,
      "elevation": true,
    };

    try {
      // Запрос к API OpenRouteService
      final response = await http.post(
        Uri.parse(
            'https://api.openrouteservice.org/v2/directions/foot-walking/geojson'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': openRouteApiKey,
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          return data;
        } else {
          throw Exception(
              'Не удалось построить маршрут. Проверьте точки и попробуйте снова.');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Ошибка при построении маршрута: ${errorData['error']['message']}');
      }
    } catch (e) {
      throw Exception('Ошибка при выполнении запроса: $e');
    }
  }

  // Расчет расстояния между точками (в км)
  double calculateDistance(List<LatLng> points) {
    const R = 6371; // Радиус Земли в км
    double totalDistance = 0;

    for (int i = 0; i < points.length - 1; i++) {
      final lat1 =
          points[i].latitude * (pi / 180); // Преобразуем градусы в радианы
      final lng1 = points[i].longitude * (pi / 180);
      final lat2 = points[i + 1].latitude * (pi / 180);
      final lng2 = points[i + 1].longitude * (pi / 180);

      final dLat = lat2 - lat1;
      final dLng = lng2 - lng1;

      final a = sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);

      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      totalDistance += R * c;
    }

    return totalDistance;
  }

  // Получить список мероприятий
  // Получить список мероприятий
  Future<List<Event>> getEvents({
    required int skip,
    required int limit,
    String sortBy = 'id',
    String sortOrder = 'desc',
    String? query,
    String? city,
    bool availableOnly = false,
    bool activeOnly = true,
  }) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final queryParameters = <String, String>{
      'skip': '$skip',
      'limit': '$limit',
      'sort_by': sortBy,
      'sort_order': sortOrder,
      'format': 'json',
      'available_only': '$availableOnly',
      'active_only': '$activeOnly',
    };
    if (query != null && query.trim().isNotEmpty) {
      queryParameters['q'] = query.trim();
    }
    if (city != null && city.trim().isNotEmpty) {
      queryParameters['city'] = city.trim();
    }

    final url = Uri.parse('$baseUrl/events/')
        .replace(queryParameters: queryParameters);

    final response = await Api.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
    );

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = jsonDecode(responseBody);
      return data.map((json) => Event.fromJson(json)).toList();
    } else {
      throw ApiException.fromResponse(response);
    }
  }

  Future<List<String>> getEventCities() async {
    try {
      final response = await Api.get(Uri.parse('$baseUrl/events/cities'));
      if (response.statusCode == 200) {
        final String responseBody = utf8.decode(response.bodyBytes);
        final List<dynamic> data = jsonDecode(responseBody);
        return data.map((city) => city.toString()).toList();
      }
    } catch (_) {
      // Фоллбек нужен, чтобы форма создания не блокировалась без backend.
    }
    return fallbackCities;
  }

  /// Серверное время (UTC). Возвращает null, если запрос не удался —
  /// тогда клиент валидирует по локальным часам.
  Future<DateTime?> getServerTime() async {
    try {
      final response =
          await Api.get(Uri.parse('$baseUrl/events/server_time'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final raw = data['now']?.toString();
        if (raw != null) {
          return DateTime.tryParse(raw)?.toLocal();
        }
      }
    } catch (_) {
      // Игнорируем — будет фоллбек на локальное время.
    }
    return null;
  }

  Future<void> participateEvent(int eventId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final url = Uri.parse('$baseUrl/events/$eventId/participate');
    final response = await Api.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Удаление мероприятия (только организатор)
  Future<void> deleteEvent(int eventId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final url = Uri.parse('$baseUrl/events/$eventId');
    final response = await Api.delete(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  // Создание мероприятия
  Future<EventCreate> createEvent(EventCreate event) async {
    final token = await storage.read(key: 'access_token');
    if (event.routeData.isEmpty) {
      throw ApiException(
          ApiErrorKind.unknown, 'Маршрут обязателен для создания мероприятия');
    }
    if (token == null) {
      throw ApiException(
          ApiErrorKind.unauthorized, 'Сессия истекла. Войдите снова.');
    }

    final url = Uri.parse('$baseUrl/events/create');
    final response = await Api.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
      body: jsonEncode({
        'title': event.title,
        'description': event.description,
        'event_type': event.eventType,
        'goal': event.goal,
        'city': event.city,
        'start_time': event.startTime?.toIso8601String(),
        'end_time': event.endTime?.toIso8601String(),
        'difficulty': event.difficulty,
        'max_participants': event.maxParticipants,
        'is_public': event.isPublic,
        'route_data': event.routeData
            .map((point) => {
                  'latitude': point['latitude'],
                  'longitude': point['longitude'],
                  'timestamp': point['timestamp']?.toIso8601String(),
                })
            .toList(),
        'create_group_chat': event.createGroupChat,
      }),
    );

    if (response.statusCode == 200) {
      return EventCreate.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException.fromResponse(response);
    }
  }
}
