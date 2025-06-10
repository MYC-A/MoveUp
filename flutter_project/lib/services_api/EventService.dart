import 'dart:convert';
import 'dart:math';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

class EventService {
  final String baseUrl = 'http://91.200.84.206/api'; // Для Android-эмулятора
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final String openRouteApiKey =
      '5b3ce3597851110001cf6248fc87794625ca407fa03a6dac7017f830'; // API-ключ

  // Построение маршрута через OpenRouteService
  Future<Map<String, dynamic>> buildRoute(
      List<LatLng> points, bool roundTrip) async {
    if (points.length < 2) {
      throw Exception('Добавьте минимум две точки для построения маршрута.');
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
  }) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse(
        '$baseUrl/events/?skip=$skip&limit=$limit&sort_by=$sortBy&sort_order=$sortOrder&format=json');
    print('Requesting URL: $url');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'users_access_token=$token',
      },
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final String responseBody = utf8.decode(response.bodyBytes);
      final List<dynamic> data = jsonDecode(responseBody);
      return data.map((json) => Event.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка загрузки мероприятий: ${response.statusCode}');
    }
  }

  Future<void> participateEvent(int eventId) async {
    final token = await storage.read(key: 'access_token');
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final url = Uri.parse('$baseUrl/events/$eventId/participate');
    final response = await http.post(
      url,
      headers: {'Cookie': 'users_access_token=$token'},
    );

    final String responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      return;
    } else {
      try {
        final dynamic errorData = jsonDecode(responseBody);
        final String errorMessage = errorData['detail'] ?? 'Неизвестная ошибка';
        throw Exception(errorMessage);
      } catch (e) {
        throw Exception('Ошибка: ${response.statusCode} - $responseBody');
      }
    }
  }

  // Создание мероприятия
  Future<EventCreate> createEvent(EventCreate event) async {
    final token = await storage.read(key: 'access_token');
    if (event.routeData.isEmpty) {
      throw Exception('Маршрут обязателен для создания мероприятия');
    }
    if (token == null) {
      throw Exception('Токен не найден');
    }

    print("Отправлен: ${event.createGroupChat}");

    final url = Uri.parse('$baseUrl/events/create');
    final response = await http.post(
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
      throw Exception('Ошибка создания мероприятия: ${response.body}');
    }
  }
}
