import 'package:latlong2/latlong.dart';

class Event {
  final int id;
  final String title;
  final String? description;
  final String eventType;
  final String? goal;
  final DateTime? startTime;
  final DateTime? endTime;
  final String difficulty;
  final int maxParticipants;
  final bool isPublic;
  final int organizerId;
  final int availableSeats;
  final List<Map<String, dynamic>> routeData;

  Event({
    required this.id,
    required this.title,
    this.description,
    required this.eventType,
    this.goal,
    this.startTime,
    this.endTime,
    required this.difficulty,
    required this.maxParticipants,
    required this.isPublic,
    required this.organizerId,
    required this.availableSeats,
    required this.routeData,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      eventType: json['event_type'],
      goal: json['goal'],
      startTime: json['start_time'] != null
          ? DateTime.parse(json['start_time'])
          : null,
      endTime:
          json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      difficulty: json['difficulty'],
      maxParticipants: json['max_participants'],
      isPublic: json['is_public'],
      organizerId: json['organizer_id'],
      availableSeats: json['available_seats'],
      routeData: (json['route_data'] as List?)
              ?.map((point) => {
                    'latitude': point['latitude'] as double,
                    'longitude': point['longitude'] as double,
                    'timestamp': point['timestamp'] != null
                        ? DateTime.parse(point['timestamp'])
                        : null,
                  })
              .toList() ??
          [],
    );
  }

  List<LatLng> get routePoints {
    return routeData
        .map((point) => LatLng(point['latitude'], point['longitude']))
        .toList();
  }
}

class EventCreate {
  final String title;
  final String? description;
  final String eventType;
  final String? goal;
  final DateTime? startTime;
  final DateTime? endTime;
  final String difficulty;
  final int maxParticipants;
  final bool isPublic;
  final List<Map<String, dynamic>> routeData;
  final bool createGroupChat;

  EventCreate({
    required this.title,
    this.description,
    required this.eventType,
    this.goal,
    this.startTime,
    this.endTime,
    required this.difficulty,
    required this.maxParticipants,
    required this.isPublic,
    required this.routeData,
    this.createGroupChat = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'event_type': eventType,
      'goal': goal,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'difficulty': difficulty,
      'max_participants': maxParticipants,
      'is_public': isPublic,
      'route_data': routeData
          .map((point) => {
                'latitude': point['latitude'],
                'longitude': point['longitude'],
                'timestamp': point['timestamp']?.toIso8601String(),
              })
          .toList(),
      'create_group_chat': createGroupChat,
    };
  }

  factory EventCreate.fromJson(Map<String, dynamic> json) {
    return EventCreate(
      title: json['title'],
      description: json['description'],
      eventType: json['event_type'],
      goal: json['goal'],
      startTime: json['start_time'] != null
          ? DateTime.parse(json['start_time'])
          : null,
      endTime:
          json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      difficulty: json['difficulty'],
      maxParticipants: json['max_participants'],
      isPublic: json['is_public'],
      routeData: (json['route_data'] as List)
          .map((point) => {
                'latitude': point['latitude'] as double,
                'longitude': point['longitude'] as double,
                'timestamp': point['timestamp'] != null
                    ? DateTime.parse(point['timestamp'])
                    : null,
              })
          .toList(),
      createGroupChat: json['create_group_chat'] ?? false,
    );
  }
}
